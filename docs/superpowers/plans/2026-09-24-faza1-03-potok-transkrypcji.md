# Plan C — potok transkrypcji

> **Dla wykonawcy (Hermes):** najpierw przegląd §0 „Instrukcja dla Hermesa". Jedno zadanie = jedna sesja. Kroki używają pól `- [ ]`.

**Cel:** z katalogu sesji do transkryptu z podziałem „ja / oni", czasem słów na osi sesji, jawnymi lukami i oznaczeniem zmyślonego języka — wznawialnie, bez płacenia za ciszę. Plus `meetnotes-cli transcribe`.

**Architektura:** ścieżka → 16 kHz mono (offline, z opróżnieniem filtra) → bramka energetyczna z histerezą → pakowanie fragmentów mowy w długie okna do limitu modelu (tablica segmentów do przeliczania czasu) → WAV → ASR → scalenie po znacznikach słów, przeliczenie przez kotwice zegara → strażnik języka. Każde okno zapisane osobno na dysk, więc przerwany przebieg dokańcza tylko brakujące.

**Stos:** Swift 6.4, AVFoundation (`AVAudioConverter` offline), `MeetNotesSessionFormat`, `MeetNotesProviders`.

**Specyfikacja:** `docs/superpowers/specs/2026-09-24-faza1-warstwa-dostawcow-design.md` §1.5, §6, §8, §10 (po poprawkach z zadania 0). Przegląd: `docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md`.

## Wspólne ograniczenia

Obowiązują w całości: przegląd §4. Najważniejsze dla tego planu:

- `MeetNotesTranscription` zależy od `MeetNotesSessionFormat` i `MeetNotesProviders`, **nie** od `MeetNotesRecording`. Testy tego modułu zależą od nagrywania — budują prawdziwe sesje rejestratorem.
- Mówcy z kanałów: `system` → „Them", `mic_aec` → „Me", a gdy go brak albo ma awarię (`trackFailed`) — `mic_raw` (E3). Domyślnie aplikacja i CLI nagrywają bez VP, więc zwykle „Me" to `mic_raw` (S5).
- Bramka: próg −45 dBFS, atak 0,1 s, zwolnienie 0,5 s, zapas 0,2 s, ramka 20 ms (wartości startowe do strojenia — O2).
- Okno: limit 59 s (MAI-Transcribe-2: 60 s), przerwa między fragmentami 0,3 s, cięcie długiej mowy w najcichszej ramce z ostatnich 5 s przed limitem.
- Wypowiedź: słowa jednego mówcy z przerwą < 1,2 s.
- Strażnik języka tylko dla pary pl/en; wymaga ≥ 4 słów; dla innych języków milczy.
- Katalog przebiegu: `<sesja>/runs/<runID>/` z `run.json`, `transcript.json`, `chunks/<ścieżka>-<n>.json`.

## Na co patrzeć przy przeglądzie

