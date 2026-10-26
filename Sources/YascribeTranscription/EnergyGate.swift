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
