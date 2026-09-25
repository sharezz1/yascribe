import Foundation

public enum Levels {
    /// RMS w dBFS dla próbek Int16. Pusta porcja albo sama cisza cyfrowa: -160.
    public static func rmsDBFS(_ samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return -160 }
        var sum = 0.0
        for s in samples {
            let x = Double(s) / 32_768
            sum += x * x
        }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? max(-160, 20 * log10(rms)) : -160
    }
}
