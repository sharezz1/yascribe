import FluidAudio
import Foundation
import Synchronization
import Testing
@testable import YascribeLocalASR

private let tiny = ModelManifest(model: "speaker-diarization", files: [
    "A.mlmodelc/model.mil": 3,
    "A.mlmodelc/weights/weight.bin": 10,
    "plda-parameters.json": 4,
])

/// Katalog `mn-<UUID>` (sprząta go `scripts/test.sh`); sam katalog magazynu jeszcze nie istnieje.
private func makeStore(manifest: ModelManifest = tiny, fetch: DiarizerModelStore.Fetch? = nil) -> DiarizerModelStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    return DiarizerModelStore(directory: root.appendingPathComponent("speaker-diarization", isDirectory: true), manifest: manifest,
                              fetch: fetch ?? { url in
                                  Issue.record("network in a unit test: \(url)")
                                  throw DiarizerModelStoreError(message: "network in a unit test")
                              })
}

private func write(_ file: String, size: Int, in dir: URL) throws {
    let url = dir.appendingPathComponent(file)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x61, count: size).write(to: url)
}

private func writeAll(_ store: DiarizerModelStore, skipping skipped: Set<String> = []) throws {
    for (file, size) in store.manifest.files where !skipped.contains(file) { try write(file, size: Int(size), in: store.directory) }
}

private let resolveBase = "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/df2625ac79a7ac6b65ad868fee6d80f320da4232/"

/// Atrapa HF: plik z pełnej ścieżki po `resolve/<rewizja>/`, odpowiedź `(bajty, kod HTTP)`; obcy adres → błąd i zgłoszenie, nie awaria.
private final class FakeHF: Sendable {
    let fetched = Mutex<[String]>([])
    let respond: @Sendable (String) -> (size: Int, code: Int)
    init(_ respond: @escaping @Sendable (String) -> (size: Int, code: Int)) { self.respond = respond }

