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
    private let queue = DispatchQueue(label: "meetnotes.hal", qos: .userInteractive)
    private var procID: AudioDeviceIOProcID?

    init(device: AudioObjectID, inputFormat: AVAudioFormat, sampleRate: Double, channels: Int,
         onChunk: @escaping @Sendable (AudioChunk) -> Void) throws {
        self.device = device
        self.inputFormat = inputFormat
        self.converter = try FormatConverter(input: inputFormat, sampleRate: sampleRate, channels: channels)
        self.onChunk = onChunk
    }

    func start() throws {
        let fmt = inputFormat
        let conv = converter
        let emit = onChunk
        var proc: AudioDeviceIOProcID?
        let st = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, inInputData, inInputTime, _, _ in
            guard inInputTime.pointee.mFlags.contains(.hostTimeValid),
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: inInputData, deallocator: nil) else { return }
            let samples = conv.convert(buf)
            if !samples.isEmpty { emit(AudioChunk(samples: samples, hostTime: inInputTime.pointee.mHostTime)) }
        }
        guard st == noErr, let proc else { throw AudioSourceError.coreAudio("CreateIOProc", st) }
        procID = proc
        let s2 = AudioDeviceStart(device, proc)
        guard s2 == noErr else { throw AudioSourceError.coreAudio("DeviceStart", s2) }
    }

    func stop() {
        guard let proc = procID else { return }
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
        procID = nil
    }
}
