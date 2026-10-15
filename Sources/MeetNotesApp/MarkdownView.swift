import AppKit
import MeetNotesNotes
import SwiftUI

/// Notatka Summary jako JEDEN `NSTextView` tylko do odczytu (D6; odbiór T13 uwaga 4): zaznaczanie przez wszystkie akapity,
/// Cmd-A / Cmd-C. Bez własnego przewijania — wysokość z `sizeThatFits`, przewija `ScrollView` widoku.
/// Typografia (macos.md §11.2) w `MarkdownBlocks.attributed`; kolory to tokeny DesignSystem (`NSColor(Color)` zostaje dynamiczny).
struct MarkdownView: NSViewRepresentable {
    let blocks: [MarkdownBlock]

    final class Coordinator { var shown: [MarkdownBlock]? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let v = NSTextView(usingTextLayoutManager: false) // TextKit 1: pomiar wysokości przez layoutManager
        v.isEditable = false
        v.isSelectable = true
        v.drawsBackground = false
        v.isRichText = true
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0 // lewa krawędź tekstu = krawędź kolumny (jak tytuł)
        v.textContainer?.widthTracksTextView = true
        v.isVerticallyResizable = false
        v.isHorizontallyResizable = false
        return v
    }

    func updateNSView(_ v: NSTextView, context: Context) {
        // Tylko przy zmianie treści — inaczej każde przerysowanie rodzica gubi zaznaczenie.
        guard context.coordinator.shown != blocks else { return }
        context.coordinator.shown = blocks
        var style = NoteStyle()
        style.text = NSColor(Color.mnText)
        style.secondary = NSColor(Color.mnText2)
        style.marker = NSColor(Color.mnText3)
        v.textStorage?.setAttributedString(MarkdownBlocks.attributed(blocks, style: style))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: NSTextView, context: Context) -> CGSize? {
        guard let lm = v.layoutManager, let tc = v.textContainer else { return nil }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 640 // 640 = kolumna spotkania (§11.2)
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        return CGSize(width: width, height: ceil(lm.usedRect(for: tc).height))
    }
}
