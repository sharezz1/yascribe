import Foundation

/// CAM++ v2 (beta, TASK-117 D2) z HF `FluidInference/campplus-coreml` przy przypiętej rewizji; tylko pliki `_v2`
/// (FluidAudio 0.18.4 `ModelNames.CampPlus`). Lista i rozmiary z API HF `tree` przy tej rewizji (2026-11-24); razem 29 418 955 B.
public enum CampPlusManifest {
    public static let repo = "FluidInference/campplus-coreml"
    public static let revision = "f316edbc70d9023a94aaf8965538aba4330dc28e"

    public static let offline = ModelManifest(model: "campplus", files: [
        "CamPlusPlus_v2.mlmodelc/analytics/coremldata.bin": 243,
        "CamPlusPlus_v2.mlmodelc/coremldata.bin": 411,
        "CamPlusPlus_v2.mlmodelc/metadata.json": 2325,
        "CamPlusPlus_v2.mlmodelc/model.mil": 833242,
        "CamPlusPlus_v2.mlmodelc/weights/weight.bin": 27670272,
        "CamPlusPreprocessor_v2.mlmodelc/analytics/coremldata.bin": 243,
        "CamPlusPreprocessor_v2.mlmodelc/coremldata.bin": 384,
        "CamPlusPreprocessor_v2.mlmodelc/metadata.json": 1902,
        "CamPlusPreprocessor_v2.mlmodelc/model.mil": 5101,
        "CamPlusPreprocessor_v2.mlmodelc/weights/weight.bin": 904832,
    ])

    public static func url(for file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")!
    }

    /// Magazyn obok modelu mówców: `<dane>/Models/campplus`, ten sam pobieracz, blokada i usuwanie.
    public static func store(root: URL) -> DiarizerModelStore {
        DiarizerModelStore(directory: root.appendingPathComponent("Models", isDirectory: true).appendingPathComponent(offline.model, isDirectory: true),
                           manifest: offline, remote: url(for:))
    }
}

/// Model odcisku głosu; identyfikator trafia do każdej próbki profilu — porównujemy tylko ten sam model (TASK-117).
public enum VoiceModel: String, Sendable, CaseIterable {
    case diarizer, campPlus

    /// Nazwa w CLI `voices --model`.
    public init?(cliName: String) {
        switch cliName {
        case "diarizer": self = .diarizer
        case "campplus": self = .campPlus
        default: return nil
        }
    }

    public var id: String {
        switch self {
        case .diarizer: "diarizer/" + DiarizerManifest.pin
        case .campPlus: "campplus-v2@\(CampPlusManifest.revision)/fluidaudio-0.18.4"
        }
    }
}
