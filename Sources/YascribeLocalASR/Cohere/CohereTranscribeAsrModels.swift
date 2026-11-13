// Źródło: altic-dev/FluidAudio@386f7195670b77f2954c7ee143ec63fcb50b6c3b, Sources/FluidAudio/ASR/Cohere/CohereTranscribeAsrModels.swift
// Licencja: Apache-2.0 (LICENSES/Apache-2.0.txt).
// Zmodyfikowano w Yascribe: własność Core ML w aktorze, walidacja EOS i języka, wstrzyknięta kompilacja według odcisku.

import CoreML
import Foundation
import OSLog

private let cohereLogger = Logger(subsystem: "io.github.sharezz1.yascribe", category: "CohereTranscribeAsrModels")

public enum CohereTranscribeAsrError: LocalizedError {
    case manifestMissing(URL)
    case invalidManifest(URL, Error)
    case modelNotFound(String)
    case invalidModelContract(String)
    case invalidOutput(String)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .manifestMissing(let url):
            return "Cohere manifest not found at \(url.path)"
        case .invalidManifest(let url, let error):
            return "Failed to decode Cohere manifest at \(url.path): \(error.localizedDescription)"
        case .modelNotFound(let name):
            return "Required Cohere CoreML model not found: \(name)"
        case .invalidModelContract(let message):
            return "Invalid Cohere model contract: \(message)"
        case .invalidOutput(let message):
            return "Invalid Cohere model output: \(message)"
        case .generationFailed(let message):
            return "Cohere generation failed: \(message)"
        }
    }
}

public struct CohereTranscribeStageMeta: Codable, Sendable {
    public let package: String
    public let inputs: [String]
    public let outputs: [String]
}

public struct CohereTranscribeCachedDecoderMeta: Codable, Sendable {
    public let package: String
    public let inputs: [String]
    public let outputs: [String]
    public let logitsOutput: String
    public let cacheKOutput: String?
    public let cacheVOutput: String?
    public let numLayers: Int
    public let numHeads: Int
    public let headDim: Int

    private enum CodingKeys: String, CodingKey {
        case package
        case inputs
        case outputs
        case logitsOutput = "logits_output"
        case cacheKOutput = "cache_k_output"
        case cacheVOutput = "cache_v_output"
        case numLayers = "num_layers"
        case numHeads = "num_heads"
        case headDim = "head_dim"
    }
}

public struct CohereTranscribeCrossKVMeta: Codable, Sendable {
    public let package: String
    public let inputs: [String]
    public let outputs: [String]
    public let crossKOutput: String?
    public let crossVOutput: String?

    private enum CodingKeys: String, CodingKey {
        case package
        case inputs
        case outputs
        case crossKOutput = "cross_k_output"
        case crossVOutput = "cross_v_output"
    }
}

public struct CohereTranscribeAsrManifest: Codable, Sendable {
    public let modelID: String
    public let sampleRate: Int
    public let precision: String?
    public let quantize: String?
    public let preemph: Float?
    public let maxAudioSamples: Int
    public let maxAudioSeconds: Double?
    public let overlapSeconds: Double?
    public let overlapSamples: Int?
    public let maxFeatureFrames: Int
    public let maxEncoderFrames: Int
    public let decoderMaxLen: Int
    public let defaultMaxNewTokens: Int
    public let promptIDs: [Int]
    public let eosTokenID: Int
    public let padTokenID: Int?
    public let idToToken: [String]
    public let frontend: CohereTranscribeStageMeta
    public let encoder: CohereTranscribeStageMeta
    public let decoder: CohereTranscribeStageMeta
    public let crossKVProjector: CohereTranscribeCrossKVMeta?
    public let decoderCached: CohereTranscribeCachedDecoderMeta?

    var packages: [String] {
        [frontend.package, encoder.package, decoder.package] +
            [crossKVProjector?.package, decoderCached?.package].compactMap { $0 }
    }

    public var isFp16: Bool { self.precision == "float16" }

    private enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case sampleRate = "sample_rate"
        case precision
        case quantize
        case preemph
        case maxAudioSamples = "max_audio_samples"
        case maxAudioSeconds = "max_audio_seconds"
        case overlapSeconds = "overlap_seconds"
        case overlapSamples = "overlap_samples"
        case maxFeatureFrames = "max_feature_frames"
        case maxEncoderFrames = "max_encoder_frames"
        case decoderMaxLen = "decoder_max_len"
        case defaultMaxNewTokens = "default_max_new_tokens"
        case promptIDs = "prompt_ids"
        case eosTokenID = "eos_token_id"
        case padTokenID = "pad_token_id"
        case idToToken = "id_to_token"
        case frontend
        case encoder
        case decoder
        case crossKVProjector = "cross_kv_projector"
        case decoderCached = "decoder_cached"
    }
}