1. **Milczący mikrofon przez całe spotkanie** (norma: słuchasz częściej, niż mówisz) → zero żądań z tego kanału. Test `silentSessionSendsNothing` (C3). Rozdz. 13: 82% halucynacji na takim kanale.
2. **Przebieg przerwany w połowie serii** → drugi przebieg nie płaci za gotowe okna, a nieudane okna są jawnymi lukami, nie ciszą. Test `interruptedRunResumesWithoutPayingAgain` (C3).
3. **90 s monologu bez pauzy** → cięcie w najcichszym miejscu przed limitem, nie w połowie słowa. Test `longSpeechIsCutAtTheQuietestPointBeforeTheLimit` (C1).
4. **Mikrofon rusza 165 ms po systemie** (zmierzone u Narady) → słowa „Me" przesunięte o to opóźnienie. Test `speakersComeFromChannelsWithMicOffsetApplied` (C3).
5. **Polskie zdanie z angielską wstawką** („mieliśmy wczoraj some things") → nie jest oznaczane jako zmyślony angielski. Test `realPolishIsNotFlagged` (C2).

---

### Zadanie C1: Przygotowanie audio — przepróbkowanie, bramka, pakowanie, WAV (P6)

Status: ✅ zweryfikowane (10 testów). `Signals.swift` to początek zweryfikowanego `Helpers.swift` ze spike'a — od `let ns` do `burstTrack` włącznie — z importami ograniczonymi do `Foundation` i `MeetNotesSessionFormat`. Reszta tego pliku wchodzi w C3.

**Pliki:**
- Utwórz: `Sources/MeetNotesTranscription/Resampler.swift`, `EnergyGate.swift`, `ChunkPacker.swift`, `WAVEncoder.swift`
- Usuń: `Sources/MeetNotesTranscription/_Placeholder.swift`, `Tests/MeetNotesTranscriptionTests/_Placeholder.swift`
- Test: `Tests/MeetNotesTranscriptionTests/Signals.swift`, `Tests/MeetNotesTranscriptionTests/GateAndPackerTests.swift`

**Interfejsy:**
- Dostarcza: `Resampler.asrRate` (= 16 000), `Resampler.toASR(_ samples: [Int16], sampleRate:channels:) throws -> [Float]`, `ResampleError.converter`. `EnergyGate(_ config:)`, `EnergyGate.Config` (`thresholdDBFS`, `attackSeconds`, `releaseSeconds`, `paddingSeconds`), `EnergyGate.frameSeconds` (= 0,02), `frameLevels(_:rate:)`, `speechRegions(_:rate:) -> [Range<Int>]`. `ChunkSegment(sourceStart:sourceEnd:chunkStart:)`, `Chunk(index:segments:length:)` z `sourceSeconds(chunkSeconds:rate:)`, `sourceStartSeconds`, `sourceEndSeconds`; `ChunkPacker(maxSeconds:)` z `pack(_:samples:) -> [Chunk]`. `WAVEncoder.encode(_:samples:rate:) -> Data`, `WAVEncoder.wav(_:rate:) -> Data`.

- [x] **Krok 1: Testy, które padną.** Usuń obie zaślepki transkrypcji i utwórz:

`Tests/MeetNotesTranscriptionTests/Signals.swift`:

```swift
import Foundation
import MeetNotesSessionFormat

let ns = Timebase(numer: 1, denom: 1)

func tone(seconds: Double, rate: Double, hz: Double = 300, amp: Double = 0.3) -> [Int16] {
    (0..<Int(seconds * rate)).map { Int16(amp * 32_767 * sin(2 * .pi * hz * Double($0) / rate)) }
}

func silence(seconds: Double, rate: Double, channels: Int = 1) -> [Int16] {
    [Int16](repeating: 0, count: Int(seconds * rate) * channels)
}

/// Nagranie ze „słowami": ton 2 s co 10 s, zaczynając od 5 s.
func burstTrack(seconds: Double, rate: Double) -> (samples: [Int16], starts: [Double]) {
    var s: [Int16] = []
    var starts: [Double] = []
    var t = 0.0
    while t + 10 <= seconds {
        s += silence(seconds: 5, rate: rate); starts.append(t + 5)
        s += tone(seconds: 2, rate: rate); s += silence(seconds: 3, rate: rate)
        t += 10
    }
    return (s, starts)
}
```

`Tests/MeetNotesTranscriptionTests/GateAndPackerTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesTranscription

private func floats(_ s: [Int16]) -> [Float] { s.map { Float($0) / 32_768 } }

@Test func resamplerKeepsDurationAndEnergy() throws {
    let stereo = tone(seconds: 1, rate: 48_000).flatMap { [$0, $0] }
    let x = try Resampler.toASR(stereo, sampleRate: 48_000, channels: 2)
    #expect(abs(x.count - 16_000) <= 16)
    let rms = (x.map { Double($0 * $0) }.reduce(0, +) / Double(x.count)).squareRoot()
    #expect(rms > 0.18 && rms < 0.25) // sinus 0,3 → RMS ≈ 0,21
}

@Test func pureSilenceProducesNoRegions() {
    // P6: cisza nie generuje żadnego żądania.
    #expect(EnergyGate().speechRegions(floats(silence(seconds: 30, rate: 16_000)), rate: 16_000).isEmpty)
}

@Test func burstBecomesOneRegionWithPadding() {
    let x = floats(silence(seconds: 5, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 5, rate: 16_000))
    let r = EnergyGate().speechRegions(x, rate: 16_000)
    #expect(r.count == 1)
    #expect(abs(Double(r[0].lowerBound) / 16_000 - 4.8) < 0.05)
    #expect(abs(Double(r[0].upperBound) / 16_000 - 7.2) < 0.05)
}

@Test func clickShorterThanAttackIsIgnored() {
    let x = floats(silence(seconds: 2, rate: 16_000) + tone(seconds: 0.04, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    #expect(EnergyGate().speechRegions(x, rate: 16_000).isEmpty)
}

@Test func shortPauseDoesNotSplitSpeech() {
    let x = floats(tone(seconds: 1, rate: 16_000) + silence(seconds: 0.3, rate: 16_000) + tone(seconds: 1, rate: 16_000)
                   + silence(seconds: 2, rate: 16_000))
    #expect(EnergyGate().speechRegions(x, rate: 16_000).count == 1)
}

@Test func shortRegionsArePackedIntoLongWindows() {
    // „Nie tnij na sekundy" (rozdz. 13): 12 fragmentów po 2,4 s → jedno okno, nie dwanaście.
    let regions = (0..<12).map { i in (i * 160_000)..<(i * 160_000 + 38_400) }
    let chunks = ChunkPacker(maxSeconds: 59).pack(regions, samples: [Float](repeating: 0.1, count: 12 * 160_000))
    #expect(chunks.count == 1)
    #expect(chunks[0].segments.count == 12)
    #expect(Double(chunks[0].length) / 16_000 < 59)
}

@Test func windowNeverExceedsModelLimit() {
    let regions = (0..<40).map { i in (i * 160_000)..<(i * 160_000 + 80_000) } // 40 × 5 s
    let chunks = ChunkPacker(maxSeconds: 59).pack(regions, samples: [Float](repeating: 0.1, count: 40 * 160_000))
    #expect(chunks.allSatisfy { Double($0.length) / 16_000 <= 59 })
    #expect(chunks.flatMap(\.segments).count == 40)
}

@Test func longSpeechIsCutAtTheQuietestPointBeforeTheLimit() {
    // 90 s ciągłej mowy z cichym miejscem w 57. sekundzie.
    var x = [Float](repeating: 0.3, count: 90 * 16_000)
    for i in (57 * 16_000)..<(57 * 16_000 + 800) { x[i] = 0.001 }
    let chunks = ChunkPacker(maxSeconds: 59).pack([0..<x.count], samples: x)
    #expect(chunks.count == 2)
    let cut = Double(chunks[0].segments[0].sourceEnd) / 16_000
    #expect(abs(cut - 57.025) < 0.03)
}

@Test func chunkTimeMapsBackToTrackTime() {
    let c = Chunk(index: 0, segments: [ChunkSegment(sourceStart: 80_000, sourceEnd: 118_400, chunkStart: 0),
                                       ChunkSegment(sourceStart: 240_000, sourceEnd: 278_400, chunkStart: 43_200)], length: 81_600)
    #expect(abs(c.sourceSeconds(chunkSeconds: 1.0, rate: 16_000) - 6.0) < 1e-9)   // w 1. fragmencie
    #expect(abs(c.sourceSeconds(chunkSeconds: 3.2, rate: 16_000) - 15.5) < 1e-9)  // 0,5 s w 2. fragmencie
    #expect(abs(c.sourceSeconds(chunkSeconds: 2.5, rate: 16_000) - 7.4) < 1e-9)   // w przerwie → krawędź 1. fragmentu
}

@Test func wavHasCorrectHeaderAndLength() {
    let d = WAVEncoder.wav([1, 2, 3, 4], rate: 16_000)
    #expect(d.count == 44 + 8)
    #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
    #expect(d[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) } == 16_000)
}
```

- [x] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesTranscriptionTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `Resampler`, `EnergyGate`, `ChunkPacker`, `WAVEncoder`.

- [x] **Krok 3: Implementacja.**

`Sources/MeetNotesTranscription/Resampler.swift`:

```swift
@preconcurrency import AVFoundation
import Foundation

public enum ResampleError: Error, Equatable {
    case converter
}

/// Przepróbkowanie całej ścieżki do 16 kHz mono na potrzeby ASR. Offline:
/// konwerter dostaje koniec strumienia i oddaje ogon filtra — inaczej niż
/// w nagrywaniu, gdzie strumień trwa.
public enum Resampler {
    public static let asrRate = 16_000.0

    public static func toASR(_ samples: [Int16], sampleRate: Double, channels: Int) throws -> [Float] {
        let frames = samples.count / channels
        guard frames > 0 else { return [] }
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                        channels: AVAudioChannelCount(channels), interleaved: true),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asrRate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt),
              let input = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(frames)) else {
            throw ResampleError.converter
        }
        if channels > 1 { conv.downmix = true }
        input.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { src in
            input.int16ChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        var out: [Float] = []
        out.reserveCapacity(Int(Double(frames) * asrRate / sampleRate) + 1_024)
        var fed = false
        while true {
            guard let buf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 16_384) else { throw ResampleError.converter }
            var err: NSError?
            let st = conv.convert(to: buf, error: &err) { _, status in
                if fed {
                    status.pointee = .endOfStream
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return input
            }
            if err != nil || st == .error { throw ResampleError.converter }
            out.append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
            if st == .endOfStream || (st == .inputRanDry && buf.frameLength == 0) { break }
        }
        return out
    }
}
```

`Sources/MeetNotesTranscription/EnergyGate.swift`:

```swift
import Foundation

/// 🔴 Bramka mowy per kanał przed ASR (W§1) — energetyczna, bez modelu: RMS
/// w dBFS z histerezą. Tak robi Wispr Flow (`rmsDbfs`, `silenceAccruedMs`,
/// `silenceQualifiedMs`, `silenceArmed`, rozdz. 15). Cisza nie trafia do modelu:
/// nie halucynuje (82% na milczącym mikrofonie, rozdz. 13) i nie kosztuje.
public struct EnergyGate: Sendable {
    public struct Config: Codable, Equatable, Sendable {
        public var thresholdDBFS: Double = -45
        /// Tyle głośności trzeba, żeby uznać początek mowy (odsiewa trzaski).
        public var attackSeconds: Double = 0.1
        /// Tyle ciszy trzeba, żeby uznać koniec mowy („cisza kwalifikowana").
        public var releaseSeconds: Double = 0.5
        /// Zapas z obu stron, żeby nie uciąć pierwszej i ostatniej głoski.
        public var paddingSeconds: Double = 0.2
        public init() {}
    }

    public static let frameSeconds = 0.02
    public let config: Config

    public init(_ config: Config = Config()) { self.config = config }

    /// Poziom każdej 20-milisekundowej ramki.
    public static func frameLevels(_ x: [Float], rate: Double) -> [Double] {
        let n = Int(rate * frameSeconds)
        return stride(from: 0, to: x.count, by: n).map { start in
            let end = min(start + n, x.count)
            var sum = 0.0
            for i in start..<end { sum += Double(x[i]) * Double(x[i]) }
            let rms = (sum / Double(end - start)).squareRoot()
            return rms > 0 ? max(-160, 20 * log10(rms)) : -160
        }
    }

    /// Zakresy próbek z mową.
    public func speechRegions(_ x: [Float], rate: Double) -> [Range<Int>] {
        let levels = Self.frameLevels(x, rate: rate)
        let frameLen = Int(rate * Self.frameSeconds)
        let attack = max(1, Int((config.attackSeconds / Self.frameSeconds).rounded()))
        let release = max(1, Int((config.releaseSeconds / Self.frameSeconds).rounded()))
        var regions: [Range<Int>] = []
        var inSpeech = false
        var loudRun = 0, quietRun = 0, start = 0
        for (i, l) in levels.enumerated() {
            let loud = l > config.thresholdDBFS
            if inSpeech {
                quietRun = loud ? 0 : quietRun + 1
                if quietRun >= release {
                    regions.append(start..<(i - quietRun + 1))
                    inSpeech = false
                    loudRun = 0
                }
            } else {
                loudRun = loud ? loudRun + 1 : 0
                if loudRun >= attack {
                    inSpeech = true
                    start = i - loudRun + 1
                    quietRun = 0
                }
            }
        }
        if inSpeech { regions.append(start..<(levels.count - quietRun)) }
        let pad = Int(config.paddingSeconds / Self.frameSeconds)
        var merged: [Range<Int>] = []
        for r in regions {
            let padded = max(0, r.lowerBound - pad)..<min(levels.count, r.upperBound + pad)
            if let last = merged.last, padded.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, padded.upperBound)
            } else {
                merged.append(padded)
            }
        }
        return merged.map { ($0.lowerBound * frameLen)..<min(x.count, $0.upperBound * frameLen) }
    }
}
```

`Sources/MeetNotesTranscription/ChunkPacker.swift`:

```swift
import Foundation

/// Fragment nagrania wklejony do okna.
public struct ChunkSegment: Codable, Equatable, Sendable {
    /// Zakres w próbkach ścieżki (16 kHz).
    public var sourceStart: Int
    public var sourceEnd: Int
    /// Początek w próbkach okna.
    public var chunkStart: Int

    public var length: Int { sourceEnd - sourceStart }
}

/// Jedno żądanie do ASR: fragmenty mowy sklejone przerwami ciszy.
public struct Chunk: Codable, Equatable, Sendable {
    public var index: Int
    public var segments: [ChunkSegment]
    public var length: Int

    /// Czas w oknie (s) → czas ścieżki (s). Czas w sztucznej przerwie trafia do
    /// najbliższej krawędzi fragmentu.
    public func sourceSeconds(chunkSeconds t: Double, rate: Double) -> Double {
        let p = Int((t * rate).rounded())
        var best = segments[0]
        var bestDist = Int.max
        for s in segments {
            if p >= s.chunkStart && p < s.chunkStart + s.length {
                return Double(s.sourceStart + (p - s.chunkStart)) / rate
            }
            let d = p < s.chunkStart ? s.chunkStart - p : p - (s.chunkStart + s.length)
            if d < bestDist { bestDist = d; best = s }
        }
        let clamped = min(max(p, best.chunkStart), best.chunkStart + best.length)
        return Double(best.sourceStart + (clamped - best.chunkStart)) / rate
    }

    public var sourceStartSeconds: Double { Double(segments.first?.sourceStart ?? 0) / Resampler.asrRate }
    public var sourceEndSeconds: Double { Double(segments.last?.sourceEnd ?? 0) / Resampler.asrRate }
}

/// Pakowanie fragmentów mowy w okna do limitu modelu. Dwa zmierzone ograniczenia
/// naraz: nie wysyłamy ciszy (P6), a okna są długie — „nie tnij audio na sekundy",
/// krótkie okna przy cichym tle produkują halucynacje (rozdz. 13).
/// Fragment dłuższy niż okno tnie się w najcichszej ramce z ostatnich sekund
/// przed limitem, nie w połowie słowa.
public struct ChunkPacker: Sendable {
    public var maxSeconds: Double
    public var gapSeconds: Double = 0.3
    public var splitSearchSeconds: Double = 5
    public var rate: Double = Resampler.asrRate

    public init(maxSeconds: Double) { self.maxSeconds = maxSeconds }

    public func pack(_ regions: [Range<Int>], samples x: [Float]) -> [Chunk] {
        let maxLen = Int(maxSeconds * rate)
        let gap = Int(gapSeconds * rate)
        var pieces: [Range<Int>] = []
        for r in regions { pieces += split(r, maxLen: maxLen, x: x) }

        var chunks: [Chunk] = []
        var current: [ChunkSegment] = []
        var used = 0
        for p in pieces {
            let need = (current.isEmpty ? 0 : gap) + p.count
            if !current.isEmpty && used + need > maxLen {
                chunks.append(Chunk(index: chunks.count, segments: current, length: used))
                current = []
                used = 0
            }
            let start = current.isEmpty ? 0 : used + gap
            current.append(ChunkSegment(sourceStart: p.lowerBound, sourceEnd: p.upperBound, chunkStart: start))
            used = start + p.count
        }
        if !current.isEmpty { chunks.append(Chunk(index: chunks.count, segments: current, length: used)) }
        return chunks
    }

    func split(_ r: Range<Int>, maxLen: Int, x: [Float]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = r.lowerBound
        let frame = Int(rate * EnergyGate.frameSeconds)
        while r.upperBound - start > maxLen {
            let searchFrom = start + maxLen - Int(splitSearchSeconds * rate)
            var cut = start + maxLen
            var quietest = Double.infinity
            var f = max(start + frame, searchFrom)
            while f + frame <= start + maxLen {
                var sum = 0.0
                for i in f..<(f + frame) { sum += Double(x[i]) * Double(x[i]) }
                if sum < quietest { quietest = sum; cut = f + frame / 2 }
                f += frame
            }
            out.append(start..<cut)
            start = cut
        }
        out.append(start..<r.upperBound)
        return out
    }
}
```

`Sources/MeetNotesTranscription/WAVEncoder.swift`:

```swift
import Foundation

/// WAV 16 kHz mono Int16 z fragmentów okna — tak wysyłamy audio do ASR.
public enum WAVEncoder {
    public static func encode(_ chunk: Chunk, samples x: [Float], rate: Double = Resampler.asrRate) -> Data {
        var pcm = [Int16](repeating: 0, count: chunk.length)
        for s in chunk.segments {
            for i in 0..<s.length {
                let v = max(-1, min(1, x[s.sourceStart + i]))
                pcm[s.chunkStart + i] = Int16((v * 32_767).rounded())
            }
        }
        return wav(pcm, rate: rate)
    }

    public static func wav(_ pcm: [Int16], rate: Double) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(pcm.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        pcm.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: pcm.count * 2)) }
        return d
    }
}
```

- [x] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 87/87 testów uruchomionych i zaliczonych.`

- [x] **Krok 5: Mutacja (P6).** W `EnergyGate.Config` zamień `public var thresholdDBFS: Double = -45` na `= -200`. `scripts/test.sh --filter pureSilenceProducesNoRegions` — oczekiwane: pada (cisza cyfrowa −160 dBFS jest „głośniejsza" niż próg). Przywróć; `87/87`.

- [x] **Krok 6: Commit.**

```bash
git add Sources/MeetNotesTranscription Tests/MeetNotesTranscriptionTests
git commit -m "Transkrypcja: bramka energetyczna i pakowanie mowy w dlugie okna" -m "Cisza nie idzie do modelu (P6), a okna sa dlugie - krotkie okna przy cichym tle halucynuja (rozdz. 13). Tablica segmentow przelicza czas okna na czas sciezki."
```

---

### Zadanie C2: Strażnik języka (P11)

Status: ✅ zweryfikowane (4 testy, w tym jeden sparametryzowany zdaniami z rozdz. 14), z jedną poprawką po recenzji (W4), sprawdzoną przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet): z listy angielskich słów funkcyjnych usunięte `"i"` — to też polskie „i”, więc zawyżało wynik angielski w polskim tekście. Trzy zdania z rozdz. 14 mają dość innych angielskich słów funkcyjnych, żeby test przeszedł bez niego.

**Pliki:**
- Utwórz: `Sources/MeetNotesTranscription/LanguageGuard.swift`
- Test: `Tests/MeetNotesTranscriptionTests/LanguageGuardTests.swift`

**Interfejsy:**
- Pobiera: `LanguageCode`, `ProbeClips.normalize` (plan B).
- Dostarcza: `LanguageGuard.mismatch(_ text: String, expected: LanguageCode) -> LanguageCode?` — język, na który wygląda tekst, gdy wyraźnie różny od oczekiwanego; inaczej `nil`.

- [x] **Krok 1: Test, który padnie.** Utwórz `Tests/MeetNotesTranscriptionTests/LanguageGuardTests.swift`:

```swift
import Testing
import MeetNotesProviders
@testable import MeetNotesTranscription

// Zdania z rozdz. 14: polskie spotkanie, a model zwrócił płynną angielszczyznę.
@Test(arguments: [
    "Mr. President, I am very happy to be here in the next few days. Thank you for your attention.",
    "I think there is a problem with the production of the products.",
    "The only thing that I can do is to take a look at the people who are not in the same boat.",
])
func confabulatedEnglishInPolishMeetingIsFlagged(_ text: String) {
    #expect(LanguageGuard.mismatch(text, expected: .polish) == .english)
}

@Test func realPolishIsNotFlagged() {
    #expect(LanguageGuard.mismatch("No, dobra. Słuchajcie, dzisiaj mamy spotkanie, by sobie przekazać wiedzę.", expected: .polish) == nil)
    #expect(LanguageGuard.mismatch("Chociaż mieliśmy wczoraj some things do omówienia", expected: .polish) == nil)
}

@Test func tooShortToJudge() {
    #expect(LanguageGuard.mismatch("Thank you", expected: .polish) == nil)
}

@Test func unsupportedLanguageStaysSilent() throws {
    #expect(LanguageGuard.mismatch("the and is to of you that it", expected: try LanguageCode("de")) == nil)
}
```

- [x] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter LanguageGuard` — oczekiwane: kod `1`, `cannot find 'LanguageGuard' in scope`.

- [x] **Krok 3: Implementacja.** `Sources/MeetNotesTranscription/LanguageGuard.swift`:

```swift
import Foundation
import MeetNotesProviders

/// 🔴 Strażnik języka na wyjściu (spec fazy 1, §1.5, P11). Dla modeli, które same
/// wybierają język, to jedyna obrona przed konfabulacją z rozdz. 14: fragment,
/// który w presecie polskim czyta się jak angielski, zostaje oznaczony i nie
/// trafia do notatki jako fakt.
///
/// Heurystyka ze słów funkcyjnych, w fazie 1 tylko dla pary polski/angielski.
/// Dla innych języków strażnik milczy — lepiej nie oznaczyć niż oznaczyć źle.
public enum LanguageGuard {
    static let polishStop: Set<String> = ["i", "w", "na", "nie", "się", "to", "że", "jest", "z", "do", "jak", "ale",
                                          "co", "tak", "po", "o", "czy", "mamy", "jestem", "no", "tu", "już", "być",
                                          "od", "za", "dla", "ten", "ta", "te", "sobie", "tym", "tego", "przez", "są"]
    static let englishStop: Set<String> = ["the", "and", "is", "to", "of", "you", "that", "it", "in", "for", "am",
                                           "are", "be", "this", "we", "with", "have", "not", "on", "at", "will", "can",
                                           "there", "here", "what", "very", "so", "do", "my", "your", "a", "an"]
    static let polishLetters = Set("ąćęłńóśźż")

    /// Język, na który wygląda tekst, jeśli wyraźnie różny od oczekiwanego; inaczej `nil`.
    public static func mismatch(_ text: String, expected: LanguageCode) -> LanguageCode? {
        guard expected == .polish || expected == .english else { return nil }
        let words = ProbeClips.normalize(text).split(separator: " ").map(String.init)
        guard words.count >= 4 else { return nil } // za krótko, żeby orzekać
        let pl = words.filter { polishStop.contains($0) }.count
        let en = words.filter { englishStop.contains($0) }.count
        let hasPolishLetters = text.lowercased().contains { polishLetters.contains($0) }
        switch expected {
        case .polish:
            return !hasPolishLetters && en >= 2 && en > pl * 2 ? .english : nil
        case .english:
            return hasPolishLetters && pl >= 2 && pl > en ? .polish : nil
        default:
            return nil
        }
    }
}
```

- [x] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 91/91 testów uruchomionych i zaliczonych.` Test sparametryzowany liczy się jako jeden test.

- [x] **Krok 5: Commit.**

```bash
git add Sources/MeetNotesTranscription Tests/MeetNotesTranscriptionTests
git commit -m "Transkrypcja: straznik jezyka na wyjsciu" -m "Jedyna obrona przed konfabulacja z rozdz. 14 tam, gdzie model sam wybiera jezyk. Tylko para pl/en; dla innych jezykow milczy."
```

---

### Zadanie C3: Model transkryptu, scalanie, wykonawca przebiegu (P4–P6, P11, P12)

Status: ✅ zweryfikowane (7 testów) + jeden test i parametr `systemChannels` w `makeSession` dopisane po recenzji (W5), sprawdzone przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet). `SessionFixtures.swift` to reszta zweryfikowanego `Helpers.swift` ze spike'a — od `makeSession` do końca — z jego oryginalnymi importami.

**Pliki:**
- Utwórz: `Sources/MeetNotesTranscription/Transcript.swift`, `Merger.swift`, `TranscriptionRunner.swift`
- Test: `Tests/MeetNotesTranscriptionTests/SessionFixtures.swift`, `Tests/MeetNotesTranscriptionTests/RunnerTests.swift`

**Interfejsy:**
- Pobiera: C1, C2; `SessionDirectory`, `SessionSummary`, `CAFReader` (plan A); `OpenAICompatibleClient`, `Preset`, `Provider`, `ProbeResult`, `JSONFile` (plan B).
- Dostarcza: `Speaker` (`.me`, `.them`), `Word(text:start:end:)` (sekundy osi sesji), `Utterance` (`speaker`, `start`, `end`, `text`, `words`, `approximateTiming`, `languageMismatch`, `excludedFromNotes`), `ChunkFailure`, `Transcript` (`utterances`, `failedChunks`, `languageFlagCount`). `RunSnapshot(preset:provider:probe:dictionaryVersion:) throws` — migawka, nie odwołanie. `RunMetadata`. `ChunkResult`, `SessionClock(summary:)` z `sessionSeconds(track:trackSeconds:)`, `Merger.merge(_:speakers:clock:language:failures:)`. `TranscriptionProgress` (`done`, `total`, `fraction`), `RunDirectory(session:runID:)`, `TranscriptionRunner(session:runID:snapshot:client:maxChunkSeconds: = 59, gate:)` z `run(progress:) async throws -> Transcript`.

- [x] **Krok 1: Testy, które padną.**

`Tests/MeetNotesTranscriptionTests/SessionFixtures.swift`:

```swift
import Foundation
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
@testable import MeetNotesTranscription

/// Prawdziwa sesja z dysku, zrobiona rejestratorem z próbek.
func makeSession(system: [Int16]? = nil, systemRate: Double = 16_000, systemChannels: Int = 1, mic: [Int16]? = nil,
                 micTrack: String = "mic_raw", micOffset: Double = 0) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mn-tr-\(UUID().uuidString)")
    var sources: [any AudioSource] = []
    if let system {
        sources.append(FileSource(trackID: "system", samples: system, sampleRate: systemRate, channels: systemChannels,
                                  startHostTime: 1_000_000_000, timebase: ns, chunkFrames: 1_600))
    }
    if let mic {
        sources.append(FileSource(trackID: micTrack, samples: mic, sampleRate: 16_000, channels: 1,
                                  startHostTime: 1_000_000_000 + ns.ticks(seconds: micOffset), timebase: ns, chunkFrames: 1_600))
    }
    try SessionRecorder(directory: dir, sources: sources, conditions: [], clock: ManualHostClock(), timebase: ns,
                        zeroWatch: [:]).start()
    return dir
}

