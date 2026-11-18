@preconcurrency import CoreML
import FluidAudio
import Foundation
import YascribeProviders

public enum DiarizerModelStatus: Equatable, Sendable {
    /// Żadnego pliku z manifestu (także katalog z samym `.lock` po `remove`).
    case missing
    /// Część plików jest, ale brakuje pliku albo rozmiar się nie zgadza (przerwane pobranie).
    case incomplete
    case ready
}

public struct DiarizerModelStoreError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var errorDescription: String? { message }
    public var displayMessage: String? = nil
}

/// Blokada `flock` na `<katalog>/.lock`, współdzielona między aplikacją i CLI; zwalnia się przy zwolnieniu obiektu.
public final class DiarizerModelLock: Sendable {
    private let fd: Int32
    fileprivate init(fd: Int32) { self.fd = fd }
    deinit { close(fd) }
}

/// Magazyn modelu diaryzacji w katalogu Yascribe (spec D6, §8 R02, R04): stan, własny pobieracz z przypiętej rewizji HF,
/// usunięcie i ładowanie `MLModel(contentsOf:)` — bez centrum pobierań FluidAudio (globalna flaga offline, kasowanie cache przy błędzie).
public struct DiarizerModelStore: Sendable {
    /// Wstrzykiwane pobranie jednego pliku: adres → (plik tymczasowy do przeniesienia, odpowiedź).
    public typealias Fetch = @Sendable (URL) async throws -> (URL, URLResponse)

    public let directory: URL
    let manifest: ModelManifest
    private let fetch: Fetch

    public init(directory: URL = DiarizerModelStore.defaultDirectory, manifest: ModelManifest = DiarizerManifest.offline,
                fetch: Fetch? = nil) {
        self.directory = directory
        self.manifest = manifest
        self.fetch = fetch ?? { try await URLSession.shared.download(from: $0) }
    }

    public static var defaultDirectory: URL { directory(root: YascribePaths.fromEnvironment().root) }

    /// Katalog modelu w danym katalogu danych Yascribe (aplikacja podaje własne `paths`, nie czyta środowiska drugi raz).
    public static func directory(root: URL) -> URL {
        root.appendingPathComponent("Models", isDirectory: true).appendingPathComponent(DiarizerManifest.offline.model, isDirectory: true)
    }

    private var lockURL: URL { directory.appendingPathComponent(".lock") }

    public func status() -> DiarizerModelStatus {
        let actual = manifest.files.map { (Self.size(of: directory.appendingPathComponent($0.key)), $0.value) }
        if actual.allSatisfy({ $0.0 == nil }) { return .missing }
        return actual.allSatisfy { $0.0 == $0.1 } ? .ready : .incomplete
    }

    /// Blokada współdzielona na czas ładowania i przebiegu; `download`/`remove` w tym czasie dostają błąd.
    public func lockForUse() throws -> DiarizerModelLock {
        try lock(LOCK_SH, busy: "The speaker model is being downloaded or removed. Try again when it finishes.", displayBusy: String(localized: "The speaker model is being downloaded or removed. Try again when it finishes."))
    }