public struct CohereTranscribeComputeConfiguration: Sendable {
    public let frontend: MLComputeUnits
    public let encoder: MLComputeUnits
    public let crossKV: MLComputeUnits
    public let decoder: MLComputeUnits

    public init(
        frontend: MLComputeUnits,
        encoder: MLComputeUnits,
        crossKV: MLComputeUnits,
        decoder: MLComputeUnits
    ) {
        self.frontend = frontend
        self.encoder = encoder
        self.crossKV = crossKV
        self.decoder = decoder
    }

    public init(uniform computeUnits: MLComputeUnits) {
        self.init(
            frontend: computeUnits,
            encoder: computeUnits,
            crossKV: computeUnits,
            decoder: computeUnits
        )
    }

    // Spike TASK-102 README §5, §8–9: enkoder GPU zawodzi, ANE kompiluje zbyt długo; CPU działa.
    public static let yascribe = Self(frontend: .cpuAndNeuralEngine, encoder: .cpuOnly,
                                      crossKV: .cpuAndNeuralEngine, decoder: .cpuAndNeuralEngine)

}

@available(macOS 15, iOS 18, *)
struct CohereTranscribeAsrModels {
    public static let manifestFile = "coreml_manifest.json"

    public let frontend: MLModel
    public let encoder: MLModel
    public let decoder: MLModel
    public let crossKVProjector: MLModel?
    public let cachedDecoder: MLModel?
    public let manifest: CohereTranscribeAsrManifest
    public let computeConfiguration: CohereTranscribeComputeConfiguration

