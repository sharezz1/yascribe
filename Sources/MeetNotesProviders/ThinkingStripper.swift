import Foundation

/// Odpowiedź modelu „thinking" bez bloku rozumowania (`<think>…</think>`, `[THINK]…[/THINK]`). Niedomknięty blok
/// (rozumowanie ucięte limitem tokenów) znika razem z resztą odpowiedzi — pusty wynik to błąd, nie wyciek do notatki.
public enum ThinkingStripper {
    private static let tags = [("<think>", "</think>"), ("[THINK]", "[/THINK]")]

    public static func clean(_ reply: String) -> String {
        var s = reply
        for (open, close) in tags {
            while let o = s.range(of: open) {
                let end = s.range(of: close, range: o.upperBound..<s.endIndex)?.upperBound ?? s.endIndex
                s.removeSubrange(o.lowerBound..<end)
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
