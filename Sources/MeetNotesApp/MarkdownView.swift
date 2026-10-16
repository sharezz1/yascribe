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
        v.invalidateIntrinsicContentSize() // nowa treść (Regenerate) → nowa wysokość
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: NSTextView, context: Context) -> CGSize? {
        measure(v, proposal: proposal)
    }
}

/// Wysokość tekstu przy proponowanej szerokości (brak propozycji → 640 = kolumna spotkania, §11.2).
/// Uwaga 7 z odbioru: pomiar przestawiał kontener na szerokość sondy SwiftUI; gdy ramka widoku się potem nie zmieniła,
/// `widthTracksTextView` nie przywracał szerokości i notatka łamała się na ~250 pt. Po pomiarze kontener wraca do ramki.
@MainActor
private func measure(_ v: NSTextView, proposal: ProposedViewSize, minHeight: CGFloat = 0) -> CGSize? {
    guard let lm = v.layoutManager, let tc = v.textContainer else { return nil }
    let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 640
    tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    lm.ensureLayout(for: tc)
    let height = ceil(lm.usedRect(for: tc).height + 2 * v.textContainerInset.height)
    if v.bounds.width > 0 { tc.containerSize = NSSize(width: v.bounds.width - 2 * v.textContainerInset.width, height: .greatestFiniteMagnitude) }
    return CGSize(width: width, height: max(height, minHeight))
}

/// Edytowalny tekst bez własnego przewijania (uwaga 7): rośnie z treścią, przewija `ScrollView` widoku spotkania.
/// Zapis przy każdej zmianie przez `text` (autozapis My notes jak wcześniej w `TextEditor`).
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 0
    var minHeight: CGFloat = 0
    var accessibilityLabel: String

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(_ text: Binding<String>) { self.text = text }
        func textDidChange(_ n: Notification) {
            guard let v = n.object as? NSTextView else { return }
            text.wrappedValue = v.string
            v.invalidateIntrinsicContentSize() // SwiftUI pyta ponownie o `sizeThatFits`
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator($text) }

    func makeNSView(context: Context) -> NSTextView {
        let v = NSTextView(usingTextLayoutManager: false)
        v.isEditable = true
        v.isSelectable = true
        v.isRichText = false
        v.allowsUndo = true
        v.drawsBackground = false
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = true
        v.isVerticallyResizable = false
        v.isHorizontallyResizable = false
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        let font = NSFont.systemFont(ofSize: fontSize)
        v.font = font
        v.textColor = NSColor(Color.mnText)
        v.insertionPointColor = NSColor(Color.mnText)
        v.defaultParagraphStyle = para
        v.typingAttributes = [.font: font, .foregroundColor: NSColor(Color.mnText), .paragraphStyle: para]
        v.string = text
        v.delegate = context.coordinator
        v.setAccessibilityLabel(accessibilityLabel)
        return v
    }

    func updateNSView(_ v: NSTextView, context: Context) {
        context.coordinator.text = $text
        // Tylko gdy treść przyszła z zewnątrz — inaczej każde przerysowanie gubi kursor.
        if v.string != text { v.string = text; v.invalidateIntrinsicContentSize() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: NSTextView, context: Context) -> CGSize? {
        measure(v, proposal: proposal, minHeight: minHeight)
    }
}
