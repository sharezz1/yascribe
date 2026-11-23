@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// Odcisk głosu mówców z ich odcinków na torze `system` (TASK-117): model mówców (`embedSpans`, domyślny) albo CAM++ v2 (beta).
/// Wynik żyje w pamięci; zapis do profilu (tylko po zgodzie) należy do wołającego. Bez sieci: modele tylko z magazynów Yascribe.
public actor VoiceEmbedder {
    typealias Work = @Sendable (URL, [String: [ClosedRange<Double>]], VoiceModel) async throws -> [String: [Float]]

    private let diarizerStore: DiarizerModelStore
    private let campPlusStore: DiarizerModelStore
    private let work: Work?

    public init(diarizerStore: DiarizerModelStore, campPlusStore: DiarizerModelStore) {
        self.init(diarizerStore: diarizerStore, campPlusStore: campPlusStore, work: nil)
    }

    /// Testy: `work` zastępuje liczenie, ale nadal czeka w kolejce diaryzacji.
    init(diarizerStore: DiarizerModelStore, campPlusStore: DiarizerModelStore, work: Work?) {
        self.diarizerStore = diarizerStore
        self.campPlusStore = campPlusStore
        self.work = work
    }

    public func store(for model: VoiceModel) -> DiarizerModelStore { model == .diarizer ? diarizerStore : campPlusStore }

    /// Klucz mówcy → znormalizowany odcisk (średnia odcinków ważona długością). Mówca bez odcinka w nagraniu nie trafia do wyniku.
    /// Ta sama kolejka co diaryzacja: jeden model CoreML naraz.
    public func embed(systemTrack: URL, speakers: [String: [ClosedRange<Double>]], model: VoiceModel) async throws -> [String: [Float]] {
        let store = store(for: model)
        return try await DiarizationQueue.shared.serialized { [work] in
            if let work { return try await work(systemTrack, speakers, model) }
            return try await Self.compute(systemTrack: systemTrack, speakers: speakers, model: model, store: store)
        }
    }

    private static func compute(systemTrack: URL, speakers: [String: [ClosedRange<Double>]], model: VoiceModel,
                                store: DiarizerModelStore) async throws -> [String: [Float]] {
        guard store.status() == .ready else {
            throw DiarizerModelStoreError(message: "The voice model is not downloaded. Download it in Settings.",
                                          displayMessage: String(localized: "The voice model is not downloaded. Download it in Settings."))
        }
        let lock = try store.lockForUse()
        defer { withExtendedLifetime(lock) {} }
        let rate = 16_000.0
        let seconds = (try? AVAudioFile(forReading: systemTrack)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        let free = (try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard SpeakerDiarizer.hasRoomForPCM(trackSeconds: seconds, freeBytes: free) else {
            throw DiarizerModelStoreError(message: "Not enough free disk space to detect speakers in this recording.",
                                          displayMessage: String(localized: "Not enough free disk space to detect speakers in this recording."))
        }
        let source = try SpeakerDiarizer.makeSource(from: systemTrack, sampleRate: Int(rate))
        defer { source.cleanup() }
        let duration = Double(source.sampleCount) / rate
        let flat = speakers.sorted { $0.key < $1.key }.flatMap { key, spans in
            spans.compactMap { span -> (key: String, span: ClosedRange<Double>)? in
                let end = min(span.upperBound, duration)
                return end - span.lowerBound >= 0.5 ? (key, span.lowerBound...end) : nil
            }
        }
        guard !flat.isEmpty else { return [:] }
        let vectors: [[Float]]
        switch model {
        case .diarizer:
            let manager = OfflineDiarizerManager(config: SpeakerDiarizer.config(for: .medium))
            manager.initialize(models: try store.loadModels())
            vectors = try await manager.embedSpans(audioSource: source, spans: flat.map { $0.span.lowerBound..<$0.span.upperBound })
        case .campPlus:
            let embedder = CampPlusEmbedder(models: try CampPlusModels.load(from: store.directory))
            var out: [[Float]] = []
            for item in flat {
                try Task.checkCancellation()
                let offset = Int(item.span.lowerBound * rate)
                let count = min(Int((item.span.upperBound - item.span.lowerBound) * rate), source.sampleCount - offset)
                var samples = [Float](repeating: 0, count: max(count, 0))
                try samples.withUnsafeMutableBufferPointer { buffer in
                    guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
                    try source.copySamples(into: base, offset: offset, count: buffer.count)
                }
                out.append(try await embedder.embed(audio: samples))
            }
            vectors = out
        }
        var grouped: [String: (vectors: [[Float]], weights: [Double])] = [:]
        for (item, vector) in zip(flat, vectors) {
            grouped[item.key, default: ([], [])].vectors.append(vector)
            grouped[item.key, default: ([], [])].weights.append(item.span.upperBound - item.span.lowerBound)
        }
        return grouped.compactMapValues { combine($0.vectors, weights: $0.weights) }
    }

    /// Średnia znormalizowanych wektorów ważona długością odcinków, znów znormalizowana; `nil` = brak wektorów albo różne długości.
    static func combine(_ vectors: [[Float]], weights: [Double]) -> [Float]? {
        guard let dimension = vectors.first?.count, dimension > 0, vectors.allSatisfy({ $0.count == dimension }) else { return nil }
        var sum = [Float](repeating: 0, count: dimension)
        for (vector, weight) in zip(vectors, weights) {
            let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            guard norm > 0 else { continue }
            for i in sum.indices { sum[i] += vector[i] / norm * Float(weight) }
        }
        let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? sum.map { $0 / norm } : nil
    }
}
