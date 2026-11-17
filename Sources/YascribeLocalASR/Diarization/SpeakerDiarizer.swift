@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import YascribeProviders

/// Diaryzacja toru `system` (spec D1, D2, §8 R04, R06): źródło dyskowe FluidAudio + `prepare`/`cluster` na modelach z
/// `DiarizerModelStore`. Wynik w czasie TORU; przeliczenie na czas sesji i format pliku należą do wołającego (T3).
public actor SpeakerDiarizer {
    typealias Work = @Sendable (URL) async throws -> [(speaker: String, start: Double, end: Double)]

    /// Jedna diaryzacja naraz w procesie (R04): kolejka wspólna dla wszystkich instancji, obejmuje cały przebieg.
    private static let queue = DiarizationQueue()

    private let store: DiarizerModelStore
    private let work: Work?
    private var models: OfflineDiarizerModels?

    public init(store: DiarizerModelStore = DiarizerModelStore()) { self.init(store: store, work: nil) }

    /// Testy: `work` zastępuje właściwy przebieg, ale nadal czeka w kolejce.
    init(store: DiarizerModelStore, work: Work?) {
        self.store = store
        self.work = work
    }

    public func run(systemTrack: URL, sensitivity: SpeakerSensitivity,
                    progress: (@Sendable (Double) -> Void)?) async throws -> [(speaker: String, start: Double, end: Double)] {
        try await Self.queue.serialized { [work] in
            if let work { return try await work(systemTrack) }
            return try await self.diarizeTrack(systemTrack, sensitivity: sensitivity, progress: progress)
        }
    }

    private func diarizeTrack(_ systemTrack: URL, sensitivity: SpeakerSensitivity,
                              progress: (@Sendable (Double) -> Void)?) async throws -> [(speaker: String, start: Double, end: Double)] {
        // Sprawdzenie przed blokadą: brak modelu nie tworzy katalogu magazynu.
        guard store.status() == .ready else {
            throw DiarizerModelStoreError(message: "The speaker model is not downloaded. Download it in Settings.")
        }
        let lock = try store.lockForUse()
        defer { withExtendedLifetime(lock) {} }
        let file = try AVAudioFile(forReading: systemTrack)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        let temporary = FileManager.default.temporaryDirectory
        let free = (try? temporary.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard Self.hasRoomForPCM(trackSeconds: seconds, freeBytes: free) else {
            throw DiarizerModelStoreError(message: "Not enough free disk space to detect speakers in this recording.")
        }
        let models = try self.models ?? store.loadModels()
        self.models = models
        let config = Self.config(for: sensitivity)
        let source = try Self.makeSource(from: systemTrack, sampleRate: config.segmentation.sampleRate)
        defer { source.cleanup() }
        return try await diarize(OfflineDiarizerManager(config: config), models: models, source: source, progress: progress)
    }

    /// Jedyna droga do FluidAudio: modele trafiają do menedżera przed `prepare`, bo bez nich `prepare` sam pobiera model (R02).
    func diarize<Steps: DiarizationSteps>(_ steps: Steps, models: Steps.Models, source: any AudioSampleSource,
                                          progress: (@Sendable (Double) -> Void)?) async throws -> [(speaker: String, start: Double, end: Double)] {
        steps.initialize(models: models)
        let prepared = try await steps.prepare(audioSource: source, audioLoadingSeconds: 0) { done, total in
            if total > 0 { progress?(Double(done) / Double(total)) }
        }
        return try steps.cluster(prepared).segments.map { ($0.speakerId, Double($0.startTimeSeconds), Double($0.endTimeSeconds)) }
    }

    public func release() { models = nil }

    /// Tabela D2 (Fa/Fb z `SpeakerSensitivity`); próg AHC zostaje 0,6.
    static func config(for sensitivity: SpeakerSensitivity) -> OfflineDiarizerConfig {
        var config = OfflineDiarizerConfig.default
        config.clustering.threshold = 0.6
        config.clustering.warmStartFa = sensitivity.fa
        config.clustering.warmStartFb = sensitivity.fb
        return config
    }

    /// Plik PCM źródła dyskowego: 16 kHz float32 mono. Wymagany zapas: dwa takie pliki (R06).
    static func hasRoomForPCM(trackSeconds: Double, freeBytes: Int64) -> Bool {
        Double(freeBytes) >= 2 * 16_000 * 4 * trackSeconds
    }

    /// FluidAudio zakłada plik PCM przed krokami, które mogą rzucić, i nie podaje jego adresu — po błędzie znika każdy nowy plik (R06).
    /// shortcut: nowe = nazwy spoza migawki sprzed startu; równoległy CLI w tym samym TMPDIR straciłby swój plik — wtedy własny konwerter.
    static func makeSource(from track: URL, sampleRate: Int, in dir: URL = FileManager.default.temporaryDirectory,
                           factory: (URL, Int) throws -> DiskBackedAudioSampleSource = {
                               try AudioSourceFactory().makeDiskBackedSource(from: $0, targetSampleRate: $1).source
                           }) throws -> DiskBackedAudioSampleSource {
        let before = Set(temporaryPCMFiles(in: dir))
        do {
            return try factory(track, sampleRate)
        } catch {
            for url in temporaryPCMFiles(in: dir) where !before.contains(url) { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    /// Resztki `fluidaudio-streaming-*.raw` po przerwanym procesie (`cleanup` w `defer` nie zdążył); starsze niż `olderThan`.
    public static func sweepStaleTemporaryFiles(in dir: URL = FileManager.default.temporaryDirectory, olderThan age: TimeInterval = 3600,
                                                now: Date = Date()) {
        let fm = FileManager.default
        for url in temporaryPCMFiles(in: dir) {
            guard let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > age else { continue }
            try? fm.removeItem(at: url)
        }
    }

    private static func temporaryPCMFiles(in dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("fluidaudio-streaming-") && $0.hasSuffix(".raw") }
            .map { dir.appendingPathComponent($0) }
    }
}

/// Kroki `OfflineDiarizerManager` używane przez `diarize`; atrapa w testach sprawdza kolejność bez modelu CoreML.
protocol DiarizationSteps {
    associatedtype Models
    func initialize(models: Models)
    // Bez tego wysłanie menedżera z aktora do `@concurrent` `prepare` nie przechodzi kontroli regionów; praca FluidAudio i tak schodzi z aktora.
    nonisolated(nonsending) func prepare(audioSource: any AudioSampleSource, audioLoadingSeconds: TimeInterval,
                 progressCallback: (@Sendable (Int, Int) -> Void)?) async throws -> PreparedDiarization
    func cluster(_ prepared: PreparedDiarization) throws -> DiarizationResult
}

extension OfflineDiarizerManager: DiarizationSteps {}

/// Przebieg czeka, aż poprzedni się skończy (także błędem); `while`, bo między wznowieniem a wejściem może wskoczyć nowy.
private actor DiarizationQueue {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func serialized<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        while busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return try await body()
    }
}
