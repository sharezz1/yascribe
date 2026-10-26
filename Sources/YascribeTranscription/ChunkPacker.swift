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

    /// Słowo [start, end] w czasie okna (s) → czas ścieżki (s), w obrębie JEDNEGO fragmentu (U1).
    /// Granica słowa wg ASR może wypaść w sztucznej przerwie, więc mapowanie początku i końca osobno
    /// rozciągałoby słowo przez wyciętą ciszę (do kilkudziesięciu sekund). Reguła: fragment słowa to ten,
    /// w którym zaczyna się jego początek, a początek w przerwie przechodzi na następny fragment (po ostatnim —
    /// na ostatni). Początek i koniec są przycinane do tego fragmentu: koniec poza nim → koniec fragmentu,
    /// koniec jeszcze w przerwie przed fragmentem → czas zero. Słowa w całości w jednym fragmencie bez zmian.
    public func sourceSpan(chunkStart: Double, chunkEnd: Double, rate: Double) -> (start: Double, end: Double) {
        let ps = Int((chunkStart * rate).rounded())
        let pe = Int((chunkEnd * rate).rounded())
        let seg = segments.first { ps < $0.chunkStart + $0.length } ?? segments[segments.count - 1]
        func map(_ p: Int) -> Double {
            Double(seg.sourceStart + min(max(p, seg.chunkStart), seg.chunkStart + seg.length) - seg.chunkStart) / rate
        }
        return (map(ps), map(pe))
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
