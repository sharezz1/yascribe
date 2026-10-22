import AVFoundation
import CoreAudio
import Foundation

/// Trzy częstotliwości, które mogą się rozjechać na słuchawkach Bluetooth (faza 2.0.2): format tapa,
/// nominalna częstotliwość urządzenia zbiorczego i bieżącego wyjścia. 0 = nie udało się odczytać.
public struct TapRates: Equatable, Sendable {
    public var tapFormat: Double
    public var aggregateNominal: Double
    public var outputNominal: Double
}

/// Kanał „Oni": process tap Core Audio na całym wyjściu systemu, przez urządzenie
/// zbiorcze związane z bieżącym wyjściem (spec rdzenia §2, droga Narady).
/// Przy zmianie domyślnego wyjścia przebudowuje tap na nowym urządzeniu; luka
/// wychodzi w dzienniku przez skok czasu hosta (TrackWriter).
/// Format ścieżki ustalany raz, przy `prepare()`: częstotliwość i kanały tapu,
/// Int16. Po przepięciu na urządzenie o innej częstotliwości konwerter
/// przepróbkowuje do formatu ścieżki — nigdy nie pisze w złej częstotliwości.
public final class SystemTapSource: AudioSource, @unchecked Sendable {
    public let trackID = "system"
    private let lock = NSLock()
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var capture: HALCapture?
    private var format: TrackFormat?
    private var tapRate = 0.0
    private var handler: (@Sendable (AudioSourceEvent) -> Void)?
    /// Po `stop()` przebudowa z kolejki obserwatora nie może zostawić capture ani tapu (P8).
    private var stopped = false
    private let watcher = DeviceWatcher(selector: kAudioHardwarePropertyDefaultOutputDevice)
    /// Nasłuchy nominalnej częstotliwości urządzenia zbiorczego i wyjścia; nowe urządzenie zbiorcze po `rebuild()` ma nowy
    /// `AudioObjectID`, więc zakładamy je od nowa po każdej przebudowie (faza 2.0.2: w A częstotliwość spada do 16 kHz w trakcie nagrania).
    private var rateWatchers: [DeviceWatcher] = []
    private var gate = RebuildGate()
    private var rebuildPending = false
    private let rebuildQueue = DispatchQueue(label: "meetnotes.tap.rebuild")

    public init() {}

    public func prepare() throws -> TrackFormat {
        let (tapFmt, uid) = try build()
        let f = TrackFormat(sampleRate: tapFmt.sampleRate, channels: Int(tapFmt.channelCount), deviceUID: uid)
        lock.lock(); format = f; lock.unlock()
        return f
    }

    /// Częstotliwości do pomiaru (`meetnotes-cli tap-rate`); `nil` przed `prepare()`.
    public func rates() -> TapRates? {
        lock.lock(); let agg = aggregate, rate = tapRate; lock.unlock()
        guard agg != kAudioObjectUnknown else { return nil }
        let out = (try? CoreAudioDevices.defaultOutputDevice()).flatMap { try? CoreAudioDevices.nominalSampleRate(of: $0) } ?? 0
        return TapRates(tapFormat: rate, aggregateNominal: (try? CoreAudioDevices.nominalSampleRate(of: agg)) ?? 0, outputNominal: out)
    }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        lock.lock(); self.handler = handler; lock.unlock()
        try startCapture()
        installRateListeners()
        watcher.start { [weak self] in self?.requestRebuild() }
    }

    public func stop() {
        watcher.stop()
        removeRateListeners()
        lock.lock(); stopped = true; let c = capture; capture = nil; lock.unlock()
        c?.stop()
        teardown()
    }

    /// Tworzy tap i urządzenie zbiorcze na bieżącym wyjściu. Zwraca format tapu i UID wyjścia.
    private func build() throws -> (AVAudioFormat, String) {
        let output = try CoreAudioDevices.defaultOutputDevice()
        let outputUID = try CoreAudioDevices.uid(of: output)
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        desc.name = "meetnotes-system"
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { throw AudioSourceError.coreAudio("CreateProcessTap", st) }
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "meetnotes-tap",
            kAudioAggregateDeviceUIDKey: "meetnotes-tap-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        let st2 = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard st2 == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw AudioSourceError.coreAudio("CreateAggregateDevice", st2)
        }
        let fmt: AVAudioFormat
        do {
            fmt = try CoreAudioDevices.tapFormat(of: tapID)
        } catch {
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
        lock.lock(); tap = tapID; aggregate = aggID; tapRate = fmt.sampleRate; lock.unlock()
        return (fmt, outputUID)
    }

    private func startCapture() throws {
        lock.lock()
        guard let f = format, let h = handler, !stopped else { lock.unlock(); return }
        let agg = aggregate, tapID = tap
        lock.unlock()
        let deviceRate = (try? CoreAudioDevices.nominalSampleRate(of: agg)) ?? 0
        let input = CoreAudioDevices.captureFormat(tap: try CoreAudioDevices.tapFormat(of: tapID), deviceRate: deviceRate)
        let c = try HALCapture(device: agg, inputFormat: input,
                               sampleRate: f.sampleRate, channels: f.channels,
                               onChunk: { h(.chunk($0)) }, onFailure: { h(.failed($0)) })
        try c.start()
        lock.lock(); let late = stopped; if !late { capture = c }; lock.unlock()
        if late { c.stop() }
    }

    private func installRateListeners() {
        removeRateListeners()
        lock.lock(); let agg = aggregate; lock.unlock()
        var objects = [agg]
        if let out = try? CoreAudioDevices.defaultOutputDevice() { objects.append(out) }
        let watchers = objects.filter { $0 != kAudioObjectUnknown }
            .map { DeviceWatcher(object: $0, selector: kAudioDevicePropertyNominalSampleRate) }
        for w in watchers { w.start { [weak self] in self?.requestRebuild() } }
        lock.lock(); rateWatchers = watchers; lock.unlock()
    }

    private func removeRateListeners() {
        lock.lock(); let ws = rateWatchers; rateWatchers = []; lock.unlock()
        for w in ws { w.stop() }
    }

    /// Wszystkie powody przebudowy (zmiana domyślnego wyjścia, zmiana częstotliwości) idą przez bramkę. Odroczone ponowienie
    /// jest jedno naraz, a stan czyta w chwili wykonania, więc nie ginie ostatnia zmiana w serii.
    private func requestRebuild() {
        lock.lock()
        if stopped || rebuildPending { lock.unlock(); return }
        let now = ProcessInfo.processInfo.systemUptime
        switch gate.decide(now: now) {
        case .now:
            lock.unlock()
            rebuild()
        case .deferred(let until):
            rebuildPending = true
            lock.unlock()
            rebuildQueue.asyncAfter(deadline: .now() + max(until - now, 0)) { [weak self] in
                guard let self else { return }
                self.lock.lock(); self.rebuildPending = false; self.lock.unlock()
                self.requestRebuild()
            }
        }
    }

    private func teardown() {
        removeRateListeners()
        lock.lock()
        let agg = aggregate, tapID = tap
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
        lock.unlock()
        if agg != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(agg) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    }

    private func rebuild() {
        lock.lock(); let c = capture; capture = nil; let h = handler; lock.unlock()
        c?.stop()
        teardown()
        do {
            let (_, uid) = try build()
            try startCapture()
            installRateListeners()
            h?(.deviceChanged(uid))
        } catch {
            h?(.failed("rebuild: \(error)"))
        }
        lock.lock(); let late = stopped; lock.unlock()
        if late { teardown() } // build() po stop() założył tap i urządzenie zbiorcze od nowa
    }
}