/// ASR z ręki, który naprawdę „słucha": dekoduje WAV i zwraca jedno słowo na
/// każdy odcinek dźwięku, z czasem w oknie. Liczy wywołania.
final class ListeningASR: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests = 0
    let word: String
    let failWhen: @Sendable (Int) -> Bool

    init(word: String = "słowo", failWhen: @escaping @Sendable (Int) -> Bool = { _ in false }) {
        self.word = word
        self.failWhen = failWhen
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let n = lock.withLock { requests += 1; return requests }
        let url = request.url!
        if failWhen(n) {
            return (Data("{\"error\":\"boom\"}".utf8), HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let wav = Data(base64Encoded: (body["input_audio"] as! [String: Any])["data"] as! String)!
        let pcm = wav.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        var words: [[String: Any]] = []
        var runStart: Int?
        for (i, v) in pcm.enumerated() {
            if v != 0, runStart == nil { runStart = i }
            let endOfRun = runStart != nil && (i == pcm.count - 1 || (pcm[i] == 0 && pcm[min(i + 1, pcm.count - 1)] == 0 && isQuiet(pcm, from: i)))
            if endOfRun, let s = runStart {
                if i - s > 1_600 { words.append(["word": word, "start": Double(s) / 16_000, "end": Double(i) / 16_000]) }
                runStart = nil
            }
        }
        let text = words.map { $0["word"] as! String }.joined(separator: " ")
        let data = try JSONSerialization.data(withJSONObject: ["text": text, "words": words])
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func isQuiet(_ pcm: [Int16], from i: Int) -> Bool {
        let end = min(pcm.count, i + 160)
        return pcm[i..<end].allSatisfy { $0 == 0 }
    }
}

func snapshot(language: LanguageCode = .polish) throws -> RunSnapshot {
    let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    let preset = Preset(name: "Polish", language: language, asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2"))
    return try RunSnapshot(preset: preset, provider: provider, probe: nil)
}

func client(_ http: any HTTPClient) -> OpenAICompatibleClient {
    OpenAICompatibleClient(provider: Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!), key: "k", http: http)
}
```

`Tests/MeetNotesTranscriptionTests/RunnerTests.swift`:

```swift
import Foundation
import Testing
import MeetNotesProviders
import MeetNotesSessionFormat
@testable import MeetNotesTranscription

@Test func wordsLandOnTheSessionTimelineWhereTheSoundWas() async throws {
    // P4 w skali 3 minut: bramka, pakowanie, WAV, przeliczenie czasu i kotwice naraz.
    let (samples, starts) = burstTrack(seconds: 180, rate: 16_000)
    let dir = try makeSession(system: samples)
    let asr = ListeningASR()
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr)).run()
    let words = t.utterances.flatMap(\.words)
    #expect(words.count == starts.count)
    for (w, s) in zip(words.sorted { $0.start < $1.start }, starts) {
        #expect(abs(w.start - s) < 0.03, "słowo w \(w.start) s, dźwięk w \(s) s")
    }
    #expect(asr.requests == 1) // 18 fragmentów po 2,4 s mieści się w jednym oknie
}

