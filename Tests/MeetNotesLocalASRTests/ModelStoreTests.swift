import FluidAudio
import Foundation
import Testing
@testable import MeetNotesLocalASR

/// Katalog `mn-<UUID>`; pliki modelu są rzadkie (sparse) — rozmiary jak w manifeście bez 483 MB na dysku.
private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func write(_ file: String, size: Int64, in model: URL, content: Data? = nil) throws {
    let url = model.appendingPathComponent(file)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let content { try content.write(to: url); return }
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(size))
    try handle.close()
}

/// Pełny model z manifestu; `config.json` ma prawdziwą treść (odcisk), reszta to rzadkie pliki o dokładnym rozmiarze.
private func writeAll(into model: URL, skipping skipped: Set<String> = []) throws {
    for (file, size) in ModelManifest.parakeetV3.files where !skipped.contains(file) {
        try write(file, size: size, in: model, content: file == "config.json" ? Data(repeating: 0x61, count: Int(size)) : nil)
    }
}

private func store(_ root: URL, download: @escaping ModelStore.Download = { _, _, _ in },
                   modelsExist: @escaping ModelStore.ModelsExist = { _ in false }) -> ModelStore {
    ModelStore(directory: root, download: download, modelsExist: modelsExist)
}

private func installedStore(skipping skipped: Set<String> = []) throws -> ModelStore {
    let s = store(try makeRoot())
    try writeAll(into: s.modelDirectory, skipping: skipped)
    return s
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []
    var forces: [Bool] { lock.lock(); defer { lock.unlock() }; return recorded }
    func add(_ force: Bool) { lock.lock(); recorded.append(force); lock.unlock() }
}

@Suite struct ModelStoreTests {
    @Test func manifestMatchesTheS0Report() {
        #expect(ModelManifest.parakeetV3.files.count == 23)
        #expect(ModelManifest.parakeetV3.totalBytes == 483_257_242)
    }

    @Test func emptyDirectoryIsMissing() throws {
        let s = store(try makeRoot())
        #expect(s.status() == .missing)
        try FileManager.default.createDirectory(at: s.modelDirectory, withIntermediateDirectories: true)
        #expect(s.status() == .missing)
    }

    @Test func completeModelIsReady() throws {
        #expect(try installedStore().status() == .ready)
    }

    @Test func tamperedModelFileIsRefusedWithReason() throws {
        let s = try installedStore()
        let target = "Encoder.mlmodelc/weights/weight.bin"
        try write(target, size: 1234, in: s.modelDirectory)
        guard case .invalid(let reason) = s.status() else { Issue.record("expected invalid, got \(s.status())"); return }
        #expect(reason.contains(target))
        #expect(s.fingerprint() == nil)
    }

    @Test func missingFileIsInvalid() throws {
        let s = try installedStore(skipping: ["config.json"])
        guard case .invalid(let reason) = s.status() else { Issue.record("expected invalid, got \(s.status())"); return }
        #expect(reason.contains("config.json"))
    }

    @Test func differentVariantFileNamesAreUnknownVariantNotInvalid() throws {
        // Inna aplikacja zapisała enkoder `_v2` zamiast `Encoder.mlmodelc`.
        let s = try installedStore(skipping: Set(ModelManifest.parakeetV3.files.keys.filter { $0.hasPrefix("Encoder.mlmodelc/") }))
        try write("Encoder_v2.mlmodelc/weights/weight.bin", size: 10, in: s.modelDirectory)
        guard case .unknownVariant(let reason) = s.status() else { Issue.record("expected unknownVariant, got \(s.status())"); return }
        #expect(reason.contains("Encoder_v2.mlmodelc"))
    }

    @Test func fingerprintIsStableAndChangesWithAFile() throws {
        let s = try installedStore()
        let first = try #require(s.fingerprint())
        #expect(s.fingerprint() == first)
        try write("config.json", size: 475, in: s.modelDirectory, content: Data(repeating: 0x62, count: 475))
        let second = try #require(s.fingerprint())
        #expect(second != first)
    }

    @Test func fingerprintChangesWhenASmallModelFileChangesWithTheSameSize() throws {
        let s = try installedStore()
        let first = try #require(s.fingerprint())
        let graph = "Encoder.mlmodelc/model.mil"
        let size = Int(ModelManifest.parakeetV3.files[graph]!)
        try write(graph, size: Int64(size), in: s.modelDirectory, content: Data(repeating: 0x7a, count: size))
        #expect(s.status() == .ready)
        #expect(try #require(s.fingerprint()) != first)
    }

    @Test func fingerprintIncludesThePin() throws {
        let s = try installedStore()
        #expect(s.fingerprint(pin: "fluidaudio-0.17.8/v3/int8") != s.fingerprint())
        #expect(s.fingerprint() == s.fingerprint(pin: ModelManifest.pin))
        #expect(ModelManifest.pin == "fluidaudio-0.17.7/v3/int8")
    }

