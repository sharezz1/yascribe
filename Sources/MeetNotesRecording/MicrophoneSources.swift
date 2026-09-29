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
    private let lock = NSLock()
    private var capture: HALCapture?
    private var handler: (@Sendable (AudioSourceEvent) -> Void)?
    /// Po `stop()` przebudowa z kolejki obserwatora nie może podpiąć nowego capture (P8).
    private var stopped = false
    private let watcher = DeviceWatcher(selector: kAudioHardwarePropertyDefaultInputDevice)

    public init() {}

    public func prepare() throws -> TrackFormat {
        try MicrophonePermission.check()
        let dev = try CoreAudioDevices.defaultInputDevice()
        return TrackFormat(sampleRate: Self.sampleRate, channels: 1, deviceUID: try CoreAudioDevices.uid(of: dev))
    }

    public func start(_ handler: @escaping @Sendable (AudioSourceEvent) -> Void) throws {
        lock.lock(); self.handler = handler; lock.unlock()
        try open()
        watcher.start { [weak self] in self?.reopen() }
    }

    public func stop() {
        watcher.stop()
        lock.lock(); stopped = true; let c = capture; capture = nil; lock.unlock()
        c?.stop()
    }

    @discardableResult
    private func open() throws -> String {
        let dev = try CoreAudioDevices.defaultInputDevice()
        lock.lock(); let h = handler, late = stopped; lock.unlock()
        guard let h, !late else { return "" }
        let c = try HALCapture(device: dev, inputFormat: try CoreAudioDevices.inputFormat(of: dev),
                               sampleRate: Self.sampleRate, channels: 1,
                               onChunk: { h(.chunk($0)) }, onFailure: { h(.failed($0)) })
        try c.start()
        lock.lock(); let lateStop = stopped; if !lateStop { capture = c }; lock.unlock()
        if lateStop { c.stop(); return "" }
        return try CoreAudioDevices.uid(of: dev)
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
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: true, duckingLevel: .min)
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
