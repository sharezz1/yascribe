@preconcurrency import AVFoundation
import Foundation

/// Strumieniowa konwersja dowolnego formatu urządzenia na format ścieżki:
/// Int16, przeplatany, stała częstotliwość. Jeden egzemplarz na strumień —
/// konwerter trzyma stan filtra między wywołaniami. Bez ditheringu.
public final class FormatConverter {
    public let input: AVAudioFormat
    public let output: AVAudioFormat
    private let converter: AVAudioConverter
    /// Nieudane konwersje — źródło zgłasza je jako .failed zamiast po cichu gubić dźwięk.
    public private(set) var failures = 0

    /// Czy zgłosić `.failed` po wywołaniu, które zmieniło licznik z `before` na `after`:
    /// pierwsza awaria i każde przekroczenie kolejnego tysiąca. Liczone na sumie,
    /// bo jedno `convert` tnie bufor na plasterki i potrafi dodać kilka naraz (P1).
    static func shouldReport(before: Int, after: Int) -> Bool {
        after > before && (before == 0 || after / 1_000 > before / 1_000)
    }

    public init(input: AVAudioFormat, sampleRate: Double, channels: Int) throws {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                      channels: AVAudioChannelCount(channels), interleaved: true),
              let conv = AVAudioConverter(from: input, to: out) else {
            throw AudioSourceError.coreAudio("AVAudioConverter", -1)
        }
        conv.dither = false
        // Bez „rozgrzewania" filtra: wyjście zaczyna się razem z wejściem, więc czas
        // hosta pierwszej próbki wejścia jest też czasem pierwszej próbki wyjścia.
        conv.primeMethod = .none
        if input.channelCount > 2 {
            // Układ dyskretny (np. mikrofon pod przetwarzaniem głosu): downmix daje ciszę,
            // więc bierzemy pierwsze kanały wprost.
            conv.channelMap = (0..<channels).map { NSNumber(value: $0) }
        } else if input.channelCount > 1 && channels == 1 {
            conv.downmix = true
        }
        self.input = input
        self.output = out
        self.converter = conv
    }

    /// Największy plasterek podawany konwerterowi naraz. 📐 Dla buforów do 512
    /// ramek wyjście zgadza się z wejściem co do ramki przy każdym wywołaniu;
    /// bufor 4800 ramek (typowy dla `installTap`) wychodzi obcięty do 4096,
    /// a reszta wypada z następnym buforem — z cudzym czasem hosta.
    static let sliceFrames: AVAudioFrameCount = 1_024

    public func convert(_ buffer: AVAudioPCMBuffer) -> [Int16] {
        guard buffer.frameLength > 0 else { return [] }
        if buffer.frameLength <= Self.sliceFrames { return convertSlice(buffer) }
        var out: [Int16] = []
        var start: AVAudioFrameCount = 0
        while start < buffer.frameLength {
            let n = min(Self.sliceFrames, buffer.frameLength - start)
            if let slice = Self.slice(buffer, from: start, count: n) { out += convertSlice(slice) } else { failures += 1 }
            start += n
        }
        return out
    }

    private func convertSlice(_ buffer: AVAudioPCMBuffer) -> [Int16] {
        let ratio = output.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { failures += 1; return [] }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, st in
            if supplied {
                st.pointee = .noDataNow
                return nil
            }
            supplied = true
            st.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error, let p = out.int16ChannelData else { failures += 1; return [] }
        return Array(UnsafeBufferPointer(start: p[0], count: Int(out.frameLength) * Int(output.channelCount)))
    }

    /// Kopia ramek [from, from+count) — działa dla układu przeplatanego i nie.
    static func slice(_ b: AVAudioPCMBuffer, from: AVAudioFrameCount, count: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: count) else { return nil }
        dst.frameLength = count
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: b.audioBufferList))
        let out = UnsafeMutableAudioBufferListPointer(dst.mutableAudioBufferList)
        for i in 0..<min(src.count, out.count) {
            guard let s = src[i].mData, let d = out[i].mData, b.frameLength > 0 else { continue }
            let bytesPerFrame = Int(src[i].mDataByteSize) / Int(b.frameLength)
            memcpy(d, s.advanced(by: Int(from) * bytesPerFrame), Int(count) * bytesPerFrame)
            out[i].mDataByteSize = UInt32(Int(count) * bytesPerFrame)
        }
        return dst
    }
}