    private func lock(_ operation: Int32, busy: String, displayBusy: String) throws -> DiarizerModelLock {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw DiarizerModelStoreError(message: "Cannot open \(lockURL.path): \(String(cString: strerror(errno)))", displayMessage: String(localized: "Cannot open \(lockURL.path): \(String(cString: strerror(errno)))")) }
        guard flock(fd, operation | LOCK_NB) == 0 else {
            close(fd)
            throw DiarizerModelStoreError(message: busy, displayMessage: displayBusy)
        }
        return DiarizerModelLock(fd: fd)
    }

    private func lockExclusive() throws -> DiarizerModelLock {
        try lock(LOCK_EX, busy: "The speaker model is in use (download or speaker detection in progress). Try again when it finishes.", displayBusy: String(localized: "The speaker model is in use (download or speaker detection in progress). Try again when it finishes."))
    }

    /// Pobranie wyłącznie po akcji użytkownika. Pliki o właściwym rozmiarze zostają; postęp: (bajty gotowe, bajty razem).
    /// shortcut: postęp po każdym pliku (największy ma 13 MB), delegat `didWriteData` gdy pasek zacznie skakać za mocno.
    public func download(progress: @escaping @Sendable (_ done: Int64, _ total: Int64) -> Void) async throws {
        let lock = try lockExclusive()
        defer { withExtendedLifetime(lock) {} }
        var done: Int64 = 0
        for (file, size) in manifest.files.sorted(by: { $0.key < $1.key }) {
            let target = directory.appendingPathComponent(file)
            if Self.size(of: target) != size { try await fetchFile(file, size: size, to: target) }
            done += size
            progress(done, manifest.totalBytes)
        }
    }

    /// `<plik>.part` → sprawdzenie statusu HTTP i rozmiaru → przeniesienie. Po błędzie znika tylko `.part`.
    private func fetchFile(_ file: String, size: Int64, to target: URL) async throws {
        let fm = FileManager.default
        let part = target.appendingPathExtension("part")
        defer { try? fm.removeItem(at: part) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temporary, response) = try await fetch(DiarizerManifest.url(for: file))
        try? fm.removeItem(at: part)
        try fm.moveItem(at: temporary, to: part)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DiarizerModelStoreError(message: "Downloading \(file) failed (HTTP \(code)).", displayMessage: String(localized: "Downloading \(file) failed (HTTP \(code)).")) }
        let actual = Self.size(of: part) ?? 0
        guard actual == size else {
            throw DiarizerModelStoreError(message: "Downloaded \(file) has \(actual) bytes, expected \(size).", displayMessage: String(localized: "Downloaded \(file) has \(actual) bytes, expected \(size)."))
        }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: part, to: target)
    }

    /// Kasuje pliki modelu i resztki `.part`; katalog i `.lock` zostają, żeby inny proces nie zablokował osieroconego pliku.
    public func remove() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let lock = try lockExclusive()
        defer { withExtendedLifetime(lock) {} }
        let top = Set(manifest.files.keys.compactMap { $0.split(separator: "/").first.map(String.init) })
        for name in try fm.contentsOfDirectory(atPath: directory.path) where top.contains(name) || name.hasSuffix(".part") {
            try fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Ładowanie bez sieci: brak kompletu → błąd. FBank zawsze na CPU (jak w FluidAudio), reszta na `computeUnits`.
    public func loadModels(computeUnits: MLComputeUnits = .all) throws -> OfflineDiarizerModels {
        let notReady = DiarizerModelStoreError(message: "The speaker model is not downloaded. Download it in Settings.", displayMessage: String(localized: "The speaker model is not downloaded. Download it in Settings."))
        guard status() == .ready else { throw notReady }
        let lock = try lockForUse()
        defer { withExtendedLifetime(lock) {} }
        guard status() == .ready else { throw notReady }
        let start = Date()
        func model(_ name: String, _ units: MLComputeUnits) throws -> MLModel {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = units
            return try MLModel(contentsOf: directory.appendingPathComponent(name, isDirectory: true), configuration: configuration)
        }
        return OfflineDiarizerModels(
            segmentationModel: try model("Segmentation.mlmodelc", computeUnits),
            fbankModel: try model("FBank.mlmodelc", .cpuOnly),
            embeddingModel: try model("Embedding.mlmodelc", computeUnits),
            pldaRhoModel: try model("PldaRho.mlmodelc", computeUnits),
            pldaPsi: try Self.pldaPsi(from: directory.appendingPathComponent("plda-parameters.json")),
            compilationDuration: Date().timeIntervalSince(start))
    }

    /// `tensors.psi.data_base64` → float32 little-endian → `[Double]` (format FluidAudio 0.17.7).
    static func pldaPsi(from url: URL) throws -> [Double] {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        guard let tensors = root?["tensors"] as? [String: Any], let psi = tensors["psi"] as? [String: Any],
              let base64 = psi["data_base64"] as? String, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              data.count >= MemoryLayout<Float>.size
        else { throw DiarizerModelStoreError(message: "The speaker model's PLDA parameters are unreadable.", displayMessage: String(localized: "The speaker model's PLDA parameters are unreadable.")) }
        var floats = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.size)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return floats.map(Double.init)
    }

    static func size(of url: URL) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }
}
