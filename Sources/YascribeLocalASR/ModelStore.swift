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

/// Magazyn lokalnego modelu ASR: stan względem manifestu, odcisk, pobranie i usunięcie. FluidAudio tylko tutaj (domyślny
/// `download`) — `FluidAudioEngine` (T4) ładuje wyłącznie `AsrModels.loadLocal(from: modelDirectory)`.
public struct ModelStore: Sendable {
    /// Wstrzykiwane pobranie: (katalog MODELU, force, postęp). `nil` w postępie = nieokreślony.
    public typealias Download = @Sendable (URL, Bool, @escaping @Sendable (Double?) -> Void) async throws -> Void

    /// Korzeń magazynu: historyczny dla Parakeeta, własny Yascribe dla Cohere; model leży w `modelDirectory`.
    public let directory: URL
    /// Wstrzykiwane `AsrModels.modelsExist` (lokalne sprawdzenie obecności plików, bez sieci) dla katalogu modelu.
    public typealias ModelsExist = @Sendable (URL) -> Bool

    private let downloader: Download
    private let modelsExist: ModelsExist
    public let model: LocalASRModel
    private var manifest: ModelManifest { model.manifest }
    public typealias FileDownload = @Sendable (URL, URL) async throws -> Void
    public typealias DiskSpace = @Sendable (URL) throws -> ModelDiskLocation
    private let diskSpace: DiskSpace

    public init(model: LocalASRModel = .parakeetV3, directory: URL? = nil, download: Download? = nil,
                modelsExist: @escaping ModelsExist = ModelStore.fluidAudioModelsExist,
                fileDownload: @escaping FileDownload = ModelStore.networkFileDownload,
                diskSpace: @escaping DiskSpace = ModelDiskBudget.inspect) {
        self.model = model
        self.directory = directory ?? Self.resolveDirectory(model: model, env: ProcessInfo.processInfo.environment)
        self.downloader = download ?? (model == .parakeetV3 ? Self.fluidAudioDownload : Self.cohereDownload(fileDownload: fileDownload))
        self.modelsExist = modelsExist
        self.diskSpace = diskSpace
    }

    public static var defaultDirectory: URL { resolveDirectory(env: ProcessInfo.processInfo.environment) }

