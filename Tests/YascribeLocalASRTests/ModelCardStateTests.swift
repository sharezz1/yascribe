import Foundation
import Testing
@testable import YascribeLocalASR

private let statuses: [ModelStatus] = [.missing, .ready, .invalid(reason: "Encoder.mlmodelc/weights/weight.bin has 5 bytes, expected 445187200"),
                                       .unknownVariant(reason: "found Encoder-v2.mlmodelc instead of Encoder.mlmodelc")]

/// Każda para status × aktywność daje tytuł, opis i (albo brak) akcji głównej; rozmiar z manifestu, nie na sztywno.
@Test func cardStateMapsEveryStatus() {
    for status in statuses {
        for activity in [ModelActivity.idle, .downloading(nil), .downloading(0.41), .preparing] {
            let c = ModelCardState(status: status, activity: activity)
            #expect(!c.title.isEmpty && !c.description.isEmpty, "\(status) \(activity)")
            #expect(c.meta == "Multilingual · 483 MB")
            if activity != .idle { #expect(c.primary == nil && c.roleWarning == nil, "no action while busy: \(status) \(activity)") }
        }
    }
    let missing = ModelCardState(status: .missing, activity: .idle)
    #expect(missing.primary == .download && missing.primaryLabel == "Download (483 MB)" && missing.roleWarning == "Model not downloaded")
    #expect(missing.primary?.needsConfirmation == false)
    #expect(missing.note?.contains("parakeet-tdt-0.6b-v3-coreml") == true)
    let ready = ModelCardState(status: .ready, activity: .idle)
    #expect(ready.title == "Ready" && ready.primary == .remove && ready.primaryLabel == "Remove…" && ready.roleWarning == nil)
    #expect(ready.primary?.needsConfirmation == true)
    let invalid = ModelCardState(status: statuses[2], activity: .idle)
    #expect(invalid.primary == .downloadAgain && invalid.primaryLabel == "Download again" && invalid.primary?.needsConfirmation == true)
    #expect(invalid.description.contains("Encoder.mlmodelc/weights/weight.bin"))
    let variant = ModelCardState(status: statuses[3], activity: .idle)
    #expect(variant.primary == nil && variant.tone == .warning && variant.roleWarning != nil)
    #expect(ModelCardState(status: .missing, activity: .downloading(0.416)).title == "Downloading 42%")
    #expect(ModelCardState(status: .missing, activity: .downloading(nil)).tone == .progress(nil))
    let preparing = ModelCardState(status: .ready, activity: .preparing)
    #expect(preparing.description == "Preparing model… the first run on this Mac can take up to a minute.")
}

@Test func cardSizeComesFromTheManifest() {
    let ultra = ModelCardState(status: .missing, activity: .idle, variant: .parakeetUltra)
    #expect(ultra.primaryLabel == "Download (\(ModelCardState.sizeText(ModelManifest.parakeetUltra.totalBytes)))")
    #expect(ModelCardState.sizeText(1_260_000_000) == "1.3 GB")
    #expect(ModelCardState.sizeText(ModelManifest.parakeetV3.totalBytes) == "483 MB")
}

/// Karta Ultra: własna nazwa i folder; uwaga o starym układzie FluidAudio dotyczy tylko v3.
@Test func ultraCardHasItsOwnNameAndFolderAndNoLegacyNote() {
    let v3 = ModelCardState(status: .missing, activity: .idle)
    let ultra = ModelCardState(status: .missing, activity: .idle, variant: .parakeetUltra)
    #expect(v3.name == "Parakeet TDT v3" && v3.folder == "parakeet-tdt-0.6b-v3")
    #expect(ultra.name == "Parakeet Ultra" && ultra.folder == "parakeet-ultra")
    #expect(ultra.note == nil && ultra.primary == .download)
}
