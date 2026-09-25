@preconcurrency import AVFoundation
import Foundation
import MeetNotesSessionFormat

/// Miary z pomiarów w rozdz. 18, jako funkcje: dopasowanie „nagranie ≈ a·wzorzec"
/// z przeszukaniem opóźnienia. Podstawa testów odbiorczych T1, T3, T4.
public enum AudioFit {
    public struct Result: Equatable, Sendable {
        public var gain: Double
        public var rSquared: Double
        public var lagFrames: Int
        public var correlation: Double
    }

    /// Najlepsze dopasowanie `recorded ≈ gain · reference(t - lag)` dla lag w [0, maxLag].
    /// Obie tablice: mono, ta sama częstotliwość.
    public static func fit(reference: [Float], recorded: [Float], maxLagFrames: Int) -> Result {
        var best = Result(gain: 0, rSquared: 0, lagFrames: 0, correlation: 0)
        guard !reference.isEmpty, !recorded.isEmpty else { return best }
        for lag in 0...max(0, maxLagFrames) {
            let n = min(reference.count, recorded.count - lag)
            guard n > 0 else { break }
            var sxy = 0.0, sxx = 0.0, syy = 0.0
            for i in 0..<n {
                let x = Double(reference[i]), y = Double(recorded[i + lag])
                sxy += x * y; sxx += x * x; syy += y * y
            }
            guard sxx > 0, syy > 0 else { continue }
            let gain = sxy / sxx
            var ssRes = 0.0
            for i in 0..<n {
                let e = Double(recorded[i + lag]) - gain * Double(reference[i])
                ssRes += e * e
            }
            let r2 = 1 - ssRes / syy
            if r2 > best.rSquared {
                best = Result(gain: gain, rSquared: r2, lagFrames: lag, correlation: sxy / (sxx * syy).squareRoot())
            }
        }
        return best
    }

    public static func mono(_ interleaved: [Int16], channels: Int) -> [Float] {
        guard channels > 1 else { return interleaved.map { Float($0) / 32_768 } }
        var out = [Float](repeating: 0, count: interleaved.count / channels)
        for f in out.indices {
            var sum: Float = 0
            for c in 0..<channels { sum += Float(interleaved[f * channels + c]) }
            out[f] = sum / Float(channels) / 32_768
        }
        return out
    }

    /// Przepróbkowanie liniowe do analizy (nie do zapisu): obie ścieżki na 16 kHz
    /// przed dopasowaniem — T3 i T4 porównują 48 kHz stereo z 16 kHz mono.
    public static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        guard from != to, !x.isEmpty else { return x }
        let n = Int(Double(x.count) * to / from)
        return (0..<n).map { i in
            let pos = Double(i) * from / to
            let j = Int(pos), frac = Float(pos - Double(j))
            return j + 1 < x.count ? x[j] * (1 - frac) + x[j + 1] * frac : x[min(j, x.count - 1)]
        }
    }

    /// Częstotliwość, na której `fitFiles` porównuje ścieżki.
    public static let analysisRate = 16_000.0

    /// `meetnotes-cli fit`: wzorzec w dowolnym formacie (np. aiff z `say`), nagranie — nasz CAF.
    public static func fitFiles(reference: URL, recording: URL, maxLagMs: Double) throws -> Result {
        let ref = try readAnyAudio(reference)
        let rec = try CAFReader(url: recording)
        let a = resample(mono(ref.samples, channels: ref.channels), from: ref.rate, to: analysisRate)
        let b = resample(mono(rec.samples, channels: rec.channels), from: rec.sampleRate, to: analysisRate)
        return fit(reference: a, recorded: b, maxLagFrames: Int(maxLagMs / 1000 * analysisRate))
    }

    /// Czyta dowolny plik audio jako Int16 przeplatany. W pętli: jedno `read(into:)`
    /// potrafi oddać mniej ramek niż pojemność bufora (📐 63 454 z 64 000).
    /// Całość trafia do RAM — stąd limit długości zamiast cichego zjedzenia pamięci (S3-1).
    /// ponytail: limit 1 h (~0,7 GB Int16 przy 48 kHz stereo); dłuższe pliki — czytanie zakresu, gdy będzie potrzebne.
    public static func readAnyAudio(_ url: URL, maxSeconds: Double = 3_600) throws
        -> (samples: [Int16], rate: Double, channels: Int) {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let ch = Int(f.processingFormat.channelCount)
        let rate = f.processingFormat.sampleRate
        guard Double(f.length) <= maxSeconds * rate else {
            throw AudioSourceError.deviceUnavailable("plik dłuższy niż \(Int(maxSeconds)) s: \(url.path)")
        }
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 8_192) else {
            throw AudioSourceError.coreAudio("AVAudioPCMBuffer", -1)
        }
        var out: [Int16] = []
        out.reserveCapacity(Int(f.length) * ch)
        while f.framePosition < f.length {
            try f.read(into: buf)
            // Niepełny odczyt to błąd, nie wynik na obciętych danych (S3-2).
            guard buf.frameLength > 0, let p = buf.int16ChannelData else {
                throw AudioSourceError.deviceUnavailable("odczyt urwany na ramce \(f.framePosition) z \(f.length): \(url.path)")
            }
            out.append(contentsOf: UnsafeBufferPointer(start: p[0], count: Int(buf.frameLength) * ch))
        }
        return (out, rate, ch)
    }
}