    /// Korzeń magazynu; `YASCRIBE_MODEL_STORE` działa tylko w buildzie DEBUG (odbiór na kopii, bez dotykania wspólnego magazynu).
    public static func resolveDirectory(model: LocalASRModel = .parakeetV3, env: [String: String]) -> URL {
        #if DEBUG
        if let override = env["YASCRIBE_MODEL_STORE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(model == .parakeetV3 ? "FluidAudio" : "Yascribe", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Katalog wybranego modelu; dla Parakeeta zgodny z `AsrModels.download(to:)` i `loadLocal(from:)`.
    public var modelDirectory: URL { directory.appendingPathComponent(model.subdirectory, isDirectory: true) }

    public func status() -> ModelStatus {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: modelDirectory.path) else { return .missing }
        let manifestComponents = Set(manifest.files.keys.compactMap { $0.split(separator: "/").first.map(String.init) }
            .filter { $0.hasSuffix(model == .parakeetV3 ? ".mlmodelc" : ".mlpackage") })
        let present = Set(names.filter { $0.hasSuffix(model == .parakeetV3 ? ".mlmodelc" : ".mlpackage") })
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

    /// SHA-256 z pinu, listy (nazwa, rozmiar) i treści plików poza wagami. Grafy, metadane i słowniki
    /// zmieniają odcisk także przy zachowanym rozmiarze. Wagi nie są hashowane; `nil`, gdy status ≠ `ready`.
    /// Algorytm Parakeeta pozostaje zgodny z historycznymi przebiegami; pliki nadmiarowe nie wchodzą.
    public func fingerprint() -> String? { fingerprint(pin: model.pin) }

    func fingerprint(pin: String) -> String? {
        guard status() == .ready else { return nil }
        var hasher = SHA256()
        hasher.update(data: Data("\(pin)\n".utf8))
        for (file, size) in manifest.files.sorted(by: { $0.key < $1.key }) {
            hasher.update(data: Data("\(file)\t\(size)\n".utf8))
            if file.hasSuffix("/weights/weight.bin") { continue }
            guard let content = try? Data(contentsOf: modelDirectory.appendingPathComponent(file)) else { return nil }
            hasher.update(data: content)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Pobranie wyłącznie po akcji użytkownika. FluidAudio wznawia pliki `.partial`, a `force` kasuje folder modelu — więc `force`
    /// tylko wtedy, gdy bez niego nic by się nie naprawiło: (a) jakiś plik z manifestu ma ZŁY rozmiar albo (b) `modelsExist`
    /// FluidAudio (sama obecność plików) mówi „jest", a nasz status jest `invalid` (np. brak `config.json`). Brakujące pliki
    /// pobierane są bez `force`, czyli z wznowieniem przerwanego pobrania.
    public func download(progress: @escaping @Sendable (Double?) -> Void) async throws {
        let owner = try acquireLock()
        defer { withExtendedLifetime(owner) {} }
        let before = status()
        if before == .ready { return }
        var force = false
        if case .invalid = before { force = hasWrongSizeFile() || (model == .parakeetV3 && modelsExist(modelDirectory)) }
        let budget = try diskNeed(operation: .download)
        if let insufficient = budget.first(where: { !$0.fits }) {
            throw ModelStoreError(message: "Not enough disk space: need \(insufficient.bytes) bytes, available \(insufficient.freeBytes) bytes on volume \(insufficient.volume).")
        }
        try await downloader(modelDirectory, force, progress)
        switch status() {
        case .ready: return
        case .missing: throw ModelStoreError(message: "The model download finished but no model files were found.")
        case .invalid(let reason), .unknownVariant(let reason):
            throw ModelStoreError(message: "The downloaded model differs from the version this build expects (\(reason)).")
        }
    }

    /// Czy istnieje plik z manifestu o rozmiarze innym niż w manifeście (brak pliku to nie zły rozmiar).
    private func hasWrongSizeFile() -> Bool {
        manifest.files.contains { file, size in
            let attrs = try? FileManager.default.attributesOfItem(atPath: modelDirectory.appendingPathComponent(file).path)
            guard let actual = (attrs?[.size] as? NSNumber)?.int64Value else { return false }
            return actual != size
        }
    }

    /// Kasuje wyłącznie folder modelu — nie jego sąsiadów we wspólnym magazynie.
    public func remove() throws {
        let owner = try acquireLock()
        defer { withExtendedLifetime(owner) {} }
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else { return }
        try FileManager.default.removeItem(at: modelDirectory)
    }

    /// Token dla przyszłego silnika: utrzymać od sprawdzenia odcisku aż do zwolnienia obiektów Core ML.
    public func acquireLock() throws -> ModelStoreLock {
        try ModelStoreLock(url: lockURL)
    }

    var lockURL: URL { directory.appendingPathComponent(".locks", isDirectory: true).appendingPathComponent("\(model.id).lock") }
    public var compiledDirectory: URL { modelDirectory.appendingPathComponent("compiled", isDirectory: true) }

    public func compiledModelsReady(configuration: CohereTranscribeComputeConfiguration = .yascribe) -> Bool {
        guard model == .cohereTranscribe6bit, let fingerprint = fingerprint() else { return false }
        let key = CohereModelCompilation.key(fingerprint: fingerprint, configuration: configuration)
        return CohereModelCompilation.packages.allSatisfy {
            CohereModelCompilation.isComplete(at: CohereModelCompilation.directory(package: $0, root: compiledDirectory, key: key))
        }
    }

    /// N2 używa tego samego budżetu przed każdym ładowaniem, pod utrzymywanym tokenem blokady.
    public func diskNeed(operation: ModelDiskBudget.Operation,
                         configuration: CohereTranscribeComputeConfiguration = .yascribe) throws -> [ModelDiskNeed] {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
            .appendingPathComponent("com.apple.e5rt.e5bundlecache")
        return try ModelDiskBudget.need(modelBytes: manifest.totalBytes, operation: operation,
            compiledReady: operation == .load && compiledModelsReady(configuration: configuration),
            store: diskSpace(modelDirectory), temporary: diskSpace(FileManager.default.temporaryDirectory), e5rt: diskSpace(caches))
    }

    /// Jedyna ścieżka sieciowa własnego pobieracza. Odbiorca widzi wyłącznie plik .part, nigdy niekompletny plik docelowy.
    public static let networkFileDownload: FileDownload = { source, part in
        let (temporary, response) = try await URLSession.shared.download(from: source)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelStoreError(message: "The model server returned an unsuccessful response.")
        }
        try FileManager.default.moveItem(at: temporary, to: part)
    }

    static func cohereDownload(fileDownload: @escaping FileDownload) -> Download {
        { directory, force, progress in
            let fm = FileManager.default
            if force, fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
            let manifest = ModelManifest.cohereTranscribe6bit
            var completed: Int64 = 0
            for (name, size) in manifest.files.sorted(by: { $0.key < $1.key }) {
                try Task.checkCancellation()
                let destination = directory.appendingPathComponent(name)
                let attributes = try? fm.attributesOfItem(atPath: destination.path)
                if (attributes?[.size] as? NSNumber)?.int64Value != size {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let part = destination.appendingPathExtension("part")
                    try? fm.removeItem(at: part)
                    do {
                        let source = URL(string: "https://huggingface.co/\(LocalASRModel.cohereRepository)/resolve/\(LocalASRModel.cohereRevision)/\(name)")!
                        try await fileDownload(source, part)
                        try Task.checkCancellation()
                        let downloaded = try fm.attributesOfItem(atPath: part.path)
                        guard (downloaded[.size] as? NSNumber)?.int64Value == size else {
                            throw ModelStoreError(message: "Downloaded \(name) has an unexpected size; expected \(size) bytes.")
                        }
                        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                        try fm.moveItem(at: part, to: destination)
                    } catch {
                        try? fm.removeItem(at: part)
                        throw error
                    }
                }
                completed += size
                progress(Double(completed) / Double(manifest.totalBytes))
            }
        }
    }

    /// Lokalne sprawdzenie FluidAudio (obecność plików wariantu v3/int8); bez sieci.
    public static let fluidAudioModelsExist: ModelsExist = { AsrModels.modelsExist(at: $0, version: .v3, encoderPrecision: .int8) }

    /// `AsrModels.download(to:)` z pinem (v3, int8). Ładowanie modelu tylko przez `FluidAudioEngine` (`loadLocal`, bez sieci).
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
