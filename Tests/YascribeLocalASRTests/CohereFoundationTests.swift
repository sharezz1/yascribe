import CoreML
import Darwin
import Foundation
import Testing
import YascribeProviders
@testable import YascribeLocalASR

private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func sparseFile(_ url: URL, size: Int64) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    try file.truncate(atOffset: UInt64(size))
}

private let plenty: ModelStore.DiskSpace = { _ in ModelDiskLocation(volume: "test", freeBytes: 100_000_000_000) }

private func cohereStore(_ root: URL, fileDownload: @escaping ModelStore.FileDownload = { _, _ in },
                         diskSpace: @escaping ModelStore.DiskSpace = plenty) -> ModelStore {
    ModelStore(model: .cohereTranscribe6bit, directory: root, fileDownload: fileDownload, diskSpace: diskSpace)
}

private func install(_ store: ModelStore) throws {
    for (name, size) in store.model.manifest.files {
        try sparseFile(store.modelDirectory.appendingPathComponent(name), size: size)
    }
}

private actor Requests {
    var paths: [String] = []
    func add(_ path: String) { paths.append(path) }
}

@Suite struct CohereStoreTests {
    @Test func registryIsPinnedAndNotExposed() {
        #expect(LocalASRModel.cohereTranscribe6bit.manifest.files.count == 22)
        #expect(LocalASRModel.cohereTranscribe6bit.pin == "hf:BarathwajAnandan/cohere-transcribe-03-2026-CoreML-6bit@79320e92e2e220ed2ed2a9acb41f3caff06acb85")
        #expect(LocalASRModels.models(for: .asr).map(\.id) == [LocalASRModels.parakeetV3])
        #expect(!LocalASRModel.cohereTranscribe6bit.manifest.files.keys.contains { $0.hasPrefix(".compiled/") })
        #expect(CohereModelCompilation.packages.count == 4)
        #expect(!CohereModelCompilation.packages.contains { $0.contains("cross_kv") })
    }

    @Test func directoryUsesYascribeAndDebugOverride() throws {
        #expect(ModelStore.resolveDirectory(model: .cohereTranscribe6bit, env: [:]).path.hasSuffix("Application Support/Yascribe/Models"))
        #if DEBUG
        #expect(ModelStore.resolveDirectory(model: .cohereTranscribe6bit, env: ["YASCRIBE_MODEL_STORE": "/tmp/n1-store"]).path == "/tmp/n1-store")
        #endif
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(cohereStore(root).modelDirectory.lastPathComponent == "cohere-transcribe-03-2026-coreml-6bit")
    }

    @Test func statusesCheckEverySourceSize() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root)
        #expect(store.status() == .missing)
        try install(store)
        #expect(store.status() == .ready)
        let path = "cohere_encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
        try sparseFile(store.modelDirectory.appendingPathComponent(path), size: 10)
        guard case .invalid(let reason) = store.status() else { Issue.record("Expected invalid size"); return }
        #expect(reason.contains(path))
        #expect(store.fingerprint() == nil)
    }

    @Test func downloaderStagesValidatesMovesAndReportsBytes() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Requests()
        let store = cohereStore(root, fileDownload: { source, part in
            #expect(source.absoluteString.hasPrefix("https://huggingface.co/\(LocalASRModel.cohereRepository)/resolve/\(LocalASRModel.cohereRevision)/"))
            #expect(part.pathExtension == "part")
            #expect(!FileManager.default.fileExists(atPath: part.deletingPathExtension().path))
            let name = String(source.path.split(separator: "/").dropFirst(4).joined(separator: "/"))
            let size = try #require(ModelManifest.cohereTranscribe6bit.files[name])
            try sparseFile(part, size: size)
            await calls.add(name)
        })
        try await store.download { fraction in #expect(fraction.map { $0 > 0 && $0 <= 1 } == true) }
        #expect(store.status() == .ready)
        #expect(await calls.paths.count == 22)
        for name in store.model.manifest.files.keys {
            #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent(name + ".part").path))
        }
    }

    @Test func badDownloadIsNeverPublishedAndPartIsCleaned() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root, fileDownload: { _, part in try sparseFile(part, size: 1) })
        await #expect(throws: ModelStoreError.self) { try await store.download { _ in } }
        #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent("LICENSE").path))
        #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent("LICENSE.part").path))
        #expect(store.status() != .ready)
    }

    @Test func interruptedDownloadCleansPart() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root, fileDownload: { _, part in
            try sparseFile(part, size: 10)
            throw CancellationError()
        })
        await #expect(throws: CancellationError.self) { try await store.download { _ in } }
        #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent("LICENSE.part").path))
    }

    @Test func forceAndRemoveTouchOnlySelectedModelIncludingCompiled() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root, fileDownload: { source, part in
            let name = String(source.path.split(separator: "/").dropFirst(4).joined(separator: "/"))
            try sparseFile(part, size: try #require(ModelManifest.cohereTranscribe6bit.files[name]))
        })
        try install(store)
        let neighbor = ModelStore(directory: root).modelDirectory.appendingPathComponent("marker")
        try sparseFile(neighbor, size: 17)
        let stale = store.compiledDirectory.appendingPathComponent("stale")
        try sparseFile(stale, size: 1)
        try sparseFile(store.modelDirectory.appendingPathComponent("LICENSE"), size: 1)
        try await store.download { _ in }
        #expect(store.status() == .ready)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: neighbor.path))
        try sparseFile(stale, size: 1)
        try store.remove()
        #expect(!FileManager.default.fileExists(atPath: store.compiledDirectory.path))
        #expect(FileManager.default.fileExists(atPath: neighbor.path))
    }

    @Test func diskGateIsInSharedDownloadPathForBothModels() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Requests()
        for model in LocalASRModel.allCases {
            let store = ModelStore(model: model, directory: root, download: { _, _, _ in await calls.add("download") },
                diskSpace: { _ in ModelDiskLocation(volume: "full", freeBytes: 1) })
            await #expect(throws: ModelStoreError.self) { try await store.download { _ in } }
        }
        #expect(await calls.paths.isEmpty)
    }

    @Test func downloaderCannotClaimSuccessWithoutReady() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ModelStore(model: .cohereTranscribe6bit, directory: root, download: { _, _, _ in }, diskSpace: plenty)
        await #expect(throws: ModelStoreError.self) { try await store.download { _ in } }
    }
}