@Test func speakersComeFromChannelsWithMicOffsetApplied() async throws {
    // Mikrofon rusza 165 ms po systemie (zmierzone u Narady) — słowa „ja" muszą to uwzględnić.
    let sys = silence(seconds: 5, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 13, rate: 16_000)
    let mic = silence(seconds: 12, rate: 16_000) + tone(seconds: 2, rate: 16_000) + silence(seconds: 6, rate: 16_000)
    let dir = try makeSession(system: sys, mic: mic, micOffset: 0.165)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    let them = try #require(t.utterances.first { $0.speaker == .them })
    let me = try #require(t.utterances.first { $0.speaker == .me })
    #expect(abs(them.start - 5.0) < 0.03)
    #expect(abs(me.start - 12.165) < 0.03)
}

@Test func echoCancelledMicIsPreferredOverRaw() throws {
    let sum = SessionSummary(startedHostTime: 0, timebase: ns, wallClock: nil, endReason: nil, crashed: false, tracks: [
        .init(id: "system", sampleRate: 48_000, channels: 2, deviceUIDs: [], gaps: [], clock: []),
        .init(id: "mic_raw", sampleRate: 16_000, channels: 1, deviceUIDs: [], gaps: [], clock: []),
        .init(id: "mic_aec", sampleRate: 16_000, channels: 1, deviceUIDs: [], gaps: [], clock: []),
    ])
    #expect(TranscriptionRunner.tracks(in: sum).map(\.id) == ["system", "mic_aec"])
}

