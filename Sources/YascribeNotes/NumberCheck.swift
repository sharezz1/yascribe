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
            return d.count >= 2 && !known.contains(d) && seen.insert(d).inserted
        }
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
