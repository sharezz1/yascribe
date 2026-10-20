import Foundation

/// Wzorzec plików modelu Parakeet v3 (`AsrModelVersion.v3`, `ParakeetEncoderPrecision.int8`) z ŚWIEŻEGO pobrania
/// przypiętym FluidAudio 0.17.7 (F20 S0 §5): nazwa pliku względem katalogu modelu -> rozmiar w bajtach.
/// Integralność = rozmiary (sufit: podmiana o tym samym rozmiarze nie jest wykrywana; wersja HF to niepinowane `main`).
public struct ModelManifest: Codable, Equatable, Sendable {
    public var model: String
    public var files: [String: Int64]
    public var totalBytes: Int64 { files.values.reduce(0, +) }

    public init(model: String, files: [String: Int64]) {
        self.model = model
        self.files = files
    }

    /// Wersja biblioteki, wariant i precyzja, z których pochodzi wzorzec; wchodzi do odcisku modelu.
    public static let pin = "fluidaudio-0.17.7/v3/int8"

    public static let parakeetV3 = ModelManifest(model: "parakeet-tdt-0.6b-v3", files: [
        "Decoder.mlmodelc/analytics/coremldata.bin": 243,
        "Decoder.mlmodelc/coremldata.bin": 554,
        "Decoder.mlmodelc/metadata.json": 3427,
        "Decoder.mlmodelc/model.mil": 13110,
        "Decoder.mlmodelc/weights/weight.bin": 23604992,
        "Encoder.mlmodelc/analytics/coremldata.bin": 243,
        "Encoder.mlmodelc/coremldata.bin": 485,
        "Encoder.mlmodelc/metadata.json": 2921,
        "Encoder.mlmodelc/model.mil": 959769,
        "Encoder.mlmodelc/weights/weight.bin": 445187200,
        "JointDecisionv3.mlmodelc/analytics/coremldata.bin": 243,
        "JointDecisionv3.mlmodelc/coremldata.bin": 521,
        "JointDecisionv3.mlmodelc/metadata.json": 3453,
        "JointDecisionv3.mlmodelc/model.mil": 11775,
        "JointDecisionv3.mlmodelc/weights/weight.bin": 12642764,
        "Preprocessor.mlmodelc/analytics/coremldata.bin": 243,
        "Preprocessor.mlmodelc/coremldata.bin": 486,
        "Preprocessor.mlmodelc/metadata.json": 2841,
        "Preprocessor.mlmodelc/model.mil": 28181,
        "Preprocessor.mlmodelc/weights/weight.bin": 491072,
        "config.json": 475,
        "parakeet_v3_vocab.json": 151122,
        "parakeet_vocab.json": 151122,
    ])
}
