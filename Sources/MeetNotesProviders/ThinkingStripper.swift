import Foundation

/// Odpowiedź modelu „thinking" bez bloku rozumowania (`<think>…</think>`, `<thinking>…</thinking>`, `[THINK]…[/THINK]`,
/// wielkość liter bez znaczenia). Jedno przejście od lewej: bierze najwcześniejszy otwierający tag dowolnego rodzaju i
/// szuka jego własnego zamknięcia, więc tag innego rodzaju w środku bloku nie psuje wyniku.
/// - Zamknięty blok znika wszędzie.
/// - Niedomknięty otwierający tag to rozumowanie ucięte limitem tokenów (znika razem z resztą) TYLKO gdy przed nim nie
///   ma żadnej treści; w środku odpowiedzi (np. punkt notatki z literalnym `<think>`) zostaje nietknięty.
/// - Zamykający tag bez otwarcia (szablon czatu wstrzyknął otwarcie — DeepSeek-R1-Distill) usuwa wszystko przed sobą.
/// Pusty wynik to błąd wołającego, nie wyciek rozumowania do notatki.
public enum ThinkingStripper {
    private static let pairs = [("<think>", "</think>"), ("<thinking>", "</thinking>"), ("[THINK]", "[/THINK]")]

    /// Najwcześniejsze wystąpienie któregokolwiek tokena od `from` (+ indeks tokena).
    private static func earliest(_ tokens: [String], in s: String, from: String.Index) -> (range: Range<String.Index>, index: Int)? {
        tokens.enumerated().compactMap { i, t in s.range(of: t, options: .caseInsensitive, range: from..<s.endIndex).map { ($0, i) } }
            .min { $0.0.lowerBound < $1.0.lowerBound }
    }

    public static func clean(_ reply: String) -> String {
        var out = ""
        var pos = reply.startIndex
        while true {
            let open = earliest(pairs.map(\.0), in: reply, from: pos)
            if let close = earliest(pairs.map(\.1), in: reply, from: pos), open.map({ close.range.lowerBound < $0.range.lowerBound }) ?? true {
                out = ""
                pos = close.range.upperBound
                continue
            }
            guard let open else { break }
            out += reply[pos..<open.range.lowerBound]
            if let end = reply.range(of: pairs[open.index].1, options: .caseInsensitive, range: open.range.upperBound..<reply.endIndex) {
                pos = end.upperBound
            } else if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ""
            } else {
                out += reply[open.range]
                pos = open.range.upperBound
            }
        }
        out += reply[pos...]
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
