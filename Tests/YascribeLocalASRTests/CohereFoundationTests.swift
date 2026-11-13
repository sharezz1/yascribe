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

private func cohereStore(_ root: URL, fileDownload: @escaping ModelStore.FileDownload = { _, _, _ in },
                         diskSpace: @escaping ModelStore.DiskSpace = plenty) -> ModelStore {
    isolatedModelStore(model: .cohereTranscribe6bit, directory: root, fileDownload: fileDownload, diskSpace: diskSpace)
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
    @Test func registryIsPinnedAndExposedAsExperimental() {
        #expect(LocalASRModel.cohereTranscribe6bit.manifest.files.count == 19)
        #expect(LocalASRModel.cohereTranscribe6bit.pin == "hf:BarathwajAnandan/cohere-transcribe-03-2026-CoreML-6bit@79320e92e2e220ed2ed2a9acb41f3caff06acb85")
        // N4: oba modele dla roli ASR; Cohere z oznaczeniem „Experimental”, Parakeet bez nazwy (pokazuje się id jak dotąd).
        #expect(LocalASRModels.models(for: .asr).map(\.id) == [LocalASRModels.parakeetV3, LocalASRModels.cohereTranscribe6bit])
        #expect(LocalASRModels.displayName(LocalASRModels.cohereTranscribe6bit) == "Cohere Transcribe 6-bit (Experimental)")
        #expect(LocalASRModels.displayName(LocalASRModels.parakeetV3) == nil)
        #expect(ModelCatalog.visible(LocalASRModels.models(for: .asr), role: .asr, query: "").count == 2)
        #expect(!LocalASRModel.cohereTranscribe6bit.manifest.files.keys.contains { $0.hasPrefix(".compiled/") })
        #expect(!LocalASRModel.cohereTranscribe6bit.manifest.files.keys.contains { $0.contains("cross_kv") })
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
        let store = cohereStore(root, fileDownload: { source, part, progress in
            #expect(source.absoluteString.hasPrefix("https://huggingface.co/\(LocalASRModel.cohereRepository)/resolve/\(LocalASRModel.cohereRevision)/"))
            #expect(part.pathExtension == "part")
            #expect(!FileManager.default.fileExists(atPath: part.deletingPathExtension().path))
            let name = String(source.path.split(separator: "/").dropFirst(4).joined(separator: "/"))
            let size = try #require(ModelManifest.cohereTranscribe6bit.files[name])
            progress(size / 2)
            try sparseFile(part, size: size)
            await calls.add(name)
        })
        let received = ByteProgress()
        try await store.download { fraction in
            #expect(fraction.map { $0 > 0 && $0 <= 1 } == true)
            received.add(Int64((fraction ?? 0) * 1_000_000_000))
        }
        #expect(received.values.count == 38)
        #expect(store.status() == .ready)
        #expect(await calls.paths.count == 19)
        for name in store.model.manifest.files.keys {
            #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent(name + ".part").path))
        }
    }

    @Test func badDownloadIsNeverPublishedAndPartIsCleaned() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root, fileDownload: { _, part, _ in try sparseFile(part, size: 1) })
        await #expect(throws: ModelStoreError.self) { try await store.download { _ in } }
        #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent("LICENSE").path))
        #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent("LICENSE.part").path))
        #expect(store.status() != .ready)
    }

    @Test func interruptedDownloadCleansPart() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root, fileDownload: { _, part, _ in
            try sparseFile(part, size: 10)
            throw CancellationError()
        })
        await #expect(throws: CancellationError.self) { try await store.download { _ in } }
        #expect(!FileManager.default.fileExists(atPath: store.modelDirectory.appendingPathComponent("LICENSE.part").path))
    }

    @Test func forceAndRemoveTouchOnlySelectedModelIncludingCompiled() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root, fileDownload: { source, part, progress in
            let name = String(source.path.split(separator: "/").dropFirst(4).joined(separator: "/"))
            try sparseFile(part, size: try #require(ModelManifest.cohereTranscribe6bit.files[name]))
        })
        try install(store)
        let neighbor = isolatedModelStore(directory: root).modelDirectory.appendingPathComponent("marker")
        try sparseFile(neighbor, size: 17)
        let stale = store.compiledDirectory.appendingPathComponent("stale")
        try sparseFile(stale, size: 1)
        try sparseFile(store.modelDirectory.appendingPathComponent("LICENSE"), size: 1)
        try await store.download { _ in }
        #expect(store.status() == .ready)
        #expect(FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: neighbor.path))
        try sparseFile(stale, size: 1)
        try store.remove()
        #expect(!FileManager.default.fileExists(atPath: store.compiledDirectory.path))
        #expect(FileManager.default.fileExists(atPath: neighbor.path))
    }

    @Test func diskGateAppliesOnlyToCohereAndParakeetWritesWaitForReaders() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Requests()
        for model in LocalASRModel.allCases {
            let store = isolatedModelStore(model: model, directory: root, download: { _, _, _ in
                await calls.add(model.id)
                for (name, size) in model.manifest.files { try sparseFile(root.appendingPathComponent(model.subdirectory).appendingPathComponent(name), size: size) }
            }, diskSpace: { _ in ModelDiskLocation(volume: "full", freeBytes: 1, path: root.path) })
            if model == .parakeetV3 {
                // Bez bramki dysku (jak przed N1), ale zapis czeka na żywych klientów (LOCK_SH) jak w Cohere.
                do {
                    let reader = try store.acquireLock(shared: true)
                    let second = try store.acquireLock(shared: true) // dwaj klienci Parakeeta naraz
                    await #expect(throws: ModelStoreError.self) { try await store.download { _ in } }
                    withExtendedLifetime((reader, second)) {}
                }
                try await store.download { _ in }
                // Osobny zakres: w DEBUG zmienna lokalna żyje do końca bloku, więc końcowe remove() trafiłoby na czytelnika.
                do {
                    let reader = try store.acquireLock(shared: true)
                    try await store.download { _ in } // gotowy model: no-op także przy żywym kliencie
                    // Katalog modelu już istnieje, więc remove() dochodzi do LOCK_EX i odmawia (brak katalogu to no-op bez blokady).
                    #expect(throws: ModelStoreError.self) { try store.remove() }
                    #expect(store.status() == .ready)
                    withExtendedLifetime(reader) {}
                }
                try store.remove()
            } else {
                do { try await store.download { _ in }; Issue.record("Disk gate must refuse") }
                catch let error as ModelStoreError {
                    #expect(error.message.contains(root.path) && error.message.contains("GB"))
                }
            }
        }
        #expect(await calls.paths == [LocalASRModel.parakeetV3.id])
    }

    @Test func downloaderCannotClaimSuccessWithoutReady() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = isolatedModelStore(model: .cohereTranscribe6bit, directory: root, download: { _, _, _ in }, diskSpace: plenty)
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
            do { _ = try store.acquireLock(); Issue.record("second owner must be refused") }
            catch let error as ModelStoreError { #expect(error.message.contains("busy in another transcription")) }
            #expect(!store.lockURL.path.hasPrefix(store.modelDirectory.path + "/"))
        }
        let next = try store.acquireLock()
        withExtendedLifetime(next) {}
    }

    @Test func activeOwnerRefusesRemovalAndRepair() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Requests()
        let store = cohereStore(root, fileDownload: { _, _, _ in await calls.add("download") })
        try install(store)
        let valid = store.modelDirectory.appendingPathComponent("coreml_manifest.json")
        let bytes = try Data(contentsOf: valid)
        try sparseFile(store.modelDirectory.appendingPathComponent("LICENSE"), size: 1)
        let owner = try store.acquireLock()
        defer { withExtendedLifetime(owner) {} }
        #expect(throws: ModelStoreError.self) { try store.remove() }
        do {
            try await store.download { _ in }
            Issue.record("Active owner must refuse repair")
        } catch let error as ModelStoreError { #expect(error.message.contains("busy")) }
        #expect(try Data(contentsOf: valid) == bytes)
        #expect(await calls.paths.isEmpty)
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
        // Ten proces nie trzyma blokady, więc konflikt jest z innym procesem (F2 R01: inny komunikat niż w aplikacji).
        do { _ = try store.acquireLock(shared: true); Issue.record("other process must refuse") }
        catch let error as ModelStoreError { #expect(error.message == "Another Yascribe process is using this model.") }
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

extension ModelLockTests {
    @Test func lockCloseOnExecAllowsReacquisitionWhileProcessLives() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = cohereStore(root)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["30"]
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        do {
            let owner = try store.acquireLock()
            var info = stat()
            try #require(stat(store.lockURL.path, &info) == 0)
            let descriptors = (0..<1024).filter { fd in
                var candidate = stat()
                return fstat(Int32(fd), &candidate) == 0 && candidate.st_ino == info.st_ino && candidate.st_dev == info.st_dev
            }
            try #require(!descriptors.isEmpty)
            // Process może dodatkowo zamykać deskryptory; sprawdzamy też sam kontrakt open().
            #expect(descriptors.allSatisfy { fcntl(Int32($0), F_GETFD) & FD_CLOEXEC != 0 })
            try child.run()
            withExtendedLifetime(owner) {}
        }
        #expect(child.isRunning)
        let next = try store.acquireLock(); withExtendedLifetime(next) {}
    }

    @Test func productionLocksUseOwnRootAndMissingRemovalCreatesNothing() throws {
        #if DEBUG
        #expect(ModelStore.lockRoot(env: ["YASCRIBE_DATA_DIR": "/tmp/x/.devdata"]).path == "/tmp/x/.devdata")
        #expect(ModelStore.lockRoot(env: ["YASCRIBE_MODEL_STORE": "/tmp/own-root", "YASCRIBE_DATA_DIR": "/tmp/x/.devdata"]).path == "/tmp/own-root")
        #endif
        #expect(ModelStore.lockRoot(env: [:]).path.hasSuffix("/Application Support/Yascribe"))
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        for model in LocalASRModel.allCases {
            let store = ModelStore(model: model, directory: root)
            #expect(store.lockURL.deletingLastPathComponent().deletingLastPathComponent().path == ModelStore.lockRoot(env: ProcessInfo.processInfo.environment).path)
            #expect(store.lockURL.lastPathComponent == model.id + ".lock")
            let isolated = isolatedModelStore(model: model, directory: root)
            try isolated.remove()
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".locks").path))
        }
    }
}

