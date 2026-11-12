import Foundation

/// Liczby w notatce, których nie ma w materiale (transkrypt, My notes, kontekst): zwykle wymyślone przez model.
/// Porównujemy same cyfry, więc `13.30` = `13:30`, a `3,8960` = `3.8960`. Liczby jednocyfrowe pomijamy (mowa „dwa" → „2").
/// shortcut: liczba wypowiedziana słowami („piętnasta") i zapisana cyframi w notatce też trafi na listę; to ostrzeżenie, nie cofnięcie.
public enum NumberCheck {
    public static func unverified(in note: String, sources: [String]) -> [String] {
        let known = Set(sources.flatMap(numbers).map(digits))
        var seen = Set<String>()
        return numbers(in: note).filter { n in
            let d = digits(n)
            return d.count >= 2 && !matches(d, known) && seen.insert(d).inserted
        }
    }

    /// Pełna godzina bywa wypowiedziana jako „na 11", a zapisana „11:00" (i odwrotnie): `1100` pasuje do `11`.
    /// shortcut: liczby `1500` i `15:00` nie są rozróżniane (porównujemy cyfry), więc `1500` przy wypowiedzianym „15" nie zostanie zgłoszone.
    private static func matches(_ d: String, _ known: Set<String>) -> Bool {
        known.contains(d) || known.contains(d + "00") || (d.hasSuffix("00") && d.count <= 4 && known.contains(String(d.dropLast(2))))
    }

    /// Liczby z tekstu, w kolejności; znaczniki list („12. ") na początku linii nie są liczbami.
    static func numbers(in text: String) -> [String] {
        let cleaned = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard let r = line.range(of: #"^\s*[-*]?\s*\d+[.)]\s"#, options: .regularExpression) else { return String(line) }
            return String(line[r.upperBound...])
        }.joined(separator: "\n")
        return cleaned.matches(of: /\d+(?:[.,:]\d+)*/).map { String($0.output) }
    }

    private static func digits(_ n: String) -> String { n.filter(\.isNumber) }
}
