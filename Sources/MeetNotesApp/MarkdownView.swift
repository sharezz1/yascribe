import MeetNotesNotes
import SwiftUI

/// Rysuje bloki z `MarkdownBlocks.group` — nagłówki, akapity, punkty (z wcięciem) i numerowane pozycje.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in row(b) }
        }
        .textSelection(.enabled)
        .frame(maxWidth: 720, alignment: .leading) // czytelna długość wiersza (macos.md §5)
    }

    @ViewBuilder private func row(_ b: MarkdownBlock) -> some View {
        switch b.kind {
        case .heading(let level):
            Text(b.text).font(level <= 1 ? .title2.bold() : .title3.bold()).padding(.top, 10)
        case .paragraph:
            Text(b.text)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); Text(b.text) }
                .padding(.leading, CGFloat(b.depth) * 18)
        case .numbered(let n):
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(n)."); Text(b.text) }
                .padding(.leading, CGFloat(b.depth) * 18)
        }
    }
}