    static func load(
        from directory: URL, compiledDirectory: URL, fingerprint: String,
        computeConfiguration: CohereTranscribeComputeConfiguration
    ) throws -> CohereTranscribeAsrModels {
        let manifest = try loadManifest(from: directory)
        let key = CohereModelCompilation.key(fingerprint: fingerprint, configuration: computeConfiguration)
        func load(_ name: String, _ units: MLComputeUnits) throws -> MLModel {
            let package = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: package.path) else {
                throw CohereTranscribeAsrError.modelNotFound(name)
            }
            let compiled = try CohereModelCompilation.compile(package: package, root: compiledDirectory, key: key)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = units
            configuration.allowLowPrecisionAccumulationOnGPU = true
            cohereLogger.info("Loading Cohere package \(name, privacy: .public)")
            do { return try MLModel(contentsOf: compiled, configuration: configuration) }
            catch {
                // Nieczytelny artefakt wymaga ponownej kompilacji; źródłowy pakiet pozostaje nietknięty.
                try? FileManager.default.removeItem(at: compiled)
                throw error
            }
        }
        let models = try Self(
            frontend: load(manifest.frontend.package, computeConfiguration.frontend),
            encoder: load(manifest.encoder.package, computeConfiguration.encoder),
            decoder: load(manifest.decoder.package, computeConfiguration.decoder),
            crossKVProjector: manifest.crossKVProjector.map { try load($0.package, computeConfiguration.crossKV) },
            cachedDecoder: manifest.decoderCached.map { try load($0.package, computeConfiguration.decoder) },
            manifest: manifest, computeConfiguration: computeConfiguration)
        try validateLoadedModelContracts(models)
        return models
    }

    static func loadManifest(from directory: URL) throws -> CohereTranscribeAsrManifest {
        let url = directory.appendingPathComponent(Self.manifestFile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CohereTranscribeAsrError.manifestMissing(url)
        }
        do {
            let manifest = try JSONDecoder().decode(CohereTranscribeAsrManifest.self, from: Data(contentsOf: url))
            try manifest.validate()
            return manifest
        } catch {
            throw CohereTranscribeAsrError.invalidManifest(url, error)
        }
    }

    private static func validateLoadedModelContracts(_ models: CohereTranscribeAsrModels) throws {
        let manifest = models.manifest

        try self.validateRequiredFeatureNames(
            stageName: "frontend",
            availableInputs: models.frontend.modelDescription.inputDescriptionsByName,
            expectedInputs: manifest.frontend.inputs,
            availableOutputs: models.frontend.modelDescription.outputDescriptionsByName,
            expectedOutputs: manifest.frontend.outputs
        )
        try self.validateMultiArrayShape(
            stageName: "frontend",
            featureName: manifest.frontend.inputs[0],
            descriptions: models.frontend.modelDescription.inputDescriptionsByName,
            expectedShape: [1, manifest.maxAudioSamples]
        )
        try self.validateMultiArrayShape(
            stageName: "frontend",
            featureName: manifest.frontend.inputs[1],
            descriptions: models.frontend.modelDescription.inputDescriptionsByName,
            expectedShape: [1]
        )

        try self.validateRequiredFeatureNames(
            stageName: "encoder",
            availableInputs: models.encoder.modelDescription.inputDescriptionsByName,
            expectedInputs: manifest.encoder.inputs,
            availableOutputs: models.encoder.modelDescription.outputDescriptionsByName,
            expectedOutputs: manifest.encoder.outputs
        )

        try self.validateRequiredFeatureNames(
            stageName: "decoder",
            availableInputs: models.decoder.modelDescription.inputDescriptionsByName,
            expectedInputs: manifest.decoder.inputs,
            availableOutputs: models.decoder.modelDescription.outputDescriptionsByName,
            expectedOutputs: manifest.decoder.outputs
        )
        if manifest.decoder.inputs.indices.contains(1) {
            try self.validateMultiArrayShape(
                stageName: "decoder",
                featureName: manifest.decoder.inputs[1],
                descriptions: models.decoder.modelDescription.inputDescriptionsByName,
                expectedShape: [1, manifest.decoderMaxLen]
            )
        }
        if manifest.decoder.inputs.indices.contains(2) {
            try self.validateMultiArrayShape(
                stageName: "decoder",
                featureName: manifest.decoder.inputs[2],
                descriptions: models.decoder.modelDescription.inputDescriptionsByName,
                expectedShape: [1, manifest.decoderMaxLen]
            )
        }

        if let crossKVMeta = manifest.crossKVProjector, let crossKVProjector = models.crossKVProjector {
            try self.validateRequiredFeatureNames(
                stageName: "cross-kv projector",
                availableInputs: crossKVProjector.modelDescription.inputDescriptionsByName,
                expectedInputs: crossKVMeta.inputs,
                availableOutputs: crossKVProjector.modelDescription.outputDescriptionsByName,
                expectedOutputs: crossKVMeta.outputs
            )
        }

        if let cachedMeta = manifest.decoderCached, let cachedDecoder = models.cachedDecoder {
            try self.validateRequiredFeatureNames(
                stageName: "cached decoder",
                availableInputs: cachedDecoder.modelDescription.inputDescriptionsByName,
                expectedInputs: cachedMeta.inputs,
                availableOutputs: cachedDecoder.modelDescription.outputDescriptionsByName,
                expectedOutputs: cachedMeta.outputs
            )
            try self.validateOutputBackingFeature(
                stageName: "cached decoder",
                featureName: cachedMeta.logitsOutput,
                descriptions: cachedDecoder.modelDescription.outputDescriptionsByName
            )
            if let cacheKOutput = cachedMeta.cacheKOutput {
                try self.validateOutputBackingFeature(
                    stageName: "cached decoder",
                    featureName: cacheKOutput,
                    descriptions: cachedDecoder.modelDescription.outputDescriptionsByName
                )
            }
            if let cacheVOutput = cachedMeta.cacheVOutput {
                try self.validateOutputBackingFeature(
                    stageName: "cached decoder",
                    featureName: cacheVOutput,
                    descriptions: cachedDecoder.modelDescription.outputDescriptionsByName
                )
            }
        }
    }

    private static func validateRequiredFeatureNames(
        stageName: String,
        availableInputs: [String: MLFeatureDescription],
        expectedInputs: [String],
        availableOutputs: [String: MLFeatureDescription],
        expectedOutputs: [String]
    ) throws {
        let missingInputs = expectedInputs.filter { availableInputs[$0] == nil }
        if missingInputs.isEmpty == false {
            throw CohereTranscribeAsrError.invalidModelContract(
                "\(stageName) is missing manifest-declared inputs: \(missingInputs.joined(separator: ", "))"
            )
        }

        let missingOutputs = expectedOutputs.filter { availableOutputs[$0] == nil }
        if missingOutputs.isEmpty == false {
            throw CohereTranscribeAsrError.invalidModelContract(
                "\(stageName) is missing manifest-declared outputs: \(missingOutputs.joined(separator: ", "))"
            )
        }
    }

    private static func validateMultiArrayShape(
        stageName: String,
        featureName: String,
        descriptions: [String: MLFeatureDescription],
        expectedShape: [Int]
    ) throws {
        guard let description = descriptions[featureName] else {
            throw CohereTranscribeAsrError.invalidModelContract(
                "\(stageName) feature '\(featureName)' is missing from the model description"
            )
        }
        guard let constraint = description.multiArrayConstraint else {
            throw CohereTranscribeAsrError.invalidModelContract(
                "\(stageName) feature '\(featureName)' is not a constrained MLMultiArray"
            )
        }

        let actualShape = constraint.shape.map(\.intValue)
        guard actualShape == expectedShape else {
            throw CohereTranscribeAsrError.invalidModelContract(
                "\(stageName) feature '\(featureName)' has shape \(actualShape), expected \(expectedShape)"
            )
        }
    }

    private static func validateOutputBackingFeature(
        stageName: String,
        featureName: String,
        descriptions: [String: MLFeatureDescription]
    ) throws {
        guard let description = descriptions[featureName] else {
            throw CohereTranscribeAsrError.invalidModelContract(
                "\(stageName) output '\(featureName)' is missing from the model description"
            )
        }
        guard description.multiArrayConstraint != nil else {
            throw CohereTranscribeAsrError.invalidModelContract(
                "\(stageName) output '\(featureName)' cannot be used with MLMultiArray output backing"
            )
        }
    }

}

