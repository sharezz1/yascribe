import Foundation
import Testing
import YascribeProviders
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
    let small = ModelManifest(model: "x", files: ["a": 1_500_000, "b": 500_000])
    #expect(ModelCardState(status: .missing, activity: .idle, manifest: small).primaryLabel == "Download (2 MB)")
    #expect(ModelCardState.sizeText(1_260_000_000) == "1.3 GB")
    #expect(ModelCardState.sizeText(ModelManifest.parakeetV3.totalBytes) == "483 MB")
}

/// R12 + N4: karta Cohere ma własną nazwę „Experimental”, rozmiar z manifestu, licencję, notę i potwierdzenia; Parakeet bez zmian.
@Test func cohereCardHasItsOwnNameSizeLicenseAndConfirmations() {
    let size = ModelCardState.sizeText(ModelManifest.cohereTranscribe6bit.totalBytes)
    for status in statuses {
        let c = ModelCardState(status: status, activity: .idle, model: .cohereTranscribe6bit)
        #expect(c.name == "Cohere Transcribe 6-bit (Experimental)" && c.size == size && c.meta == "14 languages · \(size)")
        #expect(c.license == "License: model GPL-3.0, on-device port Apache-2.0.")
        #expect(c.note == "Needs a fixed language. Uses about 5 GB RAM. May produce text on silence — such parts are flagged.")
        #expect(c.folderLabel == "Yascribe folder")
        #expect(c.removeMessage.contains(c.name) && c.removeMessage.contains(size) && !c.removeMessage.contains("FluidAudio"))
        #expect(c.repairMessage.contains(c.name) && c.repairMessage.contains(size) && !c.repairMessage.contains("FluidAudio"))
    }
    #expect(ModelCardState(status: .missing, activity: .idle, model: .cohereTranscribe6bit).primaryLabel == "Download (\(size))")
    let p = ModelCardState(status: .ready, activity: .idle)
    #expect(p.name == "Parakeet TDT v3" && p.license == nil && p.note == nil && p.folderLabel == "Shared FluidAudio folder")
    #expect(p.removeMessage.contains("Parakeet TDT v3 (483 MB)") && p.repairMessage.contains("483 MB"))
}

/// N4: wiersz roli w presecie bierze status wybranego modelu; Auto przy Cohere ostrzega, nieustawiony język nie.
@Test func roleCardUsesTheSelectedModel() {
    let status: (LocalASRModel) -> ModelStatus = { $0 == .parakeetV3 ? .ready : .missing }
    let idle: (LocalASRModel) -> ModelActivity = { _ in .idle }
    let cohere = ModelCardState.role(modelID: LocalASRModels.cohereTranscribe6bit, language: .polish, autoLanguage: false, status: status, activity: idle)
    #expect(cohere.roleWarning == "Model not downloaded" && cohere.name.hasSuffix("(Experimental)") && cohere.languageWarning == nil)
    #expect(ModelCardState.role(modelID: LocalASRModels.parakeetV3, language: .polish, autoLanguage: false, status: status, activity: idle).roleWarning == nil)
    #expect(ModelCardState.role(modelID: "typed-unknown", language: .polish, autoLanguage: false, status: status, activity: idle).name == "Parakeet TDT v3")
    let auto = ModelCardState.role(modelID: LocalASRModels.cohereTranscribe6bit, language: nil, autoLanguage: true, status: status, activity: idle)
    #expect(auto.languageWarning == "Cohere requires an explicit language. Auto is not supported.")
    #expect(ModelCardState.role(modelID: LocalASRModels.cohereTranscribe6bit, language: nil, autoLanguage: false, status: status, activity: idle).languageWarning == nil)
    #expect(ModelCardState.role(modelID: LocalASRModels.parakeetV3, language: nil, autoLanguage: true, status: status, activity: idle).languageWarning == nil)
}
