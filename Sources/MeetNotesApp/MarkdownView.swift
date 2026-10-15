import MeetNotesNotes
import SwiftUI

/// Notatka jako jeden zaznaczalny tekst (`MarkdownBlocks.flatten`) — zaznaczenie przechodzi przez akapity, nagłówki i listy.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    private var text: AttributedString {
        MarkdownBlocks.flatten(blocks) { s, level in s.font = level <= 1 ? .title2.bold() : .title3.bold() }
    }

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .frame(maxWidth: 720, alignment: .leading) // czytelna długość wiersza (macos.md §5)
    }
}
