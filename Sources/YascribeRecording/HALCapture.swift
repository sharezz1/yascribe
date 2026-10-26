@preconcurrency import AVFoundation
import CoreAudio
import Foundation

/// IOProc na urządzeniu Core Audio → konwersja → porcje z czasem hosta pierwszej
/// próbki (`mHostTime` wejścia). Wspólne dla tapu (urządzenie zbiorcze)
/// i surowego mikrofonu.
final class HALCapture: @unchecked Sendable {
    private let device: AudioObjectID
    private let sampleRate: Double
    private let channels: Int
    /// Zmieniane tylko z `queue` (IOProc) po starcie.
    private var inputFormat: AVAudioFormat
    private var converter: FormatConverter
    /// Tylko surowy mikrofon: wzmocnienie miksu kapsuł, gdy urządzenie wystawia > 2 kanały; nil = bez miksu.
    private let arrayGain: Float?
    private let onChunk: @Sendable (AudioChunk) -> Void
    private let onFailure: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "yascribe.hal", qos: .userInteractive)
    private var procID: AudioDeviceIOProcID?

    init(device: AudioObjectID, inputFormat: AVAudioFormat, sampleRate: Double, channels: Int, arrayGain: Float? = nil,
         onChunk: @escaping @Sendable (AudioChunk) -> Void, onFailure: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.device = device
        self.sampleRate = sampleRate
        self.channels = channels
        self.inputFormat = inputFormat
        self.arrayGain = arrayGain
        self.converter = try FormatConverter(input: Self.converterInput(inputFormat, arrayGain), sampleRate: sampleRate, channels: channels)
        self.onChunk = onChunk
        self.onFailure = onFailure
    }

    func start() throws {
        var proc: AudioDeviceIOProcID?
        let st = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { [self] _, inInputData, inInputTime, _, _ in
            guard inInputTime.pointee.mFlags.contains(.hostTimeValid) else { return }
            deliver(inInputData, hostTime: inInputTime.pointee.mHostTime)
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

    /// Urządzenie zmienia układ wejść pod działającym IOProc, gdy rusza przetwarzanie
    /// głosu (sonda S2): głośniki dostają 4 kanały referencji echa, które urządzenie
    /// zbiorcze tapu wystawia PRZED tapem (bufory [4, 2] zamiast [2]), a mikrofon
    /// przechodzi z 1 na 3 kanały. Bierzemy więc ostatni strumień (tap idzie po
    /// podurządzeniach) i dopasowujemy format do jego liczby kanałów.
    /// ponytail: tylko formaty przeplatane — takie wystawia HAL i tap; inne idą jak dawniej.
    private func deliver(_ data: UnsafePointer<AudioBufferList>, hostTime: UInt64) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        guard inputFormat.isInterleaved, let last = list.last else { return emit(data, hostTime: hostTime) }
        if last.mNumberChannels != inputFormat.channelCount && !adapt(to: last.mNumberChannels) { return }
        var one = AudioBufferList(mNumberBuffers: 1, mBuffers: last)
        withUnsafePointer(to: &one) { emit($0, hostTime: hostTime) }
    }

    private func emit(_ data: UnsafePointer<AudioBufferList>, hostTime: UInt64) {
        guard let buf = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: data, deallocator: nil) else {
            reportMismatch("buffer list does not match \(inputFormat)")
            return
        }
        let before = converter.failures
        let samples: [Int16]
        if let g = arrayGain, buf.format.channelCount > 2 {
            guard let mono = Self.mixArray(buf, gain: g) else { converter.recordFailure(); return }
            samples = converter.convert(mono)
        } else {
            samples = converter.convert(buf)
        }
        if FormatConverter.shouldReport(before: before, after: converter.failures) {
            onFailure("convert failures: \(converter.failures)")
        }
        if !samples.isEmpty { onChunk(AudioChunk(samples: samples, hostTime: hostTime)) }
    }

    private func adapt(to n: UInt32) -> Bool {
        var d = inputFormat.streamDescription.pointee
        d.mChannelsPerFrame = n
        d.mBytesPerFrame = n * (d.mBitsPerChannel / 8)
        d.mBytesPerPacket = d.mBytesPerFrame * d.mFramesPerPacket
        guard let f = CoreAudioDevices.format(d),
              let c = try? FormatConverter(input: Self.converterInput(f, arrayGain), sampleRate: sampleRate, channels: channels) else {
            reportMismatch("cannot adapt to \(n) channels")
            return false
        }
        inputFormat = f
        converter = c
        return true
    }

    /// Pod przetwarzaniem głosu wbudowany mikrofon wystawia surowe kapsuły macierzy
    /// (MacBook Air: 3 kanały zamiast 1 kanału po beamformingu i DSP) — sonda runda 3:
    /// kanał 0 jest ~35 dB cichszy od toru bez VP. Konwerter dostaje wtedy mono z `mixArray`.
    static func converterInput(_ f: AVAudioFormat, _ arrayGain: Float?) -> AVAudioFormat {
        guard arrayGain != nil, f.channelCount > 2,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: f.sampleRate, channels: 1, interleaved: false)
        else { return f }
        return mono
    }

    /// Średnia kanałów × `gain`, obcięta do ±1. Średnia trzyma poziom jednej kapsuły
    /// (kalibracja z kanału 0 zostaje ważna), a nieskorelowany szum spada.
    /// ponytail: stałe wzmocnienie zmierzone na jednym MacBooku Air; inny sprzęt → nowa sonda i nowa wartość.
    static func mixArray(_ b: AVAudioPCMBuffer, gain: Float) -> AVAudioPCMBuffer? {
        guard let src = b.floatChannelData,
              let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: b.format.sampleRate, channels: 1, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: b.frameLength), let dst = out.floatChannelData?[0]
        else { return nil }
        out.frameLength = b.frameLength
        let n = Int(b.format.channelCount), stride = b.stride, il = b.format.isInterleaved, scale = gain / Float(n)
        for i in 0..<Int(b.frameLength) {
            var sum: Float = 0
            for c in 0..<n { sum += il ? src[0][i * stride + c] : src[c][i] }
            dst[i] = min(max(sum * scale, -1), 1)
        }
        return out
    }

    /// Raz na przechwytywanie: dawniej taki bufor znikał po cichu i tor miał 0 ramek bez śladu.
    private var mismatchReported = false
    private func reportMismatch(_ why: String) {
        guard !mismatchReported else { return }
        mismatchReported = true
        onFailure(why)
    }

    func stop() {
        guard let proc = procID else { return }
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
        procID = nil
    }
}
