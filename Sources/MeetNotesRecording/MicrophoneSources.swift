@preconcurrency import AVFoundation
import CoreAudio
import Foundation

enum MicrophonePermission {
    static func check() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: throw AudioSourceError.permissionDenied("microphone")
        default: return
        }
    }
}

/// Kanał „Ja", surowy: HAL bez żadnego przetwarzania, 16 kHz mono (spec rdzenia §5).
public final class RawMicrophoneSource: AudioSource, @unchecked Sendable {
    public let trackID = "mic_raw"
    public static let sampleRate = 16_000.0
    /// Kalibracja miksu kapsuł pod VP (patrz `HALCapture.converterInput`): o tyle kanał 0
    /// był cichszy od toru bez VP przy tym samym głosie (sonda /tmp/mn-mic-a vs mn-mic-b).
    static let arrayGainDB: Float = 35
    private let lock = NSLock()
    private var capture: HALCapture?
    private var handler: (@Sendable (AudioSourceEvent) -> Void)?
    /// Po `stop()` przebudowa z kolejki obserwatora nie może podpiąć nowego capture (P8).
    private var stopped = false
    private let watcher = DeviceWatcher(selector: kAudioHardwarePropertyDefaultInputDevice)
    /// Lista urządzeń: wybrane ręcznie wejście znika, gdy odłączysz słuchawki, a domyślne wejście się wtedy nie zmienia.
    private let listWatcher = DeviceWatcher(selector: kAudioHardwarePropertyDevices)
    /// Wybór z pigułki (nil = domyślne wejście systemu) i faktycznie otwarte wejście; oba pod `lock`.
    private var preferredUID: String?
    private var inputUID: String?
    private var inputName: String?
    /// `reconsider` z dwóch obserwatorów i `select` z wątku głównego otwierałyby mikrofon równolegle (dwa capture na jeden tor).
    private let reopenQueue = DispatchQueue(label: "meetnotes.mic.reopen")

    public init() {}

    /// UID i nazwa wejścia, które nagrywa teraz ten tor (nie zawsze domyślne systemu).
    public var currentInputUID: String? { lock.lock(); defer { lock.unlock() }; return inputUID }
    public var currentInputName: String? { lock.lock(); defer { lock.unlock() }; return inputName }

    /// Ręczny wybór wejścia w pigułce; nil wraca do domyślnego systemu. Dotyczy tylko bieżącego nagrania.
    public func select(deviceUID: String?) {
        lock.lock(); preferredUID = deviceUID; lock.unlock()
        reopenQueue.sync { reopen() }
    }