@Test func silentSessionSendsNothing() async throws {
    // P6 na całym potoku.
    let dir = try makeSession(system: silence(seconds: 60, rate: 16_000), mic: silence(seconds: 60, rate: 16_000))
    let asr = ListeningASR()
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(asr)).run()
    #expect(asr.requests == 0)
    #expect(t.utterances.isEmpty)
}

@Test func interruptedRunResumesWithoutPayingAgain() async throws {
    // P5: pierwszy przebieg pada na 2. i dalszych oknach; drugi wysyła tylko brakujące.
    let (samples, _) = burstTrack(seconds: 600, rate: 16_000) // 60 fragmentów → kilka okien
    let dir = try makeSession(system: samples)
    let first = ListeningASR(failWhen: { $0 >= 2 })
    let t1 = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(first)).run()
    let total = first.requests
    #expect(total >= 3)
    #expect(t1.failedChunks.count == total - 1) // luki jawne, nie cisza udająca treść
    let second = ListeningASR()
    let t2 = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(second)).run()
    #expect(second.requests == total - 1)
    #expect(t2.failedChunks.isEmpty)
}

@Test func progressReachesOneAndMetadataCarriesTheSnapshot() async throws {
    let (samples, _) = burstTrack(seconds: 300, rate: 16_000)
    let dir = try makeSession(system: samples)
    let seen = Recorder()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR()))
        .run { seen.add($0.fraction) }
    #expect(seen.values.first == 0)
    #expect(seen.values.last == 1)
    let meta = try JSONFile.load(RunMetadata?.self, from: RunDirectory(session: dir, runID: "r1").metadata, default: nil)
    #expect(meta?.snapshot.model == "microsoft/mai-transcribe-2")
    #expect(meta?.snapshot.language == .polish)
}