@Suite struct ModelLockTests {
    @Test func secondOwnerIsRefusedAndReleaseAllowsReacquisition() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root)
        do {
            let owner = try store.acquireLock()
            defer { withExtendedLifetime(owner) {} }
            #expect(throws: ModelStoreError.self) { try store.acquireLock() }
            #expect(!store.lockURL.path.hasPrefix(store.modelDirectory.path + "/"))
        }
        let next = try store.acquireLock()
        withExtendedLifetime(next) {}
    }

    @Test func activeOwnerRefusesRemovalAndRepair() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root)
        try install(store)
        try sparseFile(store.modelDirectory.appendingPathComponent("LICENSE"), size: 1)
        let owner = try store.acquireLock()
        defer { withExtendedLifetime(owner) {} }
        #expect(throws: ModelStoreError.self) { try store.remove() }
        await #expect(throws: ModelStoreError.self) { try await store.download { _ in } }
        #expect(FileManager.default.fileExists(atPath: store.modelDirectory.path))
    }

    @Test func killedChildReleasesKernelLock() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root)
        // Utworzenie trwałego inode przed startem dziecka; dziecko korzysta z tego samego systemowego flock.
        do { let initial = try store.acquireLock(); withExtendedLifetime(initial) {} }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-u", "-c", "import fcntl,sys,signal; f=open(sys.argv[1],'r+'); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB); print('locked',flush=True); signal.pause()", store.lockURL.path]
        let pipe = Pipe()
        child.standardOutput = pipe
        try child.run()
        defer { if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() } }
        let output = pipe.fileHandleForReading.availableData
        #expect(String(decoding: output, as: UTF8.self) == "locked\n")
        #expect(throws: ModelStoreError.self) { try store.acquireLock() }
        kill(child.processIdentifier, SIGKILL)
        child.waitUntilExit()
        let owner = try store.acquireLock()
        withExtendedLifetime(owner) {}
    }
}

@Suite struct ModelDiskBudgetTests {
    @Test func sharedVolumeAddsAllThreeCosts() {
        let common = ModelDiskLocation(volume: "one", freeBytes: 9_000_000_000)
        let need = ModelDiskBudget.need(modelBytes: 1_000_000_000, operation: .load, store: common, temporary: common, e5rt: common)
        #expect(need.count == 1)
        #expect(need.first?.bytes == 5_300_000_000)
        #expect(need.first?.fits == true)
    }

    @Test func separateVolumesAndE5RTWithCompiledModel() {
        let store = ModelDiskLocation(volume: "store", freeBytes: 2_000_000_000)
        let temporary = ModelDiskLocation(volume: "tmp", freeBytes: 999_999_999)
        let cache = ModelDiskLocation(volume: "cache", freeBytes: 2_299_999_999)
        let need = ModelDiskBudget.need(modelBytes: 1_000_000_000, operation: .load, store: store, temporary: temporary, e5rt: cache)
        #expect(need.map(\.bytes) == [2_300_000_000, 2_000_000_000, 1_000_000_000])
        #expect(need.map(\.fits) == [false, true, false])
        let compiled = ModelDiskBudget.need(modelBytes: 1_000_000_000, operation: .load, compiledReady: true,
                                            store: store, temporary: temporary, e5rt: cache)
        #expect(compiled.map(\.bytes) == [2_300_000_000, 1_000_000_000])
        #expect(compiled.first?.fits == false)
    }

    @Test func twoLocationsOnOneVolumeStillAdd() {
        let common = ModelDiskLocation(volume: "common", freeBytes: 4_000_000_000)
        let tmp = ModelDiskLocation(volume: "tmp", freeBytes: 1_000_000_000)
        let need = ModelDiskBudget.need(modelBytes: 1_000_000_000, operation: .load, store: common, temporary: tmp, e5rt: common)
        #expect(need.map(\.bytes) == [4_300_000_000, 1_000_000_000])
        #expect(need.map(\.fits) == [false, true])
        let download = ModelDiskBudget.need(modelBytes: 1_000_000_000, operation: .download, store: common, temporary: tmp, e5rt: common)
        #expect(download.map(\.bytes) == [2_000_000_000, 1_000_000_000])
    }
}