    @Test func removeDeletesOnlyTheModelDirectoryNotItsSiblings() throws {
        let s = try installedStore()
        let siblings = ["parakeet-tdt-0.6b-v3-coreml", "parakeet-tdt-0.6b-v2-coreml"].map { s.directory.appendingPathComponent($0) }
        for sibling in siblings { try write("marker", size: 1, in: sibling, content: Data([1])) }
        try s.remove()
        #expect(s.status() == .missing)
        for sibling in siblings { #expect(FileManager.default.fileExists(atPath: sibling.appendingPathComponent("marker").path)) }
        try s.remove() // bez modelu: bez błędu
    }

    @Test func coremlFolderAloneIsMissing() throws {
        let s = store(try makeRoot())
        try write("Encoder.mlmodelc/coremldata.bin", size: 1, in: s.directory.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml"), content: Data([1]))
        #expect(s.status() == .missing)
    }

    @Test func extraFilesAreIgnoredAndNotInTheFingerprint() throws {
        let s = try installedStore()
        let before = try #require(s.fingerprint())
        try write("Encoder_v2.mlmodelc/weights/weight.bin", size: 10, in: s.modelDirectory)
        try write("notes.txt", size: 1, in: s.modelDirectory, content: Data([1]))
        #expect(s.status() == .ready)
        #expect(s.fingerprint() == before)
    }

    @Test func downloadProgressIsMonotonicAcrossFluidAudioResets() {
        var mapper = DownloadProgressMapper()
        // listing -> pobieranie 0…0,5 (z cofnięciem, bo zdarzenia przychodzą współbieżnie) -> kompilacja (3 spadki surowego ułamka)
        let sequence: [DownloadProgressMapper.Phase] = [
            .listing, .downloading(fraction: 0), .downloading(fraction: 0.2), .downloading(fraction: 0.15), .downloading(fraction: 0.5),
            .compiling, .compiling, .compiling,
        ]
        let out = sequence.map { mapper.map($0) }
        #expect(out[0] == nil)
        #expect(out[2] == 0.4)
        #expect(out[3] == 0.4)
        #expect(out[4] == 1)
        #expect(out[5...].allSatisfy { $0 == nil })
        var last = -1.0
        for value in out.compactMap({ $0 }) { #expect(value >= last); last = value }
        // po kompilacji spóźnione zdarzenie pobierania nie obniża paska
        #expect(mapper.map(.downloading(fraction: 0.1)) == 1)
    }

    @Test func defaultDirectoryMatchesFluidAudioCache() {
        let ours = store(ModelStore.resolveDirectory(env: [:])).modelDirectory
        #expect(ours.standardizedFileURL.path == AsrModels.defaultCacheDirectory(for: .v3).standardizedFileURL.path)
    }

    @Test func downloadIsNoOpWhenAlreadyReady() async throws {
        let calls = Calls()
        let s = try installedStore()
        try await store(s.directory, download: { _, force, _ in calls.add(force) }).download(progress: { _ in })
        #expect(calls.forces.isEmpty)
    }

    /// Fałszywy downloader: zapisuje force i dopełnia model (jak FluidAudio po udanym pobraniu).
    private func fixer(_ calls: Calls) -> ModelStore.Download {
        { dir, force, _ in
            calls.add(force)
            try writeAll(into: dir)
        }
    }

    @Test func missingModelDownloadsWithoutForce() async throws {
        let calls = Calls()
        try await store(try makeRoot(), download: fixer(calls)).download(progress: { _ in })
        #expect(calls.forces == [false])
    }

    @Test func wrongSizeFileDownloadsWithForce() async throws {
        let calls = Calls()
        let s = try installedStore()
        try write("Decoder.mlmodelc/model.mil", size: 3, in: s.modelDirectory)
        try await store(s.directory, download: fixer(calls)).download(progress: { _ in })
        #expect(calls.forces == [true])
    }

    @Test func interruptedDownloadWithMissingFilesKeepsItsPartialFilesByNotForcing() async throws {
        // Brakuje plików (reszta ma dobry rozmiar), a FluidAudio nie uważa modelu za kompletny: wznawia, nie kasuje.
        let calls = Calls()
        let s = try installedStore(skipping: ["Encoder.mlmodelc/weights/weight.bin", "config.json"])
        try write("Encoder.mlmodelc/weights/weight.bin.partial", size: 1000, in: s.modelDirectory)
        try await store(s.directory, download: fixer(calls), modelsExist: { _ in false }).download(progress: { _ in })
        #expect(calls.forces == [false])
    }

    @Test func missingFileThatFluidAudioDoesNotRequireDownloadsWithForce() async throws {
        // `modelsExist` (sama obecność wymaganych plików) mówi „jest", a manifest wykrywa brak `config.json` — bez force nic by się nie naprawiło.
        let calls = Calls()
        let s = try installedStore(skipping: ["config.json"])
        try await store(s.directory, download: fixer(calls), modelsExist: { _ in true }).download(progress: { _ in })
        #expect(calls.forces == [true])
    }

    @Test func downloadValidatesTheManifestAfterwards() async throws {
        let bad: ModelStore.Download = { dir, _, _ in
            try writeAll(into: dir)
            try write("config.json", size: 476, in: dir, content: Data(repeating: 0x61, count: 476))
        }
        do {
            try await store(try makeRoot(), download: bad).download(progress: { _ in })
            Issue.record("expected the post-download check to throw")
        } catch {
            #expect(error is ModelStoreError)
            #expect(error.localizedDescription.contains("differs from the version this build expects"))
            #expect(error.localizedDescription.contains("config.json"))
        }
    }

    @Test func envOverrideChangesTheDirectoryOnlyInDebug() {
        let overridden = ModelStore.resolveDirectory(env: ["MEETNOTES_MODEL_STORE": "/tmp/mn-store-x"])
        let normal = ModelStore.resolveDirectory(env: [:])
        #expect(normal.path.hasSuffix("Application Support/FluidAudio/Models"))
        #if DEBUG
        #expect(overridden.path == "/tmp/mn-store-x")
        #else
        #expect(overridden == normal)
        #endif
    }
}