@Test func confabulatedEnglishIsFlaggedAndExcludedFromNotes() async throws {
    // P11: preset polski, ASR zwraca płynną angielszczyznę.
    struct EnglishASR: HTTPClient {
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let d = try JSONSerialization.data(withJSONObject: ["text": "I think there is a problem with the production of the products."])
            return (d, HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000) + tone(seconds: 3, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(EnglishASR())).run()
    let u = try #require(t.utterances.first)
    #expect(u.languageMismatch == .english)
    #expect(u.excludedFromNotes)
    #expect(u.approximateTiming) // brak słów z czasem → czas całego okna
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [Double] = []
    func add(_ x: Double) { lock.withLock { v.append(x) } }
    var values: [Double] { lock.withLock { v } }
}
```

Następnie ⚠️ **dopisz na końcu `RunnerTests.swift`** (po recenzji, W5 — prawdziwy tap to 48 kHz stereo, a pozostałe testy potoku używają 16 kHz mono):

```swift
@Test func fullPipelineHandlesA48kStereoSystemTrack() async throws {
    let (mono, starts) = burstTrack(seconds: 60, rate: 48_000)
    let stereo = mono.flatMap { [$0, $0] }
    let dir = try makeSession(system: stereo, systemRate: 48_000, systemChannels: 2)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    let words = t.utterances.flatMap(\.words).sorted { $0.start < $1.start }
    #expect(words.count == starts.count)
    for (w, s) in zip(words, starts) {
        // 50 ms zamiast 30: filtr przepróbkowania rozmywa krawędzie tonu o kilka ms.
        #expect(abs(w.start - s) < 0.05, "słowo w \(w.start) s, dźwięk w \(s) s")
    }
}
```

- [x] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesTranscriptionTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `RunSnapshot`, `TranscriptionRunner`, `RunDirectory`, `RunMetadata`.

- [x] **Krok 3: Implementacja.**

`Sources/MeetNotesTranscription/Transcript.swift`:

```swift
import Foundation
import MeetNotesProviders

/// Podział „ja / oni" za darmo, z kanałów, bez modelu (rozdz. 8).
public enum Speaker: String, Codable, Sendable {
    case me
    case them
}

public struct Word: Codable, Equatable, Sendable {
    public var text: String
    /// Sekundy na osi sesji (0 = pierwsza próbka ścieżki systemowej).
    public var start: Double
    public var end: Double
}

public struct Utterance: Codable, Equatable, Sendable {
    public var speaker: Speaker
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [Word]
    /// Kształt czatowy nie daje znaczników słów: czas to zakres całego okna.
    public var approximateTiming: Bool
    /// Wynik strażnika języka (P11).
    public var languageMismatch: LanguageCode?

    /// Oznaczona wypowiedź nie trafia do notatki jako fakt.
    public var excludedFromNotes: Bool { languageMismatch != nil }
}

public struct ChunkFailure: Codable, Equatable, Sendable {
    public var track: String
    public var index: Int
    public var start: Double
    public var end: Double
    public var error: String
}

public struct Transcript: Codable, Equatable, Sendable {
    public var utterances: [Utterance]
    /// Jawne luki: okna, których nie udało się przetranskrybować (§6.4).
    public var failedChunks: [ChunkFailure]

    public var languageFlagCount: Int { utterances.filter(\.excludedFromNotes).count }
}

/// Migawka presetu w chwili przebiegu — nie odwołanie (spec fazy 1, §8, P12).
public struct RunSnapshot: Codable, Equatable, Sendable {
    public var presetID: UUID
    public var presetName: String
    public var providerID: UUID
    public var providerName: String
    public var providerBaseURL: URL
    public var model: String
    public var shape: ASRShape
    public var language: LanguageCode
    public var languageHandling: LanguageHandling
    public var dictionaryVersion: String

    public init(preset: Preset, provider: Provider, probe: ProbeResult?, dictionaryVersion: String = "none") throws {
        try preset.validate()
        guard let asr = preset.asr, let language = preset.language else { throw PresetError.missingASR }
        presetID = preset.id
        presetName = preset.name
        providerID = provider.id
        providerName = provider.name
        providerBaseURL = provider.baseURL
        model = asr.model
        shape = probe?.shape ?? .audioTranscriptions
        self.language = language
        languageHandling = probe?.languageHandling ?? .unknown
        self.dictionaryVersion = dictionaryVersion
    }
}

public struct RunMetadata: Codable, Equatable, Sendable {
    public var runID: String
    public var snapshot: RunSnapshot
    public var startedAt: Date
    public var finishedAt: Date?
    public var chunkCount: Int
    public var requestCount: Int
    public var audioSecondsSent: Double
    public var failedChunkCount: Int
    public var languageFlagCount: Int
}
```

`Sources/MeetNotesTranscription/Merger.swift`:

```swift
import Foundation
import MeetNotesProviders
import MeetNotesSessionFormat

/// Wynik jednego okna, zapisany na dysk — podstawa wznawiania (P5).
public struct ChunkResult: Codable, Equatable, Sendable {
    public var track: String
    public var chunk: Chunk
    public var result: TranscriptionResult
}

/// Czas ścieżki → oś sesji przez kotwice zegara (T8), a nie nominalną częstotliwość.
public struct SessionClock: Sendable {
    public let summary: SessionSummary

    public init(summary: SessionSummary) { self.summary = summary }

    public func sessionSeconds(track: String, trackSeconds: Double) -> Double {
        guard let t = summary.tracks.first(where: { $0.id == track }) else { return trackSeconds }
        let frame = Int((trackSeconds * t.sampleRate).rounded())
        let anchor = summary.tracks.first(where: { $0.id == SessionSummary.timelineTrackID })?.firstSampleHostTime
            ?? summary.startedHostTime
        if let host = summary.hostTime(track: track, frame: frame) {
            return summary.timebase.secondsBetween(host, anchor)
        }
        return (t.offsetSeconds ?? 0) + trackSeconds
    }
}

public enum Merger {
    /// Słowa jednego mówcy z przerwą krótszą niż ta są jedną wypowiedzią.
    public static let utteranceGap = 1.2

    public static func merge(_ results: [ChunkResult], speakers: [String: Speaker], clock: SessionClock,
                             language: LanguageCode, failures: [ChunkFailure] = []) -> Transcript {
        var utterances: [Utterance] = []
        for track in Set(results.map(\.track)).sorted() {
            let speaker = speakers[track] ?? .them
            var words: [Word] = []
            for r in results.filter({ $0.track == track }).sorted(by: { $0.chunk.index < $1.chunk.index }) {
                if let ws = r.result.words, !ws.isEmpty {
                    for w in ws {
                        let s = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceSeconds(chunkSeconds: w.start, rate: Resampler.asrRate))
                        let e = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceSeconds(chunkSeconds: w.end, rate: Resampler.asrRate))
                        words.append(Word(text: w.word.trimmingCharacters(in: .whitespaces), start: s, end: max(s, e)))
                    }
                } else if !r.result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let s = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceStartSeconds)
                    let e = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceEndSeconds)
                    utterances.append(Utterance(speaker: speaker, start: s, end: e, text: r.result.text,
                                                words: [], approximateTiming: true, languageMismatch: nil))
                }
            }
            words.sort { $0.start < $1.start }
            var group: [Word] = []
            func flush() {
                guard let f = group.first, let l = group.last else { return }
                utterances.append(Utterance(speaker: speaker, start: f.start, end: l.end,
                                            text: group.map(\.text).joined(separator: " "), words: group,
                                            approximateTiming: false, languageMismatch: nil))
                group = []
            }
            for w in words {
                if let last = group.last, w.start - last.end > utteranceGap { flush() }
                group.append(w)
            }
            flush()
        }
        for i in utterances.indices {
            utterances[i].languageMismatch = LanguageGuard.mismatch(utterances[i].text, expected: language)
        }
        utterances.sort { $0.start < $1.start }
        return Transcript(utterances: utterances, failedChunks: failures)
    }
}
```

`Sources/MeetNotesTranscription/TranscriptionRunner.swift`:

```swift
import Foundation
import MeetNotesProviders
import MeetNotesSessionFormat

public struct TranscriptionProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    public var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }
}

/// Katalog przebiegu: `<sesja>/runs/<runID>/`. Przebiegi leżą obok siebie (§8).
public struct RunDirectory: Sendable {
    public let url: URL
    public init(session: URL, runID: String) { url = session.appendingPathComponent("runs").appendingPathComponent(runID) }
    public var metadata: URL { url.appendingPathComponent("run.json") }
    public var transcript: URL { url.appendingPathComponent("transcript.json") }
    public func chunk(_ track: String, _ i: Int) -> URL { url.appendingPathComponent("chunks/\(track)-\(i).json") }
}

/// Potok: ścieżka → 16 kHz mono → bramka → pakowanie → okna do ASR → scalenie.
/// Wznawialny: gotowe okna leżą na dysku i nie są wysyłane ponownie (P5).
/// Nieudane okno nie przerywa przebiegu — zostaje jawną luką (§6.4).
public struct TranscriptionRunner: Sendable {
    public let session: SessionDirectory
    public let runID: String
    public let snapshot: RunSnapshot
    public let client: OpenAICompatibleClient
    public let maxChunkSeconds: Double
    public let gate: EnergyGate

    public init(session: URL, runID: String, snapshot: RunSnapshot, client: OpenAICompatibleClient,
                maxChunkSeconds: Double = 59, gate: EnergyGate = EnergyGate()) {
        self.session = SessionDirectory(url: session)
        self.runID = runID
        self.snapshot = snapshot
        self.client = client
        self.maxChunkSeconds = maxChunkSeconds
        self.gate = gate
    }

    /// „Oni" = ścieżka systemowa; „ja" = mikrofon po AEC, a gdy go brak — surowy.
    static func tracks(in summary: SessionSummary) -> [(id: String, speaker: Speaker)] {
        let ids = Set(summary.tracks.filter { $0.channels > 0 }.map(\.id))
        var out: [(String, Speaker)] = []
        if ids.contains("system") { out.append(("system", .them)) }
        if ids.contains("mic_aec") { out.append(("mic_aec", .me)) } else if ids.contains("mic_raw") { out.append(("mic_raw", .me)) }
        return out
    }

    public func run(progress: @Sendable (TranscriptionProgress) -> Void = { _ in }) async throws -> Transcript {
        let summary = try session.summarize()
        let dir = RunDirectory(session: session.url, runID: runID)
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("chunks"), withIntermediateDirectories: true)
        let started = Date()