extension ModelDiskBudgetTests {
    @Test func downloadsCountOnlyMissingBytesAndTemporaryLargestFileOnOtherVolume() async throws {
        let store = ModelDiskLocation(volume: "one", freeBytes: 1_000_003_000, path: "/models")
        let temp = ModelDiskLocation(volume: "two", freeBytes: 2_000, path: "/tmp")
        let shared = ModelDiskBudget.need(modelBytes: 2_000_000_000, operation: .download,
            missingBytes: 3_000, largestMissingFile: 2_000, store: store, temporary: store, e5rt: store)
        #expect(shared.count == 1 && shared[0].bytes == 1_000_003_000 && shared[0].fits)
        let separate = ModelDiskBudget.need(modelBytes: 2_000_000_000, operation: .download,
            missingBytes: 3_000, largestMissingFile: 2_000, store: store, temporary: temp, e5rt: store)
        #expect(separate.map(\.bytes) == [1_000_003_000, 2_000])
        #expect(separate.allSatisfy { $0.fits })
        #expect(shared[0].message.contains("/models") && shared[0].message.contains("GB"))
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = cohereStore(root)
        try install(model)
        try FileManager.default.removeItem(at: model.modelDirectory.appendingPathComponent("README.md"))
        let needs = try model.diskNeed(operation: .download)
        #expect(needs.map(\.bytes) == [1_000_003_608])
    }

