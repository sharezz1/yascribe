import CryptoKit
import FluidAudio
import Foundation

/// Stan modelu w magazynie (spec 2.0a §4.2). „Pobieranie w toku" nie należy tu — trzyma je `LocalASRSupport` (T6).
public enum ModelStatus: Equatable, Sendable {
    case missing
    case ready
    /// Komponenty są, ale brakuje pliku albo rozmiar się nie zgadza (powód zawiera nazwę pliku).
    case invalid(reason: String)
    /// Zestaw komponentów inny niż w manifeście (inny wariant/precyzja z innej aplikacji) — nie „invalid", bez pętli „Download again".
    case unknownVariant(reason: String)
}

public struct ModelStoreError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var errorDescription: String? { message }
}

/// Magazyn modelu Parakeet v3: stan względem manifestu, odcisk, pobranie i usunięcie. FluidAudio tylko tutaj (domyślny
/// `download`) — `FluidAudioEngine` (T4) ładuje wyłącznie `AsrModels.loadLocal(from: modelDirectory)`.
public struct ModelStore: Sendable {
    /// Wstrzykiwane pobranie: (katalog MODELU, force, postęp). `nil` w postępie = nieokreślony.
    public typealias Download = @Sendable (URL, Bool, @escaping @Sendable (Double?) -> Void) async throws -> Void

    /// KORZEŃ magazynu (domyślnie wspólny z FluidAudio); model leży w `modelDirectory`.
    public let directory: URL
    private let downloader: Download
    private let manifest = ModelManifest.parakeetV3

    public init(directory: URL = ModelStore.defaultDirectory, download: @escaping Download = ModelStore.fluidAudioDownload) {
        self.directory = directory
        self.downloader = download
    }

    public static var defaultDirectory: URL { resolveDirectory(env: ProcessInfo.processInfo.environment) }

    /// Korzeń magazynu; `MEETNOTES_MODEL_STORE` działa tylko w buildzie DEBUG (odbiór na kopii, bez dotykania wspólnego magazynu).
    public static func resolveDirectory(env: [String: String]) -> URL {
        #if DEBUG
        if let override = env["MEETNOTES_MODEL_STORE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Ten sam adres idzie do `AsrModels.download(to:)` i `AsrModels.loadLocal(from:)`.
    public var modelDirectory: URL { directory.appendingPathComponent(manifest.model, isDirectory: true) }

    public func status() -> ModelStatus {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: modelDirectory.path) else { return .missing }
        let manifestComponents = Set(manifest.files.keys.compactMap { $0.split(separator: "/").first.map(String.init) }
            .filter { $0.hasSuffix(".mlmodelc") })
        let present = Set(names.filter { $0.hasSuffix(".mlmodelc") })
        let absent = manifestComponents.subtracting(present).sorted()
        let extra = present.subtracting(manifestComponents).sorted()
        if present.isEmpty { return .missing }
        if !absent.isEmpty, !extra.isEmpty {
            return .unknownVariant(reason: "found \(extra.joined(separator: ", ")) instead of \(absent.joined(separator: ", "))")
        }
        for (file, size) in manifest.files.sorted(by: { $0.key < $1.key }) {
            let path = modelDirectory.appendingPathComponent(file).path
            guard let attrs = try? fm.attributesOfItem(atPath: path), let actual = (attrs[.size] as? NSNumber)?.int64Value else {
                return .invalid(reason: "\(file) is missing")
            }
            if actual != size { return .invalid(reason: "\(file) has \(actual) bytes, expected \(size)") }
        }
        return .ready
    }

    /// SHA-256 z listy (nazwa, rozmiar) manifestu i treści `config.json`; `nil`, gdy status ≠ `ready`. Pliki nadmiarowe nie wchodzą.
    public func fingerprint() -> String? {
        guard status() == .ready,
              let config = try? Data(contentsOf: modelDirectory.appendingPathComponent("config.json")) else { return nil }
        var hasher = SHA256()
        for (file, size) in manifest.files.sorted(by: { $0.key < $1.key }) { hasher.update(data: Data("\(file)\t\(size)\n".utf8)) }
        hasher.update(data: config)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Pobranie wyłącznie po akcji użytkownika. `force` liczy sam magazyn: `modelsExist` FluidAudio sprawdza tylko obecność
    /// plików, więc przy złym rozmiarze bez `force` pobranie wróciłoby od razu i nic by nie naprawiło. `force` kasuje folder modelu.
    public func download(progress: @escaping @Sendable (Double?) -> Void) async throws {
        let before = status()
        if before == .ready { return }
        var force = false
        if case .invalid = before { force = true }
        try await downloader(modelDirectory, force, progress)
        switch status() {
        case .ready: return
        case .missing: throw ModelStoreError(message: "The model download finished but no model files were found.")
        case .invalid(let reason), .unknownVariant(let reason):
            throw ModelStoreError(message: "The downloaded model differs from the version this build expects (\(reason)).")
        }
    }

    /// Kasuje wyłącznie folder modelu — nie jego sąsiadów we wspólnym magazynie.
    public func remove() throws {
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else { return }
        try FileManager.default.removeItem(at: modelDirectory)
    }

    /// `AsrModels.download(to:)` z pinem (v3, int8). Nie wołać `AsrModels.load(from:)`/`downloadAndLoad`/`isModelValid`.
    public static let fluidAudioDownload: Download = { modelDirectory, force, progress in
        let mapper = LockedMapper()
        _ = try await AsrModels.download(
            to: modelDirectory, force: force, version: .v3, encoderPrecision: .int8,
            progressHandler: { event in
                let phase: DownloadProgressMapper.Phase
                switch event.phase {
                case .listing: phase = .listing
                case .downloading: phase = .downloading(fraction: event.fractionCompleted)
                case .compiling: phase = .compiling
                }
                progress(mapper.map(phase))
            })
    }
}

private final class LockedMapper: @unchecked Sendable {
    private let lock = NSLock()
    private var mapper = DownloadProgressMapper()
    func map(_ phase: DownloadProgressMapper.Phase) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return mapper.map(phase)
    }
}