        var plan: [(track: String, chunk: Chunk, samples: [Float])] = []
        var speakers: [String: Speaker] = [:]
        for (id, speaker) in Self.tracks(in: summary) {
            speakers[id] = speaker
            let caf = try CAFReader(url: session.trackURL(id))
            let x = try Resampler.toASR(caf.samples, sampleRate: caf.sampleRate, channels: caf.channels)
            let chunks = ChunkPacker(maxSeconds: maxChunkSeconds).pack(gate.speechRegions(x, rate: Resampler.asrRate), samples: x)
            for c in chunks { plan.append((id, c, x)) }
        }

        var results: [ChunkResult] = []
        var failures: [ChunkFailure] = []
        var requests = 0
        var secondsSent = 0.0
        progress(TranscriptionProgress(done: 0, total: plan.count))
        for (n, item) in plan.enumerated() {
            let file = dir.chunk(item.track, item.chunk.index)
            if let saved = try? JSONFile.load(ChunkResult?.self, from: file, default: nil), saved.chunk == item.chunk {
                results.append(saved)
            } else {
                do {
                    requests += 1
                    secondsSent += Double(item.chunk.length) / Resampler.asrRate
                    let r = try await client.transcribe(wav: WAVEncoder.encode(item.chunk, samples: item.samples),
                                                        model: snapshot.model, language: snapshot.language, shape: snapshot.shape)
                    let cr = ChunkResult(track: item.track, chunk: item.chunk, result: r)
                    try JSONFile.save(cr, to: file)
                    results.append(cr)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append(ChunkFailure(track: item.track, index: item.chunk.index, start: item.chunk.sourceStartSeconds,
                                                 end: item.chunk.sourceEndSeconds, error: "\(error)"))
                }
            }
            try Task.checkCancellation()
            progress(TranscriptionProgress(done: n + 1, total: plan.count))
        }