extension CohereTranscribeAsrManifest {
    func validate() throws {
        guard sampleRate > 0, maxAudioSamples > 0, maxEncoderFrames > 0, maxFeatureFrames > 0,
              decoderMaxLen > promptIDs.count, !promptIDs.isEmpty, defaultMaxNewTokens > 0,
              idToToken.indices.contains(eosTokenID), idToToken[eosTokenID] == "<|endoftext|>",
              promptIDs.allSatisfy({ idToToken.indices.contains($0) }),
              frontend.inputs.count >= 2, frontend.outputs.count >= 2,
              encoder.inputs.count >= 2, encoder.outputs.count >= 2,
              decoder.inputs.count >= 4, !decoder.outputs.isEmpty else {
            throw CohereTranscribeAsrError.invalidModelContract("Invalid dimensions, prompt or EOS")
        }
        let packages = [frontend.package, encoder.package, decoder.package, crossKVProjector?.package, decoderCached?.package].compactMap { $0 }
        guard packages.allSatisfy({ !$0.contains("/") && $0.hasSuffix(".mlpackage") && !$0.hasPrefix(".") }) else {
            throw CohereTranscribeAsrError.invalidModelContract("Invalid package name")
        }
        if let cached = decoderCached {
            guard cached.numLayers > 0, cached.numHeads > 0, cached.headDim > 0 else {
                throw CohereTranscribeAsrError.invalidModelContract("Invalid decoder cache dimensions")
            }
        }
    }

    /// Szablon może zawierać ten sam język dwukrotnie; oba wystąpienia zamieniamy po słowniku.
    public func promptIDs(for language: String, template: [Int]? = nil) throws -> [Int] {
        guard let target = idToToken.firstIndex(of: "<|\(language)|>") else {
            throw CohereTranscribeAsrError.generationFailed("Unsupported language: \(language)")
        }
        var prompt = template ?? promptIDs
        var replaced = false
        for index in prompt.indices {
            guard idToToken.indices.contains(prompt[index]) else {
                throw CohereTranscribeAsrError.invalidModelContract("Invalid prompt token")
            }
            let token = idToToken[prompt[index]]
            let code = token.dropFirst(2).dropLast(2)
            if token.hasPrefix("<|"), token.hasSuffix("|>"), code.count == 2,
               code.allSatisfy({ $0.isASCII && $0.isLowercase }) {
                prompt[index] = target
                replaced = true
            }
        }
        guard replaced, !prompt.isEmpty, prompt.count < decoderMaxLen else {
            throw CohereTranscribeAsrError.invalidModelContract("Prompt has no language token or exceeds decoder capacity")
        }
        return prompt
    }
}

/// Stan EOS dotyczy tylko wygenerowanych tokenów danego wywołania, nie szablonu ani poprzedniego okna.
struct CohereDecodedTokens: Sendable {
    let tokens: [Int32]
    let reachedEOS: Bool
    init(tokens: [Int32], generatedFrom: Int, eosTokenID: Int) {
        self.tokens = tokens
        self.reachedEOS = tokens.dropFirst(generatedFrom).last.map { Int($0) == eosTokenID } ?? false
    }
}

public struct CohereTranscriptionResult: Sendable {
    public let text: String
    public let chunkEOS: [Bool]
    public var truncationCount: Int { chunkEOS.filter { !$0 }.count }
}
