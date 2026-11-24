import Foundation

/// Model diaryzacji offline (community-1 + VBx) z HF `FluidInference/speaker-diarization-coreml` przy rewizji z `ModelNames.swift`
/// FluidAudio 0.17.7 (ta sama rewizja w 0.18.4). Lista i rozmiary z API HF `tree` przy tej rewizji (2026-11-17); razem 21 599 417 B. Integralność = rozmiary.
public enum DiarizerManifest {
    public static let repo = "FluidInference/speaker-diarization-coreml"
    public static let revision = "df2625ac79a7ac6b65ad868fee6d80f320da4232"
    /// Wchodzi do `speakers.json`; inna wartość unieważnia zapisane etykiety (świadomie przy 0.17.7 → 0.18.4, TASK-118 D1).
    public static let pin = "fluidaudio-0.18.4/speaker-diarization-coreml@df2625ac79a7ac6b65ad868fee6d80f320da4232/offline"

    public static let offline = ModelManifest(model: "speaker-diarization", files: [
        "Embedding.mlmodelc/analytics/coremldata.bin": 243,
        "Embedding.mlmodelc/coremldata.bin": 704,
        "Embedding.mlmodelc/metadata.json": 2818,
        "Embedding.mlmodelc/model.mil": 78432,
        "Embedding.mlmodelc/weights/weight.bin": 13412288,
        "FBank.mlmodelc/analytics/coremldata.bin": 243,
        "FBank.mlmodelc/coremldata.bin": 853,
        "FBank.mlmodelc/metadata.json": 3409,
        "FBank.mlmodelc/model.mil": 15667,
        "FBank.mlmodelc/weights/weight.bin": 1776896,
        "PldaRho.mlmodelc/analytics/coremldata.bin": 243,
        "PldaRho.mlmodelc/coremldata.bin": 763,
        "PldaRho.mlmodelc/metadata.json": 2749,
        "PldaRho.mlmodelc/model.mil": 7613,
        "PldaRho.mlmodelc/weights/weight.bin": 200192,
        "Segmentation.mlmodelc/analytics/coremldata.bin": 243,
        "Segmentation.mlmodelc/coremldata.bin": 812,
        "Segmentation.mlmodelc/metadata.json": 3410,
        "Segmentation.mlmodelc/model.mil": 43063,
        "Segmentation.mlmodelc/weights/weight.bin": 5959360,
        "plda-parameters.json": 89416,
    ])

    public static func url(for file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")!
    }
}
