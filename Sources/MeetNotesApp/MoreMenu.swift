import SwiftUI

/// `⋯` 28 × 28 (kółko jak `CircleIconButtonStyle`) z rzadkimi akcjami zakładki: Transcript i Summary.
/// Pozycje otwierające popover ustawiają flagę w `DispatchQueue.main.async` — po zamknięciu pętli NSMenu;
/// sam popover kotwiczy się w `.background` tego przycisku (`MeetingModelChip`/`TranscribeAgainButton` z `presented:`).
/// Pusta treść to sprawa wołającego: wtedy nie rysuje `MoreMenu` wcale.
struct MoreMenu<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Ten sam przepis co `FieldMenu`: styl przycisku nie działa na `Menu`, więc kółko rysuje etykieta.
        Menu { content } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.mnText)
                .frame(width: 28, height: 28)
                .background(.mnCard, in: Circle())
                .overlay(Circle().strokeBorder(.mnLine, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}
