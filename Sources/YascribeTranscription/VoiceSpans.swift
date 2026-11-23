import Foundation

/// Mowa mówców na torze do odcisku głosu (TASK-117): tylko czyste części (bez nakładania się na innego mówcę).
public enum VoiceSpans {
    public struct Speech: Equatable, Sendable {
        /// Wszystkie czyste części — do progu 20 s.
        public var seconds: Double
        /// Części ≥ `minPiece`, od najdłuższej, łącznie ≤ `maxTotal` — wejście embeddingu, w czasie TORU.
        public var spans: [ClosedRange<Double>]
    }

    /// Krótsze kawałki dają szum zamiast głosu.
    public static let minPiece = 1.0
    /// shortcut: limit czasu liczenia na mówcę; podnieść, jeśli kalibracja pokaże, że więcej mowy poprawia odcisk.
    public static let maxTotal = 120.0

    /// Mówcy bez czasu toru (pliki sprzed TASK-117) są pominięci — dla nich nie ma odcisku.
    public static func speech(_ d: SpeakerDiarization) -> [String: Speech] {
        let timed = d.segments.compactMap { s -> (key: String, range: ClosedRange<Double>)? in
            guard let a = s.trackStart, let b = s.trackEnd, b > a else { return nil }
            return (s.speaker, a...b)
        }
        let untimed = Set(d.segments.filter { $0.trackStart == nil || $0.trackEnd == nil }.map(\.speaker))
        var result: [String: Speech] = [:]
        for key in Set(timed.map(\.key)).subtracting(untimed) {
            let others = timed.filter { $0.key != key }.map(\.range)
            let pieces = timed.filter { $0.key == key }.flatMap { subtract(others, from: $0.range) }
            let seconds = pieces.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
            var total = 0.0
            var spans: [ClosedRange<Double>] = []
            for piece in pieces.filter({ $0.upperBound - $0.lowerBound >= minPiece })
                .sorted(by: { ($0.upperBound - $0.lowerBound, $1.lowerBound) > ($1.upperBound - $1.lowerBound, $0.lowerBound) }) {
                guard total < maxTotal else { break }
                let length = min(piece.upperBound - piece.lowerBound, maxTotal - total)
                guard length >= minPiece else { break }
                spans.append(piece.lowerBound...(piece.lowerBound + length))
                total += length
            }
            result[key] = Speech(seconds: seconds, spans: spans)
        }
        return result
    }

    private static func subtract(_ cuts: [ClosedRange<Double>], from range: ClosedRange<Double>) -> [ClosedRange<Double>] {
        var pieces = [range]
        for cut in cuts {
            pieces = pieces.flatMap { p -> [ClosedRange<Double>] in
                guard cut.lowerBound < p.upperBound, cut.upperBound > p.lowerBound else { return [p] }
                var rest: [ClosedRange<Double>] = []
                if cut.lowerBound > p.lowerBound { rest.append(p.lowerBound...cut.lowerBound) }
                if cut.upperBound < p.upperBound { rest.append(cut.upperBound...p.upperBound) }
                return rest
            }
        }
        return pieces
    }
}
