import CoreML
import Foundation
import Testing
@testable import YascribeLocalASR

private func portRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func manifestFixture() -> [String: Any] {
    var vocabulary = Array(repeating: "unused", count: 160)
    vocabulary[3] = "<|endoftext|>"
    vocabulary[62] = "<|en|>"
    vocabulary[148] = "<|pl|>"
    vocabulary[5] = "<|pnc|>"
    vocabulary[8] = "<|itn|>"
    return ["model_id": "test", "sample_rate": 16_000, "max_audio_samples": 560_000, "max_audio_seconds": 35,
            "max_feature_frames": 3501, "max_encoder_frames": 438, "decoder_max_len": 108,
            "default_max_new_tokens": 96, "prompt_ids": [62, 62, 5, 8], "eos_token_id": 3, "id_to_token": vocabulary,
            "frontend": ["package": "cohere_frontend.mlpackage", "inputs": ["audio", "length"], "outputs": ["features", "length"]],
            "encoder": ["package": "cohere_encoder.mlpackage", "inputs": ["features", "length"], "outputs": ["hidden", "length"]],
            "decoder": ["package": "cohere_decoder_fullseq_masked.mlpackage", "inputs": ["hidden", "ids", "mask", "cross"], "outputs": ["logits"]]]
}

private func loadFixture(_ fixture: [String: Any], at root: URL) throws -> CohereTranscribeAsrManifest {
    try JSONSerialization.data(withJSONObject: fixture).write(to: root.appendingPathComponent("coreml_manifest.json"))
    return try CohereTranscribeAsrModels.loadManifest(from: root)
}

private func fakeCompiled(at directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("weights"), withIntermediateDirectories: true)
    try Data([1, 2]).write(to: directory.appendingPathComponent("coremldata.bin"))
    try Data([3, 4]).write(to: directory.appendingPathComponent("model.mil"))
    try Data([5, 6]).write(to: directory.appendingPathComponent("weights/weight.bin"))
    return directory
}

@Suite struct CoherePortTests {
    @Test func eosComesFromEachDecodeAndIgnoresPrompt() {
        let withEOS = CohereDecodedTokens(tokens: [62, 17, 3], generatedFrom: 1, eosTokenID: 3)
        let withoutEOS = CohereDecodedTokens(tokens: [62, 17, 19], generatedFrom: 1, eosTokenID: 3)
        #expect(withEOS.reachedEOS)
        #expect(!withoutEOS.reachedEOS)
        #expect(!CohereDecodedTokens(tokens: [3], generatedFrom: 1, eosTokenID: 3).reachedEOS)
        #expect(!CohereDecodedTokens(tokens: [], generatedFrom: 0, eosTokenID: 3).reachedEOS)
        #expect(CohereTranscriptionResult(text: "text", chunkEOS: [withEOS.reachedEOS, withoutEOS.reachedEOS]).truncationCount == 1)
    }

