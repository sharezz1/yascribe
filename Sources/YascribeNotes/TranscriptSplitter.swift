import Foundation

/// Dzieli linie transkryptu `[m:ss] Me|Them: …` na części do `maxChars` znaków (po złączeniu przez `\n`) dla map-reduce
/// (spec fazy 2.0 §11.4, plan T13). Linia nigdy nie jest cięta w środku słowa; wypowiedź dłuższa niż limit (monolog bez pauz 1,2 s)
/// jest dzielona na granicy słowa z powtórzonym prefiksem `[m:ss] Me:`/`Them:`, żeby każdy kawałek zachował mówcę i czas.
public enum TranscriptSplitter {
    public static func parts(_ lines: [String], maxChars: Int) throws -> [[String]] {
        var out: [[String]] = []
        var cur: [String] = []
        var size = 0 // znaki części po złączeniu: linie + `\n` między nimi
        for piece in try lines.flatMap({ try pieces(of: $0, maxChars: maxChars) }) {
            if !cur.isEmpty && size + 1 + piece.count > maxChars { out.append(cur); cur = []; size = 0 }
            size += (cur.isEmpty ? 0 : 1) + piece.count
            cur.append(piece)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// `[m:ss] Me: ` albo `[m:ss] Them: ` (z końcową spacją); pusty, gdy linia nie ma takiego prefiksu (np. wyjście mapy bez niego).
    static func prefix(of line: String) -> String {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return "" }
        let rest = line[line.index(after: close)...]
        for tag in [" Me: ", " Them: "] where rest.hasPrefix(tag) { return String(line[...close]) + tag }
        return ""
    }

    private static func pieces(of line: String, maxChars: Int) throws -> [String] {
        guard line.count > maxChars else { return [line] }
        let prefix = prefix(of: line)
        let words = line.dropFirst(prefix.count).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let room = maxChars - prefix.count
        guard room > 0, words.allSatisfy({ $0.count <= room }) else {
            throw NoteGenerationError.failed("A single line is longer than the Context window. Raise it in Settings.")
        }
        var out: [String] = []
        var cur = ""
        for w in words {
            if !cur.isEmpty && cur.count + 1 + w.count > room { out.append(prefix + cur); cur = "" }
            cur += cur.isEmpty ? w : " " + w
        }
        if !cur.isEmpty { out.append(prefix + cur) }
        return out
    }
}
