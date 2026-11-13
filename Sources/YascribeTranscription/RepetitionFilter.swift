import Foundation

/// Progi z TASK-102 compare.py, R07. Sygnał strukturalny, bez listy zakazanych fraz.
public enum RepetitionFilter {
    public static func isHallucinated(_ text: String, previousText: String = "") -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let w = words(text), p = words(previousText)
        if w.count >= 8 && Double(Set(w).count) < Double(w.count) * 0.4 { return true }
        for n in 1...4 {
            let repetitions = n == 1 ? 4 : 3
            if w.count >= n * repetitions {
                for i in 0...(w.count - n * repetitions) {
                    let phrase = w[i..<(i + n)]
                    if (1..<repetitions).allSatisfy({ k in
                        w[(i + k * n)..<(i + (k + 1) * n)].elementsEqual(phrase)
                    }) { return true }
                }
            }
            if n >= 2, w.count >= n {
                var counts: [[String]: Int] = [:]
                for i in 0...(w.count - n) { counts[Array(w[i..<(i + n)]), default: 0] += 1 }
                if let count = counts.values.max(), count >= 3, Double(count * n) >= 0.3 * Double(w.count) { return true }
            }
        }
        if w.count >= 3 && w == p { return true }
        // Najdłuższy wspólny ciąg, nie zbiór słów: zwykłe słownictwo tematu nie wystarcza.
        var previous = [Int](repeating: 0, count: w.count + 1)
        for word in p {
            var current = [Int](repeating: 0, count: w.count + 1)
            for j in w.indices where word == w[j] {
                current[j + 1] = previous[j] + 1
                if current[j + 1] >= 6 { return true }
            }
            previous = current
        }
        return false
    }
}