        let transcript = Merger.merge(results, speakers: speakers, clock: SessionClock(summary: summary),
                                      language: snapshot.language, failures: failures)
        try JSONFile.save(transcript, to: dir.transcript)
        try JSONFile.save(RunMetadata(runID: runID, snapshot: snapshot, startedAt: started, finishedAt: Date(),
                                      chunkCount: plan.count, requestCount: requests, audioSecondsSent: secondsSent,
                                      failedChunkCount: failures.count, languageFlagCount: transcript.languageFlagCount),
                          to: dir.metadata)
        return transcript
    }
}
```

- [x] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 99/99 testów uruchomionych i zaliczonych.` (91 z poprzednich zadań, 7 testów przebiegu ze spike'a i test 48 kHz stereo). Jeśli pada tylko nowy test, a pozostałe przechodzą, to wada nowego testu albo realny problem potoku z 48 kHz — rozstrzygnij, zanim przejdziesz dalej; tolerancji nie zwiększaj na ślepo.

- [x] **Krok 5: Mutacja (P5).** W `TranscriptionRunner.run` zamień `if let saved = try? JSONFile.load(ChunkResult?.self, from: file, default: nil), saved.chunk == item.chunk {` na `if false, let saved = try? JSONFile.load(ChunkResult?.self, from: file, default: nil), saved.chunk == item.chunk {`. `scripts/test.sh --filter interruptedRunResumesWithoutPayingAgain` — oczekiwane: pada (drugi przebieg płaci za wszystkie okna). Przywróć.

- [x] **Krok 6: Mutacja (P11).** W `Merger.merge` zamień `utterances[i].languageMismatch = LanguageGuard.mismatch(utterances[i].text, expected: language)` na `utterances[i].languageMismatch = nil`. `scripts/test.sh --filter confabulatedEnglishIsFlaggedAndExcludedFromNotes` — oczekiwane: pada. Przywróć; `99/99`.

- [x] **Krok 7: Commit.**

```bash
git add Sources/MeetNotesTranscription Tests/MeetNotesTranscriptionTests
git commit -m "Transkrypcja: scalanie po znacznikach slow, wznawialny wykonawca" -m "Ja/oni z kanalow, czas slow przez kotwice zegara na osi sesji, nieudane okna jako jawne luki, gotowe okna nie wysylane ponownie. Przebieg zapisuje migawke presetu."
```

---

### Zadanie C4: CLI — transkrypcja i sesja z pliku testowego

Status: ✅ zweryfikowane (109 testów) — kompilacja i dym w S12 (2026-10-12, Opus); przebiegi wznowienia przez CLI (te same parametry → exit 0; inny model/język → `inputMismatch`) wykonane w checku S12 i powtórzone przez orkiestratora (dowód: `reports/S12.md`). Wcześniejsza wersja (2026-09-25, kopia spike'a, Sonnet): pełny CLI skompilowany dymnie, bramka `--language` działa; `transcribe` słowo w słowo z `CLI.swift` ze spike'a; `session-from-file` nowe — złożone z `readAnyAudio` (A9), `FileSource` i `SessionRecorder` (A6).

Po co `session-from-file`: spec fazy 1 §1.0 odrzuca import plików jako funkcję produktu, ale zostawia plik jako materiał testowy. Bez tego polecenia korpus z rozdz. 13, 14 i 17 (nagrania z innych aplikacji) nie da się przepuścić przez potok, a P4 i porównanie jakości polskiego nie mają punktu odniesienia. Polecenie jest tylko w CLI; w aplikacji go nie ma.

**Pliki:**
- Zmień: `Sources/meetnotes-cli/CLI.swift`

**Interfejsy:**
- Pobiera: `TranscriptionRunner`, `RunSnapshot` (C3); `CLI.client` (B4); `CLI.readAnyAudio`, `CLI.summarize` (A9).
- Dostarcza: `meetnotes-cli transcribe <katalog> <baseURL> <model> --language pl [--shape audioTranscriptions] [--run ID]`, `session-from-file <plik audio> <katalog>`.

- [x] **Krok 1: Import.** Pod `import MeetNotesSessionFormat` dopisz `import MeetNotesTranscription`.

- [x] **Krok 2: Pomoc.** W `usage`, pod linią `probe <baseURL> …`, dopisz:

```text
      transcribe <katalog> <baseURL> <model> --language pl [--shape audioTranscriptions] [--run ID]
      session-from-file <plik audio> <katalog>                     TYLKO TESTY: sesja z pliku (korpus)
```

- [x] **Krok 3: Polecenia.** W `switch cmd`, pod `case "probe": …`, dopisz:

```swift
            case "transcribe": try await transcribe(args)
            case "session-from-file": try await sessionFromFile(args)
```

- [x] **Krok 4: Funkcje.** Przed ostatnim `}` struktury `CLI` dopisz:

```swift
    static func transcribe(_ args: [String]) async throws {
        let dir = URL(fileURLWithPath: try positional(args, 0))
        let c = try client(try positional(args, 1))
        guard let langRaw = option(args, "--language") else {
            FileHandle.standardError.write(Data("--language jest obowiązkowe (nigdy auto)\n".utf8)); exit(64)
        }
        let preset = Preset(name: "cli", language: try LanguageCode(langRaw),
                            asr: RoleAssignment(providerID: c.provider.id, model: try positional(args, 2)))
        // Opcja bez wartości to błąd użycia, nie cicha wartość domyślna (S3-3, check S12 #4).
        if let bad = ["--shape", "--run"].first(where: { args.contains($0) && (option(args, $0)?.hasPrefix("--") ?? true) }) {
            FileHandle.standardError.write(Data("\(bad) wymaga wartości\n".utf8)); exit(64)
        }
        if let s = option(args, "--shape"), s != ASRShape.audioTranscriptions.rawValue {
            FileHandle.standardError.write(Data("--shape \(s): w transcribe dozwolone tylko audioTranscriptions\n".utf8)); exit(64)
        }
        let shape = ASRShape.audioTranscriptions
        let probe = ProbeResult(providerID: c.provider.id, model: try positional(args, 2), role: .asr, works: true,
                                shape: shape, languageHandling: .unknown)
        let runID = option(args, "--run") ?? ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") // E3: runID bez ':'
        print("runID: \(runID)")
        var snapshot = try RunSnapshot(preset: preset, provider: c.provider, probe: probe)
        // Wznowienie (check S11 #2): CLI tworzy preset i dostawcę z nowymi UUID przy każdym uruchomieniu,
        // więc przy tych samych parametrach bierzemy migawkę z pierwszego przebiegu. Inny model, język,
        // adres albo kształt → runner rzuci inputMismatch, tak jak powinien.
        if RunDirectory.isValid(runID: runID),
           let saved = try JSONFile.load(RunInput?.self, from: RunDirectory(session: dir, runID: runID).input, default: nil),
           (saved.snapshot.model, saved.snapshot.language, saved.snapshot.providerBaseURL, saved.snapshot.shape)
               == (snapshot.model, snapshot.language, snapshot.providerBaseURL, snapshot.shape) {
            snapshot = saved.snapshot
        }
        let t = try await TranscriptionRunner(session: dir, runID: runID, snapshot: snapshot, client: c).run { p in print(String(format: "\r%3.0f%%", p.fraction * 100), terminator: "") }
        print()
        for u in t.utterances {
            let flag = u.languageMismatch.map { " [JĘZYK: \($0)]" } ?? ""
            print(String(format: "[%7.1f] %@: ", u.start, u.speaker == .me ? "Me" : "Them") + u.text + flag)
        }
        if !t.failedChunks.isEmpty { print("nieudanych okien: \(t.failedChunks.count)") }
    }

    /// Tylko do testów (spec fazy 1, §1.0): sesja z istniejącego pliku, np. z korpusu
    /// z rozdz. 13, 14 i 17. Import plików nie jest funkcją produktu.
    static func sessionFromFile(_ args: [String]) async throws {
        let src = try readAnyAudio(URL(fileURLWithPath: try positional(args, 0)))
        let dir = URL(fileURLWithPath: try positional(args, 1))
        let tb = Timebase.current
        let source = FileSource(trackID: "system", samples: src.samples, sampleRate: src.rate, channels: src.channels,
                                startHostTime: mach_absolute_time(), timebase: tb, chunkFrames: 4_800)
        try SessionRecorder(directory: dir, sources: [source], conditions: [], timebase: tb, zeroWatch: [:]).start()
        try summarize([dir.path])
    }
```

- [x] **Krok 5: Zbuduj.** `swift build --product meetnotes-cli` — oczekiwane: `Build complete!`.

- [x] **Krok 6: Bramka „nigdy auto" w CLI.** `swift run meetnotes-cli transcribe /tmp/x https://openrouter.ai/api/v1 m` — oczekiwane: `--language jest obowiązkowe (nigdy auto)` i kod 64. Z `--language auto` — oczekiwane: `błąd: autoIsForbidden` i kod 1.

- [x] **Krok 7: Sesja z pliku, bez sieci.** `say -v Zosia -o /tmp/mn-pl.aiff "Dzień dobry, zaczynamy spotkanie."`, potem `swift run meetnotes-cli session-from-file /tmp/mn-pl.aiff /tmp/mn-fromfile` — oczekiwane: `koniec: endOfInput` i ścieżka `system` z ramkami > 0.

- [x] **Krok 8: Pełne testy.** `scripts/test.sh` — oczekiwane: `109/109` (po E3 i E5).

- [x] **Krok 9: Commit.**

```bash
git add Sources/meetnotes-cli
git commit -m "CLI: transcribe i session-from-file" -m "session-from-file tylko do testow na korpusie - import plikow nie jest funkcja produktu (spec fazy 1, 1.0)."
```

---

### Zadanie C5: Transkrypcja na żywo i korpus (P4, O1)

Status: ⏳ częściowo wykonane (2026-10-12, S13): kroki 1–3 ✅ — świeże nagranie 10,6 min zamiast A10 (decyzja użytkownika), run `2026-10-12T12-51-35Z` 24/24 okien / 0 nieudanych, skok w czasie 3/3, wznowienie P5 (`requestCount` 17/24); raport `reports/S13.md`, spike `spikes/2026-09-24-c5-transkrypcja-na-zywo.md`. Krok 4 pominięty (brak plików korpusu). Kroki 5–6 → **S13b** (najbliższe długie spotkanie). Wymaga klucza OpenRoutera użytkownika (bramka G3 zaliczona w B5). Koszt: MAI-Transcribe-2 to 0,10 USD za godzinę audio, a wysyłana jest tylko mowa.

**Pliki:**
- Utwórz: `docs/superpowers/spikes/2026-09-24-c5-transkrypcja-na-zywo.md`

- [x] **Krok 1: Sesja z A10.** `B=$(swift build -c release --show-bin-path)/meetnotes-cli` (po `swift build -c release --product meetnotes-cli`). `$B transcribe /tmp/mn-s2 https://openrouter.ai/api/v1 microsoft/mai-transcribe-2 --language pl` — oczekiwane: postęp do 100%, wypowiedzi „Them" i „Me" w kolejności czasu. W `/tmp/mn-s2/runs/<id>/run.json`: `requestCount`, `audioSecondsSent` mniejsze niż długość sesji (cisza nie poszła).

- [x] **Krok 2: Skok w czasie.** Dla trzech wypowiedzi z wyniku: `afplay` nie przewija, więc otwórz `/tmp/mn-s2/system.caf` w QuickTime i sprawdź, że w podanej sekundzie słychać te słowa. Tolerancja: 0,5 s (granica „klikalnej linii czasu" z W§1).

- [x] **Krok 3: Wznowienie (P5) na żywo.** Uruchom transkrypcję z `--run p5` i przerwij Ctrl-C przy ~50%. Policz pliki w `runs/p5/chunks/` (przerwany przebieg nie zapisuje `run.json`, więc stan widać tylko tam). Uruchom ponownie z tym samym `--run p5` — liczniki w `run.json` dotyczą tylko bieżącego przebiegu, więc `requestCount` w nowym `run.json` ma być równy liczbie okien, których nie było w `runs/p5/chunks/`.

- [ ] **Krok 4: Korpus (O1).** Użytkownik wskazuje pliki z rozdz. 13 (spotkanie WFM, 26 min), 14 (spotkanie 10:48) i 17 (debata, ~15 min), jeśli nadal istnieją. Dla każdego: `$B session-from-file <plik> /tmp/mn-corpus-<n>` i `$B transcribe /tmp/mn-corpus-<n> … --language pl`. Zapisz liczbę słów, liczbę `[JĘZYK: en]` i porównaj z tabelą z rozdz. 13 (Narada 2901 słów, 1 obcojęzyczny wtręt). Brakujących plików nie nagrywaj ponownie w tym zadaniu — zanotuj brak. *(S13: pominięty — brak wskazanych plików.)*

- [ ] **Krok 5: P4 — 85 minut.** Jeśli jest plik ≥ 85 min (korpus albo A10 krok 7): pełna transkrypcja; oczekiwane: brak nakładek słów — `jq '[.utterances[].words[]] | sort_by(.start) | [range(1; length) as $i | select(.[$i].start < .[$i-1].end)] | length' <katalog>/runs/<id>/transcript.json` daje `0`. Deterministyczny odpowiednik z asercjami na granicach okien: test 85-minutowy w E3. *(→ S13b)*

- [ ] **Krok 6: Pamięć (recenzja R6).** Na najdłuższej dostępnej sesji (≥ 85 min, inaczej najdłuższej, jaka jest): `/usr/bin/time -l $B transcribe <katalog> https://openrouter.ai/api/v1 microsoft/mai-transcribe-2 --language pl --run mem 2>&1 | grep "maximum resident set size"`. Próg: **< 3 GB** (3 221 225 472 bajtów). Z kodu wynika szczyt ~2 GB dla ścieżki systemowej 85 min: ~979 MB `[Int16]` z `CAFReader`, kopia w buforze `AVAudioPCMBuffer` w `Resampler.toASR` i ~330 MB `[Float]` 16 kHz. **Ponad próg: STOP** i plan awaryjny — `Resampler.toASR` podaje konwerterowi plasterki po 16 384 ramki prosto z tablicy zamiast kopiować całą ścieżkę do jednego bufora, a `TranscriptionRunner` przepróbkowuje i pakuje ścieżki po kolei, zwalniając każdą przed następną. *(→ S13b)*

- [ ] **Krok 7: Zapisz wyniki i commit.**

```bash
git add docs/superpowers/spikes
git commit -m "Transkrypcja na zywo: sesja z A10, wznowienie, korpus, pamiec"
```