    @Test func manifestRejectsMissingOrInvalidEOS() throws {
        let root = try portRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try loadFixture(manifestFixture(), at: root).eosTokenID == 3)
        var missing = manifestFixture()
        missing.removeValue(forKey: "eos_token_id")
        #expect(throws: CohereTranscribeAsrError.self) { try loadFixture(missing, at: root) }
        var invalid = manifestFixture()
        invalid["eos_token_id"] = 500
        #expect(throws: CohereTranscribeAsrError.self) { try loadFixture(invalid, at: root) }
        invalid["eos_token_id"] = 62
        #expect(throws: CohereTranscribeAsrError.self) { try loadFixture(invalid, at: root) }
    }

    @Test func promptUsesVocabularyAndReplacesBothLanguageTokensOnly() throws {
        let root = try portRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try loadFixture(manifestFixture(), at: root)
        #expect(manifest.maxAudioSeconds == 35)
        #expect(try manifest.promptIDs(for: "pl") == [148, 148, 5, 8])
        #expect(throws: CohereTranscribeAsrError.self) { try manifest.promptIDs(for: "missing") }
        #expect(throws: CohereTranscribeAsrError.self) { try manifest.promptIDs(for: "pl", template: [5, 8]) }
        var moved = manifestFixture()
        var vocabulary = try #require(moved["id_to_token"] as? [String])
        vocabulary.swapAt(148, 150)
        moved["id_to_token"] = vocabulary
        #expect(try loadFixture(moved, at: root).promptIDs(for: "pl") == [150, 150, 5, 8])
    }

    @Test func compilationKeyUsesFingerprintUnitsAndFormatWithSameDate() throws {
        let root = try portRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source")
        try Data([1]).write(to: file)
        let timestamp = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
        let key = CohereModelCompilation.key(fingerprint: "first", configuration: .yascribe)
        try Data([2]).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
        #expect(CohereModelCompilation.key(fingerprint: "second", configuration: .yascribe) != key)
        #expect(CohereModelCompilation.key(fingerprint: "first", configuration: .init(uniform: .cpuOnly)) != key)
        #expect(CohereModelCompilation.key(fingerprint: "first", configuration: .yascribe, version: 2) != key)
        #expect(CohereModelCompilation.key(fingerprint: "first", configuration: .yascribe) == key)
    }

    @Test func compilationPublishesOnlyCompleteArtifactAndCleansTemporary() throws {
        let root = try portRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("compiled")
        let temp = root.appendingPathComponent("temporary")
        let package = root.appendingPathComponent("cohere_encoder.mlpackage")
        let result = try CohereModelCompilation.compile(package: package, root: cache, key: "key", compiler: { _ in
            #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("key/cohere_encoder.mlmodelc").path))
            return try fakeCompiled(at: temp)
        })
        #expect(CohereModelCompilation.isComplete(at: result))
        #expect(!FileManager.default.fileExists(atPath: temp.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path) == ["key"])
        _ = try CohereModelCompilation.compile(package: package, root: cache, key: "key", compiler: { _ in
            Issue.record("Complete compilation must be reused")
            throw CancellationError()
        })
        try FileManager.default.removeItem(at: result.appendingPathComponent("weights/weight.bin"))
        #expect(!CohereModelCompilation.isComplete(at: result))
        #expect(!CohereModelCompilation.isComplete(at: CohereModelCompilation.directory(package: package.lastPathComponent, root: cache, key: "changed")))
    }

    @Test func failedCompilationCleansStagingAndTemporary() throws {
        let root = try portRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("compiled")
        let temp = root.appendingPathComponent("temporary")
        #expect(throws: ModelStoreError.self) {
            try CohereModelCompilation.compile(package: root.appendingPathComponent("encoder.mlpackage"), root: cache, key: "key", compiler: { _ in
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                return temp
            })
        }
        #expect(!FileManager.default.fileExists(atPath: temp.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path) == ["key"])
        #expect(!CohereModelCompilation.isComplete(at: cache.appendingPathComponent("key/encoder.mlmodelc")))
    }

    @Test func interruptionAndNoSpaceDuringCopyCleanBothLocations() throws {
        let root = try portRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("compiled")
        let temp = root.appendingPathComponent("temporary")
        for noSpace in [false, true] {
            let package = root.appendingPathComponent("encoder.mlpackage")
            do {
                _ = try CohereModelCompilation.compile(package: package, root: cache, key: "key", copy: { _, staging in
                    #expect(staging.lastPathComponent.hasPrefix(".staging-"))
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    try Data([1]).write(to: staging.appendingPathComponent("partial"))
                    if noSpace { throw POSIXError(.ENOSPC) }
                    throw CancellationError()
                }, compiler: { _ in try fakeCompiled(at: temp) })
                Issue.record("Copy failure must prevent publication")
            } catch is CancellationError { #expect(!noSpace) }
              catch let error as POSIXError { #expect(noSpace && error.code == .ENOSPC) }
            #expect(!FileManager.default.fileExists(atPath: temp.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path) == ["key"])
            #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("key/encoder.mlmodelc").path))
        }
    }

    @Test func storeRequiresEveryCompiledComponentForCurrentFingerprint() throws {
        let root = try portRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ModelStore(model: .cohereTranscribe6bit, directory: root)
        for (name, size) in store.model.manifest.files {
            let file = store.modelDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
        }
        let key = CohereModelCompilation.key(fingerprint: try #require(store.fingerprint()), configuration: .yascribe)
        #expect(!store.compiledModelsReady())
        for package in CohereModelCompilation.packages {
            _ = try CohereModelCompilation.compile(package: store.modelDirectory.appendingPathComponent(package), root: store.compiledDirectory, key: key, compiler: { _ in
                try fakeCompiled(at: root.appendingPathComponent("temp"))
            })
        }
        #expect(store.compiledModelsReady())
        let manifest = store.modelDirectory.appendingPathComponent("coreml_manifest.json")
        let date = try #require(FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date)
        let handle = try FileHandle(forWritingTo: manifest)
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: manifest.path)
        #expect(store.status() == .ready)
        #expect(!store.compiledModelsReady())
    }
}
