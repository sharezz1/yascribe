import Foundation

/// Wyrównanie tokenów (LCS kluczy) — wspólne dla `CorrectionGuard` (YascribeNotes) i podziału wypowiedzi na mówców (TASK-127).
public enum TokenAlign {
    public static func key(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters.union(.symbols)).lowercased()
    }

    public enum Step: Equatable, Sendable { case same(Int, Int), changed(Range<Int>, Range<Int>) }

    /// Najdłuższy wspólny podciąg kluczy (LCS); bloki między wspólnymi tokenami to zmiany. Linie mają do kilkuset słów.
    public static func align(_ a: [String], _ b: [String]) -> [Step] {
        let n = a.count, m = b.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var steps: [Step] = []
        var i = 0, j = 0, oi = 0, ci = 0
        func flush() { if oi < i || ci < j { steps.append(.changed(oi..<i, ci..<j)) }; oi = i; ci = j }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                flush(); steps.append(.same(i, j)); i += 1; j += 1; oi = i; ci = j
            } else if j < m, i == n || table[i][j + 1] >= table[i + 1][j] { j += 1 }
            else { i += 1 }
        }
        flush()
        return steps
    }
}
