import Foundation

/// 🔴 Drugi tryb awarii bramki (W§1, rozdz. 17): przesłuch z głośników. Mikrofon słyszy
/// rozmówców, a bramka energii uznaje to za mowę — inne narzędzie wstawiał tak urywki cudzych
/// zdań w środek zdań rozmówcy (52 z 53 wtrąceń ≤ 3 słowa). Fragment mikrofonu, którego
/// obwiednia energii idzie w parze z kanałem systemowym (z opóźnieniem drogi akustycznej
/// do 0,3 s), odpada przed ASR. Obwiednia z ramek 20 ms, nie próbki: tanio i odpornie na
/// barwę pokoju. Próg zachowawczy — gdy użytkownik mówi sam albo przez rozmówcę, obwiednie
/// się rozjeżdżają i fragment zostaje.
public struct CrosstalkFilter: Codable, Equatable, Sendable {
    public var correlationThreshold = 0.8
    public var maxLagSeconds = 0.3

    public init() {}

    /// `micOffsetSeconds`: o ile później ruszył mikrofon niż ścieżka systemowa (oś sesji).
    public func keep(_ regions: [Range<Int>], mic: [Float], system: [Float], micOffsetSeconds: Double,
                     rate: Double = Resampler.asrRate) -> [Range<Int>] {
        let frame = Int(rate * EnergyGate.frameSeconds)
        let micEnv = EnergyGate.frameLevels(mic, rate: rate)
        let sysEnv = EnergyGate.frameLevels(system, rate: rate)
        let offsetFrames = Int((micOffsetSeconds / EnergyGate.frameSeconds).rounded())
        let maxLag = Int((maxLagSeconds / EnergyGate.frameSeconds).rounded())
        return regions.filter { r in
            let a = r.lowerBound / frame
            let b = min(max(a + 1, r.upperBound / frame), micEnv.count)
            guard a < b else { return true }
            let m = Array(micEnv[a..<b])
            var best = 0.0
            for lag in 0...maxLag {
                // echo w mikrofonie w chwili T pochodzi z systemu z chwili T - lag
                let s0 = a + offsetFrames - lag
                guard s0 >= 0, s0 + m.count <= sysEnv.count else { continue }
                best = max(best, Self.pearson(m, Array(sysEnv[s0..<(s0 + m.count)])))
            }
            return best < correlationThreshold
        }
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        guard n > 2 else { return 0 }
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in x.indices {
            let dx = x[i] - mx, dy = y[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        return sxx > 0 && syy > 0 ? sxy / (sxx * syy).squareRoot() : 0
    }
}