    func fetch(_ url: URL) throws -> (URL, URLResponse) {
        guard url.absoluteString.hasPrefix(resolveBase) else {
            Issue.record("unexpected URL \(url)")
            throw DiarizerModelStoreError(message: "unexpected URL")
        }
        let file = String(url.absoluteString.dropFirst(resolveBase.count))
        fetched.withLock { $0.append(file) }
        let (size, code) = respond(file)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
        try Data(repeating: 0x62, count: size).write(to: tmp)
        return (tmp, HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}

private func partFiles(in dir: URL) -> [String] {
    let all = FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []
    return all.filter { $0.hasSuffix(".part") }
}

@Test func diarizerManifestMatchesTheHuggingFaceTree() {
    #expect(DiarizerManifest.offline.files.count == 21)
    #expect(DiarizerManifest.offline.totalBytes == 21_599_417)
    #expect(DiarizerModelStore().directory.path.hasSuffix("/Models/speaker-diarization"))
}

@Test func diarizerStatusFollowsPresenceAndSizeOfEveryFile() throws {
    let store = makeStore()
    #expect(store.status() == .missing) // brak katalogu
    _ = try store.lockForUse()
    #expect(store.status() == .missing) // sam `.lock`
    try writeAll(store, skipping: ["plda-parameters.json"])
    #expect(store.status() == .incomplete)
    try write("plda-parameters.json", size: 3, in: store.directory) // za krótki
    #expect(store.status() == .incomplete)
    try write("plda-parameters.json", size: 4, in: store.directory)
    #expect(store.status() == .ready)
}

@Test func diarizerRemoveRefusesWhileTheModelIsInUse() throws {
    let store = makeStore()
    try writeAll(store)
    do {
        let lock = try store.lockForUse()
        #expect(throws: DiarizerModelStoreError.self) { try store.remove() }
        #expect(store.status() == .ready)
        withExtendedLifetime(lock) {}
    }
    try store.remove() // blokada zwolniona
    #expect(store.status() == .missing)
    #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(".lock").path))
}

@Test func diarizerDownloadKeepsReadyFilesAndDropsThePartAfterAFailure() async throws {
    let weight = "A.mlmodelc/weights/weight.bin"
    // Za krótka odpowiedź 200 oraz odpowiedź o właściwym rozmiarze, ale z kodem ≠ 200: oba to błąd.
    for (size, code) in [(9, 200), (10, 404), (10, 500)] {
        let hf = FakeHF { _ in (size, code) }
        let store = makeStore(fetch: { try hf.fetch($0) })
        try write("A.mlmodelc/model.mil", size: 3, in: store.directory)
        await #expect(throws: DiarizerModelStoreError.self, "\(size) B, HTTP \(code)") { try await store.download { _, _ in } }
        #expect(hf.fetched.withLock { $0 } == [weight]) // gotowy model.mil nie był pobierany, po błędzie stop
        #expect(try Data(contentsOf: store.directory.appendingPathComponent("A.mlmodelc/model.mil")) == Data(repeating: 0x61, count: 3))
        #expect(partFiles(in: store.directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(weight).path))
        #expect(store.status() == .incomplete)
    }
}

@Test func diarizerDownloadCompletesAndReportsBytes() async throws {
    let hf = FakeHF { file in (Int(tiny.files[file] ?? 0), 200) }
    let store = makeStore(fetch: { try hf.fetch($0) })
    let last = Mutex<(Int64, Int64)>((0, 0))
    try await store.download { done, total in last.withLock { $0 = (done, total) } }
    #expect(store.status() == .ready)
    #expect(hf.fetched.withLock { $0 } == tiny.files.keys.sorted()) // pełne ścieżki z `/` w `.mlmodelc/...`
    #expect(partFiles(in: store.directory).isEmpty)
    let (done, total) = last.withLock { $0 }
    #expect(done == 17 && total == 17)
}

@Test func diarizerLoadWithoutModelFailsLocally() {
    let store = makeStore()
    #expect(throws: DiarizerModelStoreError.self) { try store.loadModels() }
    #expect(!FileManager.default.fileExists(atPath: store.directory.path))
}

@Test func diarizerLoadOfACompleteButBrokenStoreFailsWithoutNetworkOrFileChanges() throws {
    let names = ["Segmentation", "FBank", "Embedding", "PldaRho"].map { "\($0).mlmodelc/model.mil" } + ["plda-parameters.json"]
    let store = makeStore(manifest: ModelManifest(model: "speaker-diarization", files: Dictionary(uniqueKeysWithValues: names.map { ($0, 5) })))
    try writeAll(store)
    #expect(store.status() == .ready)
    func snapshot() throws -> [String: Data] {
        let paths = FileManager.default.enumerator(atPath: store.directory.path)?.allObjects as? [String] ?? []
        var out: [String: Data] = [:]
        for path in paths where path != ".lock" {
            let url = store.directory.appendingPathComponent(path)
            if (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true { out[path] = try Data(contentsOf: url) }
        }
        return out
    }
    let before = try snapshot()
    // Pas bezpieczeństwa: gdyby ładowanie szło przez centrum pobierań FluidAudio, rzuci `networkDisabled` zamiast pobrać.
    let wasOffline = ModelHub.offlineMode
    ModelHub.offlineMode = true
    defer { ModelHub.offlineMode = wasOffline }
    #expect(throws: (any Error).self) { try store.loadModels() } // atrapy to nie modele CoreML
    #expect(try snapshot() == before)
    #expect(before.count == names.count)
    #expect(store.status() == .ready)
}

@Test func pldaPsiDecodesFloat32Base64() throws {
    let floats: [Float] = [1.5, -2, 0.25]
    let base64 = floats.withUnsafeBytes { Data($0) }.base64EncodedString()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try Data(#"{"tensors":{"psi":{"data_base64":"\#(base64)"}}}"#.utf8).write(to: url)
    #expect(try DiarizerModelStore.pldaPsi(from: url) == [1.5, -2, 0.25])
    try Data(#"{"tensors":{}}"#.utf8).write(to: url)
    #expect(throws: DiarizerModelStoreError.self) { try DiarizerModelStore.pldaPsi(from: url) }
}
