import MeetNotesNotes
import SwiftUI

/// Notatka jako jeden zaznaczalny tekst (`MarkdownBlocks.flatten`) — zaznaczenie przechodzi przez akapity, nagłówki i listy.
/// Typografia notatki (macos.md §11.2): SF 14 z interlinią ~22 pt, nagłówki 15 Semibold, punktory w `text3`.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    private var text: AttributedString {
        var s = MarkdownBlocks.flatten(blocks) { h, _ in h.font = .system(size: 15, weight: .semibold) }
        for r in s.characters.ranges(of: "• ") { s[r].foregroundColor = Color.mnText3 }
        return s
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(5) // SF 14 ma ~17 pt interlinii; cel 22 pt
            .foregroundStyle(.mnText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading) // szerokość daje kolumna 640 pt (§11.2)
    }
}
