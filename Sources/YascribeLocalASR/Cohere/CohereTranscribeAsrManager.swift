// Źródło: altic-dev/FluidAudio@386f7195670b77f2954c7ee143ec63fcb50b6c3b, Sources/FluidAudio/ASR/Cohere/CohereTranscribeAsrManager.swift
// Licencja: Apache-2.0 (LICENSES/Apache-2.0.txt).
// Zmodyfikowano w Yascribe: sekwencyjny aktor Swift 6, wynik EOS z wywołania, język, wstrzyknięta kompilacja, bez wejścia plikowego i prefetch.

import CoreML
import Foundation
import OSLog

@available(macOS 15, iOS 18, *)
public enum CohereTranscribeDecoderMode: String, Sendable {
    case cached
    case fullSequence
}

@available(macOS 15, iOS 18, *)
private struct CohereTranscribeEncoderStageOutput {
    let frontMs: Double
    let encMs: Double
    let crossKVms: Double
    let encoderHidden: MLMultiArray
    let encoderValid: Int
    let crossK: MLMultiArray?
    let crossV: MLMultiArray?
}

/// Jedyny właściciel modeli i buforów Core ML. Ładowanie i predykcja nie mają punktów zawieszenia,
/// więc żaden obiekt Core ML nie opuszcza aktora ani nie jest używany równolegle.
public actor CohereTranscribeAsrManager {
    private var models: CohereTranscribeAsrModels?
    private let logger = Logger(subsystem: "io.github.sharezz1.yascribe", category: "CohereTranscribeAsrManager")

    public init() {}

    private var decodingManifest: CohereTranscribeAsrManifest?
    private var tokenStep: (@Sendable (Int32, Int32) throws -> Int32)?
    /// Ten sam dekoder tokenów co Core ML, z przewidywaniem kolejnego tokenu bez MLModel.
    init(manifest: CohereTranscribeAsrManifest, tokenStep: @escaping @Sendable (Int32, Int32) throws -> Int32) {
        decodingManifest = manifest
        self.tokenStep = tokenStep
    }

    public func loadModels(
        from directory: URL,
        compiledDirectory: URL,
        fingerprint: String,
        computeConfiguration: CohereTranscribeComputeConfiguration = .yascribe,
        lock: ModelStoreLock
    ) throws {
        // shortcut: synchroniczny Core ML zajmuje wątek puli aktora; osobny executor przy pracy nad responsywnością.
        defer { withExtendedLifetime(lock) {} }
        try CohereModelCompilation.clean(root: compiledDirectory,
            key: CohereModelCompilation.key(fingerprint: fingerprint, configuration: computeConfiguration), lock: lock)
        self.models = try CohereTranscribeAsrModels.load(
            from: directory, compiledDirectory: compiledDirectory,
            fingerprint: fingerprint, computeConfiguration: computeConfiguration
        )
    }

    public func unload() { models = nil }

    public func transcribe(
        audioSamples: [Float],
        decoderMode: CohereTranscribeDecoderMode = .cached,
        maxNewTokens: Int? = nil,
        language: String,
        promptIDs: [Int]? = nil
    ) throws -> CohereTranscriptionResult {
        guard let manifest = models?.manifest ?? decodingManifest else {
            throw CohereTranscribeAsrError.generationFailed("Models not loaded")
        }
        guard audioSamples.isEmpty == false else { return .init(text: "", chunkEOS: []) }
        let selectedPrompt = try manifest.promptIDs(for: language, template: promptIDs)

        let chunks = CohereAudioChunkPlanner.makeChunks(
            audioSamples: audioSamples,
            sampleRate: manifest.sampleRate,
            maxAudioSamples: manifest.maxAudioSamples,
            boundarySearchSeconds: self.boundarySearchSeconds(for: manifest)
        )
        let startedAt = Date()
        let audioSeconds = Double(audioSamples.count) / Double(manifest.sampleRate)
        self.logger.info(
            "Cohere transcribe start [samples=\(audioSamples.count), audioSeconds=\(audioSeconds, format: .fixed(precision: 2)), decoderMode=\(decoderMode.rawValue, privacy: .public), chunks=\(chunks.count), chunking=energy-boundary]"
        )

        var chunkTexts: [String] = []
        var chunkEOS: [Bool] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let decoded: CohereDecodedTokens
            if let tokenStep {
                decoded = try Self.decodeCachedTokens(manifest: manifest, prompt: selectedPrompt,
                    maxTokens: maxNewTokens ?? manifest.defaultMaxNewTokens, nextToken: tokenStep)
            } else if let models {
                let inputs = try buildChunkInputs(chunk: chunk, audioSamples: audioSamples, manifest: manifest)
                decoded = try runPipeline(frontInputs: inputs, models: models, decoderMode: decoderMode,
                                          maxNewTokens: maxNewTokens, promptIDs: selectedPrompt)
            } else { throw CohereTranscribeAsrError.generationFailed("Models not loaded") }
            chunkTexts.append(decodeTokens(decoded.tokens, manifest: manifest))
            chunkEOS.append(decoded.reachedEOS)
        }

        let merged = CohereAudioChunkPlanner.joinChunkTexts(chunkTexts)
        let elapsed = Date().timeIntervalSince(startedAt)
        let rtf = audioSeconds > 0 ? elapsed / audioSeconds : 0
        self.logger.info(
            "Cohere transcribe finished in \(elapsed, format: .fixed(precision: 2))s [audioSeconds=\(audioSeconds, format: .fixed(precision: 2)), rtf=\(rtf, format: .fixed(precision: 2))x, chars=\(merged.count)]"
        )
        return .init(text: merged, chunkEOS: chunkEOS)
    }

    private func runPipeline(
        frontInputs: MLDictionaryFeatureProvider,
        models: CohereTranscribeAsrModels,
        decoderMode: CohereTranscribeDecoderMode,
        maxNewTokens: Int?,
        promptIDs: [Int]?
    ) throws -> CohereDecodedTokens {
        switch decoderMode {
        case .fullSequence:
            return try self.runFullSequencePipeline(
                frontInputs: frontInputs,
                models: models,
                maxNewTokens: maxNewTokens,
                promptIDs: promptIDs
            )
        case .cached:
            guard self.canRunCachedDecoder(with: models) else {
                self.logger.warning("Cached decoder metadata missing; falling back to full-sequence decode.")
                return try self.runFullSequencePipeline(
                    frontInputs: frontInputs,
                    models: models,
                    maxNewTokens: maxNewTokens,
                    promptIDs: promptIDs
                )
            }
            return try self.runCachedPipeline(
                frontInputs: frontInputs,
                models: models,
                maxNewTokens: maxNewTokens,
                promptIDs: promptIDs
            )
        }
    }

    private func canRunCachedDecoder(with models: CohereTranscribeAsrModels) -> Bool {
        guard let metadata = models.manifest.decoderCached, models.cachedDecoder != nil else {
            return false
        }
        return metadata.cacheKOutput != nil && metadata.cacheVOutput != nil
    }

    private func buildChunkInputs(
        chunk: CohereAudioChunkPlanner.Chunk,
        audioSamples: [Float],
        manifest: CohereTranscribeAsrManifest
    ) throws -> MLDictionaryFeatureProvider {
        var segment = Array(audioSamples[chunk.range])
        let rawLength = segment.count

        if segment.count < manifest.maxAudioSamples {
            segment += Array(repeating: 0, count: manifest.maxAudioSamples - segment.count)
        }

        self.applyPreemphasis(
            &segment,
            rawLength: rawLength,
            coefficient: manifest.preemph ?? 0.97
        )

        let audioArray = try self.makeFloatArray(
            shape: [1, manifest.maxAudioSamples],
            values: segment
        )
        let audioLengthArray = try self.makeIntArray(shape: [1], values: [Int32(rawLength)])

        return try MLDictionaryFeatureProvider(dictionary: [
            manifest.frontend.inputs[0]: MLFeatureValue(multiArray: audioArray),
            manifest.frontend.inputs[1]: MLFeatureValue(multiArray: audioLengthArray),
        ])
    }

    private func runEncoderStage(
        frontInputs: MLDictionaryFeatureProvider,
        models: CohereTranscribeAsrModels
    ) throws -> CohereTranscribeEncoderStageOutput {
        let manifest = models.manifest
        let frontStartedAt = Date()
        let frontOut = try models.frontend.prediction(from: frontInputs)
        let frontMs = Date().timeIntervalSince(frontStartedAt) * 1000
        guard
            let inputFeatures = frontOut.featureValue(for: manifest.frontend.outputs[0])?.multiArrayValue,
            let featureLength = frontOut.featureValue(for: manifest.frontend.outputs[1])?.multiArrayValue
        else {
            throw CohereTranscribeAsrError.invalidOutput("Frontend outputs missing")
        }

        let encoderInputs = try MLDictionaryFeatureProvider(dictionary: [
            manifest.encoder.inputs[0]: MLFeatureValue(multiArray: inputFeatures),
            manifest.encoder.inputs[1]: MLFeatureValue(multiArray: featureLength),
        ])
        let encoderStartedAt = Date()
        let encoderOut = try models.encoder.prediction(from: encoderInputs)
        let encoderMs = Date().timeIntervalSince(encoderStartedAt) * 1000
        guard
            let encoderHidden = encoderOut.featureValue(for: manifest.encoder.outputs[0])?.multiArrayValue,
            let encoderLengthOut = encoderOut.featureValue(for: manifest.encoder.outputs[1])?.multiArrayValue
        else {
            throw CohereTranscribeAsrError.invalidOutput("Encoder outputs missing")
        }

        let encoderHiddenContiguous = try self.toContiguous(encoderHidden)
        let encoderValidRaw = Int(encoderLengthOut[0].doubleValue.rounded())
        let encoderValid = max(1, min(manifest.maxEncoderFrames, encoderValidRaw))

        var crossK: MLMultiArray?
        var crossV: MLMultiArray?
        var crossKVms: Double = 0
        if
            let crossKVMeta = manifest.crossKVProjector,
            let crossKVProjector = models.crossKVProjector
        {
            let inputName = crossKVMeta.inputs.first ?? "encoder_hidden_states"
            let crossKVStartedAt = Date()
            let crossKVInputs = try MLDictionaryFeatureProvider(dictionary: [
                inputName: MLFeatureValue(multiArray: encoderHiddenContiguous)
            ])
            let crossKVOutput = try crossKVProjector.prediction(from: crossKVInputs)
            crossKVms = Date().timeIntervalSince(crossKVStartedAt) * 1000
            if let crossKOutput = crossKVMeta.crossKOutput ?? crossKVMeta.outputs.first {
                crossK = crossKVOutput.featureValue(for: crossKOutput)?.multiArrayValue
            }
            if let crossVOutput = crossKVMeta.crossVOutput ?? crossKVMeta.outputs.dropFirst().first {
                crossV = crossKVOutput.featureValue(for: crossVOutput)?.multiArrayValue
            }
        }

        return CohereTranscribeEncoderStageOutput(
            frontMs: frontMs,
            encMs: encoderMs,
            crossKVms: crossKVms,
            encoderHidden: encoderHiddenContiguous,
            encoderValid: encoderValid,
            crossK: crossK,
            crossV: crossV
        )
    }

    private func runFullSequencePipeline(
        frontInputs: MLDictionaryFeatureProvider,
        models: CohereTranscribeAsrModels,
        maxNewTokens: Int?,
        promptIDs: [Int]?
    ) throws -> CohereDecodedTokens {
        let manifest = models.manifest
        let encoderStage = try self.runEncoderStage(frontInputs: frontInputs, models: models)
        let encoderHidden = encoderStage.encoderHidden
        let encoderValid = encoderStage.encoderValid
        let generationPromptIDs = promptIDs ?? manifest.promptIDs

        let vocabSize = manifest.idToToken.count
        let totalMaxNewTokens = maxNewTokens ?? manifest.defaultMaxNewTokens
        guard totalMaxNewTokens > 0 else { throw CohereTranscribeAsrError.generationFailed("Token limit must be positive") }
        let padToken = Int32(manifest.padTokenID ?? 0)
        var inputIDs = Array(repeating: padToken, count: manifest.decoderMaxLen)
        var attentionMask = Array(repeating: Int32(0), count: manifest.decoderMaxLen)

        for (index, tokenID) in generationPromptIDs.enumerated() where index < manifest.decoderMaxLen {
            inputIDs[index] = Int32(tokenID)
            attentionMask[index] = 1
        }

        let crossAttentionMask = try self.makeCrossAttentionMask(
            validLength: encoderValid,
            totalLength: manifest.maxEncoderFrames,
            useFloat16: manifest.isFp16
        )

        var currentIndex = generationPromptIDs.count - 1
        for _ in 0..<totalMaxNewTokens {
            if currentIndex + 1 >= manifest.decoderMaxLen {
                break
            }

            let idsArray = try self.makeIntArray(shape: [1, manifest.decoderMaxLen], values: inputIDs)
            let maskArray = try self.makeIntArray(shape: [1, manifest.decoderMaxLen], values: attentionMask)
            let decoderInputs = try MLDictionaryFeatureProvider(dictionary: [
                manifest.decoder.inputs[0]: MLFeatureValue(multiArray: encoderHidden),
                manifest.decoder.inputs[1]: MLFeatureValue(multiArray: idsArray),
                manifest.decoder.inputs[2]: MLFeatureValue(multiArray: maskArray),
                manifest.decoder.inputs[3]: MLFeatureValue(multiArray: crossAttentionMask),
            ])

            let decoderOut = try models.decoder.prediction(from: decoderInputs)
            guard let logits = decoderOut.featureValue(for: manifest.decoder.outputs[0])?.multiArrayValue else {
                throw CohereTranscribeAsrError.invalidOutput("Decoder logits missing")
            }

            let next = self.argmaxSlice(logits, tokenIndex: currentIndex, vocabSize: vocabSize)
            currentIndex += 1
            inputIDs[currentIndex] = next
            attentionMask[currentIndex] = 1

            if Int(next) == manifest.eosTokenID {
                break
            }
        }

        let result = Array(inputIDs[0...currentIndex])
        return .init(tokens: result, generatedFrom: generationPromptIDs.count, eosTokenID: manifest.eosTokenID)
    }

    private func runCachedPipeline(
        frontInputs: MLDictionaryFeatureProvider,
        models: CohereTranscribeAsrModels,
        maxNewTokens: Int?,
        promptIDs: [Int]?
    ) throws -> CohereDecodedTokens {
        let encoderStage = try self.runEncoderStage(frontInputs: frontInputs, models: models)
        return try self.runCachedDecoderOnly(
            encoderStage: encoderStage,
            models: models,
            maxNewTokens: maxNewTokens,
            promptIDs: promptIDs
        )
    }

    private func runCachedDecoderOnly(
        encoderStage: CohereTranscribeEncoderStageOutput,
        models: CohereTranscribeAsrModels,
        maxNewTokens: Int?,
        promptIDs: [Int]?
    ) throws -> CohereDecodedTokens {
        guard
            let cachedMetadata = models.manifest.decoderCached,
            let cachedDecoder = models.cachedDecoder,
            let cacheKOutput = cachedMetadata.cacheKOutput,
            let cacheVOutput = cachedMetadata.cacheVOutput
        else {
            throw CohereTranscribeAsrError.generationFailed("Cached decoder is unavailable")
        }

        let manifest = models.manifest
        let generationPromptIDs = promptIDs ?? manifest.promptIDs
        let maxTokens = maxNewTokens ?? manifest.defaultMaxNewTokens
        guard maxTokens > 0 else { throw CohereTranscribeAsrError.generationFailed("Token limit must be positive") }
        let cacheShape = [cachedMetadata.numLayers, cachedMetadata.numHeads, manifest.decoderMaxLen, cachedMetadata.headDim]
            .map(NSNumber.init)
        let cacheType: MLMultiArrayDataType = manifest.isFp16 ? .float16 : .float32
        let cacheBytesPerElement = manifest.isFp16 ? 2 : 4
        let cacheElementCount = cachedMetadata.numLayers * cachedMetadata.numHeads * manifest.decoderMaxLen * cachedMetadata.headDim

        let vocabSize = manifest.idToToken.count
        let logitsShape = [1, vocabSize].map(NSNumber.init)
        let logitsBuffer = try MLMultiArray(shape: logitsShape, dataType: cacheType)

        let cacheKA = try MLMultiArray(shape: cacheShape, dataType: cacheType)
        let cacheVA = try MLMultiArray(shape: cacheShape, dataType: cacheType)
        let cacheKB = try MLMultiArray(shape: cacheShape, dataType: cacheType)
        let cacheVB = try MLMultiArray(shape: cacheShape, dataType: cacheType)
        memset(cacheKA.dataPointer, 0, cacheElementCount * cacheBytesPerElement)
        memset(cacheVA.dataPointer, 0, cacheElementCount * cacheBytesPerElement)

        let crossAttentionMask = try self.makeCrossAttentionMask(
            validLength: encoderStage.encoderValid,
            totalLength: manifest.maxEncoderFrames,
            useFloat16: manifest.isFp16
        )

        let inputIDArray = try MLMultiArray(shape: [1, 1], dataType: .int32)
        let stepArray = try MLMultiArray(shape: [1], dataType: .int32)
        let inputIDName = self.cachedDecoderInputName(metadata: cachedMetadata, preferred: "input_id", fallbackIndex: 1)
        let cacheKInputName = self.cachedDecoderInputName(metadata: cachedMetadata, preferred: "cache_k", fallbackIndex: 2)
        let cacheVInputName = self.cachedDecoderInputName(metadata: cachedMetadata, preferred: "cache_v", fallbackIndex: 3)
        let stepInputName = self.cachedDecoderInputName(metadata: cachedMetadata, preferred: "step", fallbackIndex: 4)
        let crossAttentionMaskName = self.cachedDecoderInputName(metadata: cachedMetadata, preferred: "cross_attention_mask", fallbackIndex: 5)

        let featureProvider = self.makeCachedDecoderFeatureProvider(
            metadata: cachedMetadata,
            encoderStage: encoderStage,
            inputIDArray: inputIDArray,
            cacheKA: cacheKA,
            cacheVA: cacheVA,
            stepArray: stepArray,
            crossAttentionMask: crossAttentionMask
        )

        let optionsA = MLPredictionOptions()
        optionsA.outputBackings = [
            cachedMetadata.logitsOutput: logitsBuffer,
            cacheKOutput: cacheKB,
            cacheVOutput: cacheVB,
        ]
        let optionsB = MLPredictionOptions()
        optionsB.outputBackings = [
            cachedMetadata.logitsOutput: logitsBuffer,
            cacheKOutput: cacheKA,
            cacheVOutput: cacheVA,
        ]

        var useA = true

        func runStep(tokenID: Int32, stepIndex: Int32) throws -> MLMultiArray {
            inputIDArray[0] = NSNumber(value: tokenID)
            stepArray[0] = NSNumber(value: stepIndex)

            let inputCacheK = useA ? cacheKA : cacheKB
            let inputCacheV = useA ? cacheVA : cacheVB
            featureProvider.update(inputIDName, inputIDArray)
            featureProvider.update(cacheKInputName, inputCacheK)
            featureProvider.update(cacheVInputName, inputCacheV)
            featureProvider.update(stepInputName, stepArray)
            featureProvider.update(crossAttentionMaskName, crossAttentionMask)

            let options = useA ? optionsA : optionsB
            _ = try cachedDecoder.prediction(from: featureProvider, options: options)
            useA.toggle()
            return logitsBuffer
        }

        return try Self.decodeCachedTokens(manifest: manifest, prompt: generationPromptIDs, maxTokens: maxTokens) { token, index in
            self.argmax1D(try runStep(tokenID: token, stepIndex: index))
        }
    }

    static func decodeCachedTokens(manifest: CohereTranscribeAsrManifest, prompt: [Int], maxTokens: Int,
                                   nextToken: (Int32, Int32) throws -> Int32) throws -> CohereDecodedTokens {
        guard maxTokens > 0 else { throw CohereTranscribeAsrError.generationFailed("Token limit must be positive") }
        var generated = prompt.map(Int32.init)
        var next: Int32?
        for (index, token) in generated.enumerated() {
            next = try nextToken(token, Int32(index))
        }
        var currentIndex = prompt.count
        if let next {
            generated.append(next)
            if Int(next) == manifest.eosTokenID {
                return .init(tokens: generated, generatedFrom: prompt.count, eosTokenID: manifest.eosTokenID)
            }
        }
        for _ in 1..<maxTokens {
            if currentIndex >= manifest.decoderMaxLen { break }
            let token = try nextToken(generated.last ?? 0, Int32(currentIndex))
            generated.append(token)
            currentIndex += 1
            if Int(token) == manifest.eosTokenID { break }
        }
        return .init(tokens: generated, generatedFrom: prompt.count, eosTokenID: manifest.eosTokenID)
    }

    private func makeCachedDecoderFeatureProvider(
        metadata: CohereTranscribeCachedDecoderMeta,
        encoderStage: CohereTranscribeEncoderStageOutput,
        inputIDArray: MLMultiArray,
        cacheKA: MLMultiArray,
        cacheVA: MLMultiArray,
        stepArray: MLMultiArray,
        crossAttentionMask: MLMultiArray
    ) -> FastFeatureProvider {
        let inputIDName = self.cachedDecoderInputName(metadata: metadata, preferred: "input_id", fallbackIndex: 1)
        let cacheKInputName = self.cachedDecoderInputName(metadata: metadata, preferred: "cache_k", fallbackIndex: 2)
        let cacheVInputName = self.cachedDecoderInputName(metadata: metadata, preferred: "cache_v", fallbackIndex: 3)
        let stepInputName = self.cachedDecoderInputName(metadata: metadata, preferred: "step", fallbackIndex: 4)
        let crossAttentionMaskName = self.cachedDecoderInputName(metadata: metadata, preferred: "cross_attention_mask", fallbackIndex: 5)

        if let crossK = encoderStage.crossK, let crossV = encoderStage.crossV {
            let crossKName = self.cachedDecoderInputName(metadata: metadata, preferred: "cross_k", fallbackIndex: 0)
            let crossVName = self.cachedDecoderInputName(metadata: metadata, preferred: "cross_v", fallbackIndex: 1)
            return FastFeatureProvider([
                (crossKName, crossK),
                (crossVName, crossV),
                (inputIDName, inputIDArray),
                (cacheKInputName, cacheKA),
                (cacheVInputName, cacheVA),
                (stepInputName, stepArray),
                (crossAttentionMaskName, crossAttentionMask),
            ])
        }

        let encoderHiddenName = self.cachedDecoderInputName(metadata: metadata, preferred: "encoder_hidden_states", fallbackIndex: 0)
        return FastFeatureProvider([
            (encoderHiddenName, encoderStage.encoderHidden),
            (inputIDName, inputIDArray),
            (cacheKInputName, cacheKA),
            (cacheVInputName, cacheVA),
            (stepInputName, stepArray),
            (crossAttentionMaskName, crossAttentionMask),
        ])
    }

    private func cachedDecoderInputName(
        metadata: CohereTranscribeCachedDecoderMeta,
        preferred: String,
        fallbackIndex: Int
    ) -> String {
        if metadata.inputs.contains(preferred) {
            return preferred
        }
        if metadata.inputs.indices.contains(fallbackIndex) {
            return metadata.inputs[fallbackIndex]
        }
        return preferred
    }

    private func decodeTokens(
        _ tokenIDs: [Int32],
        manifest: CohereTranscribeAsrManifest
    ) -> String {
        var pieces: [String] = []
        pieces.reserveCapacity(tokenIDs.count)

        for tokenID in tokenIDs {
            let tokenIndex = Int(tokenID)
            if tokenIndex == manifest.eosTokenID {
                break
            }
            if let padTokenID = manifest.padTokenID, tokenIndex == padTokenID {
                continue
            }
            guard manifest.idToToken.indices.contains(tokenIndex) else { continue }

            let piece = manifest.idToToken[tokenIndex]
            if piece.hasPrefix("<"), piece.hasSuffix(">") {
                continue
            }
            pieces.append(piece)
        }

        return pieces.joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boundarySearchSeconds(for manifest: CohereTranscribeAsrManifest) -> Double {
        if let overlapSamples = manifest.overlapSamples, overlapSamples > 0 {
            return Double(overlapSamples) / Double(manifest.sampleRate)
        }
        if let overlapSeconds = manifest.overlapSeconds, overlapSeconds > 0 {
            return overlapSeconds
        }
        return CohereAudioChunkPlanner.defaultBoundarySearchSeconds
    }

    private func applyPreemphasis(
        _ audio: inout [Float],
        rawLength: Int,
        coefficient: Float
    ) {
        let count = min(rawLength, audio.count)
        guard count > 0 else { return }

        if count > 1 {
            for index in stride(from: count - 1, through: 1, by: -1) {
                audio[index] = audio[index] - coefficient * audio[index - 1]
            }
        }

        for index in count..<audio.count {
            audio[index] = 0
        }
    }

    private func makeCrossAttentionMask(
        validLength: Int,
        totalLength: Int,
        useFloat16: Bool
    ) throws -> MLMultiArray {
        let limitedValidLength = max(0, min(validLength, totalLength))
        let invalidValue: Float = -1e9
        var values = Array(repeating: invalidValue, count: totalLength)
        if limitedValidLength > 0 {
            for index in 0..<limitedValidLength {
                values[index] = 0
            }
        }

        if useFloat16 {
            return try self.makeFloat16Array(shape: [1, 1, 1, totalLength], values: values)
        }
        return try self.makeFloatArray(shape: [1, 1, 1, totalLength], values: values)
    }

    private func argmax1D(_ array: MLMultiArray) -> Int32 {
        let count = array.count
        if array.dataType == .float16 {
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: count)
            var bestIndex = 0
            var bestValue = pointer[0]
            for index in 1..<count {
                let current = pointer[index]
                if self.float32(fromFloat16BitPattern: current) > self.float32(fromFloat16BitPattern: bestValue) {
                    bestValue = current
                    bestIndex = index
                }
            }
            return Int32(bestIndex)
        }

        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        var bestIndex = 0
        var bestValue = pointer[0]
        for index in 1..<count {
            if pointer[index] > bestValue {
                bestValue = pointer[index]
                bestIndex = index
            }
        }
        return Int32(bestIndex)
    }

    private func argmaxSlice(
        _ array: MLMultiArray,
        tokenIndex: Int,
        vocabSize: Int
    ) -> Int32 {
        let strideT = array.strides[1].intValue
        let strideV = array.strides[2].intValue
        let base = tokenIndex * strideT
        var bestValue = array[base].doubleValue
        var bestIndex = 0

        for index in 1..<vocabSize {
            let value = array[base + index * strideV].doubleValue
            if value > bestValue {
                bestValue = value
                bestIndex = index
            }
        }

        return Int32(bestIndex)
    }

    private func toContiguous(_ array: MLMultiArray) throws -> MLMultiArray {
        let shape = array.shape.map(\.intValue)
        let totalCount = shape.reduce(1, *)
        let strides = array.strides.map(\.intValue)

        var expectedStride = 1
        var isContiguous = true
        for index in stride(from: shape.count - 1, through: 0, by: -1) {
            if strides[index] != expectedStride {
                isContiguous = false
                break
            }
            expectedStride *= shape[index]
        }

        if isContiguous {
            return array
        }

        let contiguous = try MLMultiArray(shape: array.shape, dataType: array.dataType)
        if array.dataType == .float16 {
            let source = array.dataPointer.bindMemory(to: UInt16.self, capacity: totalCount)
            let destination = contiguous.dataPointer.bindMemory(to: UInt16.self, capacity: totalCount)
            if shape.count == 3 {
                var outputIndex = 0
                for batch in 0..<shape[0] {
                    for time in 0..<shape[1] {
                        let base = batch * strides[0] + time * strides[1]
                        if strides[2] == 1 {
                            memcpy(destination + outputIndex, source + base, shape[2] * MemoryLayout<UInt16>.size)
                            outputIndex += shape[2]
                        } else {
                            for hidden in 0..<shape[2] {
                                destination[outputIndex] = source[base + hidden * strides[2]]
                                outputIndex += 1
                            }
                        }
                    }
                }
            }
        } else {
            let source = array.dataPointer.bindMemory(to: Float.self, capacity: totalCount)
            let destination = contiguous.dataPointer.bindMemory(to: Float.self, capacity: totalCount)
            if shape.count == 3 {
                var outputIndex = 0
                for batch in 0..<shape[0] {
                    for time in 0..<shape[1] {
                        let base = batch * strides[0] + time * strides[1]
                        if strides[2] == 1 {
                            memcpy(destination + outputIndex, source + base, shape[2] * MemoryLayout<Float>.size)
                            outputIndex += shape[2]
                        } else {
                            for hidden in 0..<shape[2] {
                                destination[outputIndex] = source[base + hidden * strides[2]]
                                outputIndex += 1
                            }
                        }
                    }
                }
            }
        }
        return contiguous
    }

    private func makeFloatArray(shape: [Int], values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .float32)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: values.count)
        _ = values.withUnsafeBufferPointer { buffer in
            memcpy(pointer, buffer.baseAddress, values.count * MemoryLayout<Float>.stride)
        }
        return array
    }

    private func makeFloat16Array(shape: [Int], values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .float16)
        let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: values.count)
        for index in 0..<values.count {
            pointer[index] = self.float16BitPattern(from: values[index])
        }
        return array
    }

    private func float32(fromFloat16BitPattern bitPattern: UInt16) -> Float {
        let sign = UInt32(bitPattern & 0x8000) << 16
        let exponent = Int((bitPattern >> 10) & 0x1F)
        let fraction = UInt32(bitPattern & 0x03FF)

        let floatBits: UInt32
        switch exponent {
        case 0:
            if fraction == 0 {
                floatBits = sign
            } else {
                var mantissa = fraction
                var adjustedExponent = -14
                while (mantissa & 0x0400) == 0 {
                    mantissa <<= 1
                    adjustedExponent -= 1
                }
                mantissa &= 0x03FF
                let exponentBits = UInt32(adjustedExponent + 127) << 23
                let mantissaBits = mantissa << 13
                floatBits = sign | exponentBits | mantissaBits
            }
        case 0x1F:
            floatBits = sign | 0x7F80_0000 | (fraction << 13)
        default:
            let exponentBits = UInt32(exponent - 15 + 127) << 23
            let mantissaBits = fraction << 13
            floatBits = sign | exponentBits | mantissaBits
        }

        return Float(bitPattern: floatBits)
    }

    private func float16BitPattern(from value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        var exponent = Int((bits >> 23) & 0xFF) - 127 + 15
        var mantissa = bits & 0x007F_FFFF

        if exponent <= 0 {
            if exponent < -10 {
                return sign
            }
            mantissa |= 0x0080_0000
            let shift = UInt32(14 - exponent)
            let rounded = (mantissa >> shift) + ((mantissa >> (shift - 1)) & 1)
            return sign | UInt16(rounded)
        }

        if exponent >= 0x1F {
            return sign | 0x7C00
        }

        mantissa = mantissa + 0x0000_1000
        if (mantissa & 0x0080_0000) != 0 {
            mantissa = 0
            exponent += 1
            if exponent >= 0x1F {
                return sign | 0x7C00
            }
        }

        return sign | UInt16(exponent << 10) | UInt16(mantissa >> 13)
    }

    private func makeIntArray(shape: [Int], values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        _ = values.withUnsafeBufferPointer { buffer in
            memcpy(pointer, buffer.baseAddress, values.count * MemoryLayout<Int32>.stride)
        }
        return array
    }
}

@available(macOS 15, iOS 18, *)
private final class FastFeatureProvider: MLFeatureProvider {
    private var values: [String: MLFeatureValue]
    let featureNames: Set<String>

    init(_ pairs: [(String, MLMultiArray)]) {
        var values = [String: MLFeatureValue]()
        values.reserveCapacity(pairs.count)
        var names = Set<String>()
        names.reserveCapacity(pairs.count)

        for (name, array) in pairs {
            values[name] = MLFeatureValue(multiArray: array)
            names.insert(name)
        }

        self.values = values
        self.featureNames = names
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        self.values[featureName]
    }

    func update(_ name: String, _ array: MLMultiArray) {
        self.values[name] = MLFeatureValue(multiArray: array)
    }
}
