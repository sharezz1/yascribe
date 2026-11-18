import AppKit
import YascribeNotes
import SwiftUI

/// Notatka Summary jako JEDEN `NSTextView` tylko do odczytu (D6; odbiór T13 uwaga 4): zaznaczanie przez wszystkie akapity,
/// Cmd-A / Cmd-C. Bez własnego przewijania — wysokość z `sizeThatFits`, przewija `ScrollView` widoku.
/// Typografia (macos.md §11.2) w `MarkdownBlocks.attributed`; kolory to tokeny DesignSystem (`NSColor(Color)` zostaje dynamiczny).
struct MarkdownView: NSViewRepresentable {
    let blocks: [MarkdownBlock]
    /// „Who is this?” dla klikniętego mówcy (N z linku `yascribe-speaker:N`); `close` zamyka popover. `nil` = imiona nieklikalne.
    var speakerPicker: ((Int, @escaping () -> Void) -> AnyView)? = nil

    final class Coordinator: NSObject, NSTextViewDelegate {
        var shown: [MarkdownBlock]?
        var speakerPicker: ((Int, @escaping () -> Void) -> AnyView)?
        var popover: NSPopover?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == SpeakerMarkers.urlScheme,
                  let number = Int(url.absoluteString.dropFirst(SpeakerMarkers.urlScheme.count + 1)), let speakerPicker,
                  let lm = textView.layoutManager, let tc = textView.textContainer else { return false }
            var range = NSRange()
            _ = textView.textStorage?.attribute(.link, at: charIndex, effectiveRange: &range)
            var rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: tc)
            rect = rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            popover?.close()
            let p = NSPopover()
            p.behavior = .transient
            let host = NSHostingController(rootView: speakerPicker(number) { [weak p] in p?.close() })
            host.sizingOptions = .preferredContentSize // inaczej NSPopover bierze domyślną, za wysoką ramkę
            p.contentViewController = host
            p.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
            popover = p
            return true
        }
    }
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
        v.delegate = context.coordinator
        v.linkTextAttributes = [.cursor: NSCursor.pointingHand] // imię mówcy w jego kolorze, bez niebieskiego i podkreślenia
        return v
    }

    func updateNSView(_ v: NSTextView, context: Context) {
        context.coordinator.speakerPicker = speakerPicker
        // Tylko przy zmianie treści — inaczej każde przerysowanie rodzica gubi zaznaczenie.
        guard context.coordinator.shown != blocks else { return }
        // Nowa treść (zmiana imienia, nowa notatka): otwarty picker wskazywałby mówcę spod starego tekstu.
        context.coordinator.popover?.close()
        context.coordinator.shown = blocks
        var style = NoteStyle()
        style.text = NSColor(Color.mnText)
        style.secondary = NSColor(Color.mnText2)
        style.marker = NSColor(Color.mnText3)
        style.speakerColor = { NSColor(UtteranceRow.color(number: $0)) }
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
