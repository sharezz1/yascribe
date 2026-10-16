import MeetNotesMeetings
import SwiftUI

/// Co pokazuje pływająca pigułka. Okno nie zależy już od nagrywania: `.offer` i `.endPrompt` żyją bez niego (faza 1.6, spec §4.4).
enum PillMode: Equatable {
    case recording
    case offer(Offer)
    case endPrompt(EndSignal)
}

/// Treść okna pigułki wybrana przez `PillState.mode`.
struct PillContentView: View {
    let model: AppModel
    @ObservedObject var pill: PillState

    var body: some View {
        switch pill.mode {
        case .recording:
            RecordingPanelView(model: model, pill: pill)
        case .offer(let offer):
            PillOfferView(offer: offer, pill: pill).environment(model)
        case .endPrompt:
            PillEndPromptView(pill: pill).environment(model)
        }
    }
}