    public func prepare() throws -> TrackFormat {
        try MicrophonePermission.check()
        let dev = try CoreAudioDevices.defaultInputDevice()
        return TrackFormat(sampleRate: Self.sampleRate, channels: 1, deviceUID: try CoreAudioDevices.uid(of: dev))
    }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        lock.lock(); self.handler = handler; lock.unlock()
        try open()
        watcher.start { [weak self] in self?.reopenQueue.async { self?.reconsider() } }
        listWatcher.start { [weak self] in self?.reopenQueue.async { self?.reconsider() } }
    }

    public func stop() {
        watcher.stop()
        listWatcher.stop()
        lock.lock(); stopped = true; let c = capture; capture = nil; lock.unlock()
        c?.stop()
    }

    /// Wybrane wejście, a gdy go brak (albo nic nie wybrano), domyślne systemu.
    private func resolveDevice() throws -> AudioObjectID {
        lock.lock(); let preferred = preferredUID; lock.unlock()
        let uid = InputChoice.resolve(preferred: preferred, available: CoreAudioDevices.inputDevices(),
                                      defaultUID: CoreAudioDevices.defaultInputUID())
        if let uid, let id = try? CoreAudioDevices.deviceID(forUID: uid) { return id }
        return try CoreAudioDevices.defaultInputDevice()
    }

    /// Zmiana domyślnego wejścia albo listy urządzeń: otwórz od nowa tylko gdy wynik wyboru jest inny niż to, co nagrywamy.
    private func reconsider() {
        lock.lock(); let current = inputUID, preferred = preferredUID; lock.unlock()
        if InputChoice.needsReopen(current: current, preferred: preferred, available: CoreAudioDevices.inputDevices(),
                                   defaultUID: CoreAudioDevices.defaultInputUID()) { reopen() }
    }

    @discardableResult
    private func open() throws -> String {
        let dev = try resolveDevice()
        lock.lock(); let h = handler, late = stopped; lock.unlock()
        guard let h, !late else { return "" }
        let c = try HALCapture(device: dev, inputFormat: try CoreAudioDevices.inputFormat(of: dev),
                               sampleRate: Self.sampleRate, channels: 1, arrayGain: pow(10, Self.arrayGainDB / 20),
                               onChunk: { h(.chunk($0)) }, onFailure: { h(.failed($0)) })
        try c.start()
        let uid = try CoreAudioDevices.uid(of: dev)
        lock.lock(); let lateStop = stopped
        if !lateStop { capture = c; inputUID = uid; inputName = try? CoreAudioDevices.name(of: dev) }
        lock.unlock()
        if lateStop { c.stop(); return "" }
        return uid
    }

    private func reopen() {
        lock.lock(); let c = capture; capture = nil; let h = handler; lock.unlock()
        c?.stop()
        do {
            let uid = try open()
            if !uid.isEmpty { h?(.deviceChanged(uid)) } // "" = spóźniony stop(), bez zdarzenia
        } catch { h?(.failed("reopen: \(error)")) }
    }
}

/// Kanał „Ja" po platformowym AEC (`setVoiceProcessingEnabled`). Kopia obok
/// surowego — decyzja o AEC zostaje odwracalna (spec rdzenia §2).
/// 🔴 Przetwarzanie głosu domyślnie ścisza inne aplikacje, w tym Teams, i to
/// ściszenie trafiłoby też do kanału systemowego — ustawiamy je na minimum.
/// Minimum nadal ścisza (sonda S5), więc tor jest opcją `--aec`, nie domyślnym.
public final class VoiceProcessedMicrophoneSource: AudioSource, @unchecked Sendable {
    public let trackID = "mic_aec"
    public static let sampleRate = 16_000.0
    private let engine = AVAudioEngine()
    private var converter: FormatConverter?
    private let watcher = DeviceWatcher(selector: kAudioHardwarePropertyDefaultInputDevice)

    public init() {}

    public func prepare() throws -> TrackFormat {
        try MicrophonePermission.check()
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        input.voiceProcessingOtherAudioDuckingConfiguration =
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        let dev = try CoreAudioDevices.defaultInputDevice()
        converter = try FormatConverter(input: input.outputFormat(forBus: 0), sampleRate: Self.sampleRate, channels: 1)
        return TrackFormat(sampleRate: Self.sampleRate, channels: 1, deviceUID: try CoreAudioDevices.uid(of: dev))
    }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        guard let conv = converter else { throw AudioSourceError.deviceUnavailable("not prepared") }
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { buf, when in
            guard when.isHostTimeValid else { return }
            let before = conv.failures
            let s = conv.convert(buf)
            if FormatConverter.shouldReport(before: before, after: conv.failures) {
                handler(.failed("convert failures: \(conv.failures)"))
            }
            if !s.isEmpty { handler(.chunk(AudioChunk(samples: s, hostTime: when.hostTime))) }
        }
        try engine.start()
        // Zdarzenie mówi „stopped", więc tor naprawdę staje — bez tego pisałby dalej
        // ze starego wejścia obok zgłoszonej awarii (P5).
        let engine = engine
        watcher.start {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            handler(.failed("inputDeviceChanged: mic_aec stopped, mic_raw continues"))
        }
    }

    public func stop() {
        watcher.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
