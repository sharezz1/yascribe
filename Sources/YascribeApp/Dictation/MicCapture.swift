@preconcurrency import AVFoundation
import Foundation
import YascribeDictation
import YascribeRecording

/// Mikrofon dyktowania: nowy `RawMicrophoneSource` na sesję, próbki 16 kHz mono tylko w pamięci.
/// Bezpieczna jako `@unchecked Sendable`: cały stan (źródło, bufor, poziom) jest pod `lock`.
final class MicCapture: AudioCapturing, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case permission, device(String)
        var errorDescription: String? {
            switch self {
            case .permission: "Microphone access is needed for dictation."
            case let .device(why): "Microphone unavailable: \(why)"
            }
        }
    }

    /// Silnik kończy sesję po 300 s; sufit tylko chroni pamięć, gdyby stop nie przyszedł.
    private static let maxSamples = 300 * 16_000

    private let lock = NSLock()
    private var source: RawMicrophoneSource?
    private var samples: [Int16] = []
    private var smoothed: Float = 0

    var level: Float { lock.lock(); defer { lock.unlock() }; return smoothed }

    func start(onFailure: @escaping @Sendable (String) -> Void) throws {
        _ = stop()   // obrona przed startem bez wcześniejszego stopu: nie zostawiamy otwartego źródła
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            // Okno zgody jest asynchroniczne: tę próbę odrzucamy, następna ruszy po zgodzie.
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw CaptureError.permission
        default: throw CaptureError.permission
        }
        let src = RawMicrophoneSource()
        lock.lock(); source = src; samples = []; smoothed = 0; lock.unlock()
        do {
            _ = try src.prepare()
            try src.start { [weak self] event in
                switch event {
                case let .chunk(chunk): self?.append(chunk.samples)
                case let .failed(why) where Self.isFatal(event): onFailure(why)
                case .endOfStream: onFailure("Microphone stopped.")
                case .failed, .deviceChanged: break
                }
            }
        } catch {
            _ = stop()
            if case AudioSourceError.permissionDenied = error { throw CaptureError.permission }
            throw CaptureError.device("\(error)")
        }
    }

    /// Raporty konwersji i niedopasowania przychodzą przy działającym strumieniu; koniec to tylko nieudane przełączenie i koniec strumienia.
    static func isFatal(_ event: AudioSourceEvent) -> Bool {
        switch event {
        case .endOfStream: true
        case let .failed(why): why.hasPrefix(RawMicrophoneSource.reopenFailurePrefix)
        case .chunk, .deviceChanged: false
        }
    }

    func stop() -> [Int16] {
        lock.lock()
        let src = source
        let out = samples
        source = nil; samples = []; smoothed = 0
        lock.unlock()
        src?.stop()   // poza `lock`: handler audio bierze ten sam zamek
        return out
    }

    private func append(_ chunk: [Int16]) {
        guard !chunk.isEmpty else { return }
        var sum: Float = 0
        for s in chunk { let f = Float(s) / 32_768; sum += f * f }
        let db = 10 * log10(max(sum / Float(chunk.count), 1e-10))   // dBFS z mocy średniej
        let level = min(max((db + 50) / 50, 0), 1)                     // -50 dBFS → 0, 0 dBFS → 1
        lock.lock()
        if source != nil {
            if samples.count < Self.maxSamples { samples.append(contentsOf: chunk.prefix(Self.maxSamples - samples.count)) }
            smoothed = 0.6 * smoothed + 0.4 * level
        }
        lock.unlock()
    }
}