    @Test func downloadDelegateReportsIntermediateBytes() {
        let received = ByteProgress()
        let delegate = ModelDownloadProgress { received.add($0) }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: URL(string: "https://example.test/model")!)
        delegate.urlSession(session, downloadTask: task, didWriteData: 40, totalBytesWritten: 40, totalBytesExpectedToWrite: 100)
        delegate.urlSession(session, downloadTask: task, didWriteData: 60, totalBytesWritten: 100, totalBytesExpectedToWrite: 100)
        #expect(received.values == [40, 100])
    }
}

private final class ByteProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int64] = []
    var values: [Int64] { lock.withLock { storage } }
    func add(_ n: Int64) { lock.withLock { storage.append(n) } }
}

extension CohereStoreTests {
    @Test func cohereRepairNeverRequestsForce() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = isolatedModelStore(model: .cohereTranscribe6bit, directory: root, download: { directory, force, _ in
            #expect(!force)
            try sparseFile(directory.appendingPathComponent("LICENSE"), size: ModelManifest.cohereTranscribe6bit.files["LICENSE"]!)
        }, diskSpace: plenty)
        try install(store)
        try sparseFile(store.modelDirectory.appendingPathComponent("LICENSE"), size: 1)
        let marker = store.compiledDirectory.appendingPathComponent("keep")
        try sparseFile(marker, size: 23)
        try await store.download { _ in }
        #expect(store.status() == .ready)
        #expect(try Data(contentsOf: marker).count == 23)
    }
}
