import Foundation
import YascribeProviders

/// Rejestr nie udostępnia modelu w UI. Listę LocalASRModels.models(for:) rozszerzy etap N3/N4.
public enum LocalASRModel: Sendable, CaseIterable {
    case parakeetV3
    case cohereTranscribe6bit

    public var id: String {
        switch self {
        case .parakeetV3: LocalASRModels.parakeetV3
        case .cohereTranscribe6bit: LocalASRModels.cohereTranscribe6bit
        }
    }
    public var pin: String {
        switch self {
        case .parakeetV3: ModelManifest.pin
        case .cohereTranscribe6bit: "hf:\(Self.cohereRepository)@\(Self.cohereRevision)"
        }
    }
    public var subdirectory: String {
        self == .parakeetV3 ? id : "cohere-transcribe-03-2026-coreml-6bit"
    }
    public var manifest: ModelManifest { self == .parakeetV3 ? .parakeetV3 : .cohereTranscribe6bit }
    public enum EngineKind: Sendable { case parakeet, cohere }
    public var engineKind: EngineKind { self == .parakeetV3 ? .parakeet : .cohere }

    public init(id: String) throws {
        guard let model = Self.allCases.first(where: { $0.id == id }) else {
            throw RunGateRefusal(message: "Unknown on-device speech model: \(id). Choose a supported model with Transcribe again…", canDownload: false)
        }
        self = model
    }

    public var maxChunkSeconds: Double { self == .cohereTranscribe6bit ? 12 : 59 }
    public var maxSourceSpan: Double? { self == .cohereTranscribe6bit ? 30 : nil }
    public var repetitionFilterEnabled: Bool { self == .cohereTranscribe6bit }
    /// README języki przypiętej rewizji 6-bit; tokenizer zawiera też nieobsługiwane języki.
    public var supportedLanguages: Set<String>? {
        self == .cohereTranscribe6bit ? ["en", "ar", "de", "el", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt", "vi", "zh"] : nil
    }

    public static let cohereRepository = "BarathwajAnandan/cohere-transcribe-03-2026-CoreML-6bit"
    public static let cohereRevision = "79320e92e2e220ed2ed2a9acb41f3caff06acb85"
}

extension ModelManifest {
    // Rozmiary z .manifest.tsv przypiętej rewizji; bez .compiled/ i bez zapytań o listę plików przy pobieraniu.
    public static let cohereTranscribe6bit = ModelManifest(model: LocalASRModels.cohereTranscribe6bit, files: [
        "LICENSE": 35149,
        "README.md": 3608,
        "benchmarks/compute_unit_comparison.json": 3307,
        "benchmarks/librispeech_wer_200samples.json": 440,
        "benchmarks/librispeech_wer_full_2620samples.json": 204,
        "benchmarks/quantization_variants_speed_accuracy.json": 5337,
        "cohere_decoder_cached.mlpackage/Data/com.apple.CoreML/model.mlmodel": 194369,
        "cohere_decoder_cached.mlpackage/Data/com.apple.CoreML/weights/weight.bin": 114415488,
        "cohere_decoder_cached.mlpackage/Manifest.json": 617,
        "cohere_decoder_fullseq_masked.mlpackage/Data/com.apple.CoreML/model.mlmodel": 169906,
        "cohere_decoder_fullseq_masked.mlpackage/Data/com.apple.CoreML/weights/weight.bin": 113720000,
        "cohere_decoder_fullseq_masked.mlpackage/Manifest.json": 617,
        "cohere_encoder.mlpackage/Data/com.apple.CoreML/model.mlmodel": 1568247,
        "cohere_encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin": 1406127424,
        "cohere_encoder.mlpackage/Manifest.json": 617,
        "cohere_frontend.mlpackage/Data/com.apple.CoreML/model.mlmodel": 421643,
        "cohere_frontend.mlpackage/Data/com.apple.CoreML/weights/weight.bin": 1185024,
        "cohere_frontend.mlpackage/Manifest.json": 617,
        "coreml_manifest.json": 297408,
    ])
}
