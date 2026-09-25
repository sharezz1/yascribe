@preconcurrency import AVFoundation
import CoreAudio
import Foundation

/// IOProc na urządzeniu Core Audio → konwersja → porcje z czasem hosta pierwszej
/// próbki (`mHostTime` wejścia). Wspólne dla tapu (urządzenie zbiorcze)
/// i surowego mikrofonu.
final class HALCapture: @unchecked Sendable {
    private let device: AudioObjectID
    private let inputFormat: AVAudioFormat
    private let converter: FormatConverter
    private let onChunk: @Sendable (AudioChunk) -> Void
    private let onFailure: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "meetnotes.hal", qos: .userInteractive)
    private var procID: AudioDeviceIOProcID?

    init(device: AudioObjectID, inputFormat: AVAudioFormat, sampleRate: Double, channels: Int,
         onChunk: @escaping @Sendable (AudioChunk) -> Void, onFailure: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.device = device
        self.inputFormat = inputFormat
        self.converter = try FormatConverter(input: inputFormat, sampleRate: sampleRate, channels: channels)
        self.onChunk = onChunk
        self.onFailure = onFailure
    }

    func start() throws {
        let fmt = inputFormat
        let conv = converter
        let emit = onChunk
        let fail = onFailure
        var proc: AudioDeviceIOProcID?
        let st = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, inInputData, inInputTime, _, _ in
            guard inInputTime.pointee.mFlags.contains(.hostTimeValid),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: inInputData, deallocator: nil) else { return }
            let before = conv.failures
            let samples = conv.convert(buf)
            if conv.failures > before && (conv.failures == 1 || conv.failures % 1_000 == 0) {
                fail("convert failures: \(conv.failures)")
            }
            if !samples.isEmpty { emit(AudioChunk(samples: samples, hostTime: inInputTime.pointee.mHostTime)) }
        }
        guard st == noErr, let proc else { throw AudioSourceError.coreAudio("CreateIOProc", st) }
        procID = proc
        let s2 = AudioDeviceStart(device, proc)
        guard s2 == noErr else {
            AudioDeviceDestroyIOProcID(device, proc) // 🟡 bez tego IOProc wycieka przy nieudanym starcie
            procID = nil
            throw AudioSourceError.coreAudio("DeviceStart", s2)
        }
    }

    func stop() {
        guard let proc = procID else { return }
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
        procID = nil
    }
}
