import Foundation

/// Odsiew tekstowy echa z głośników (odbiór T13, uwaga 2). Mikrofon łapie dźwięk z głośników, więc ta sama rozmowa trafia
/// do transkryptu dwa razy: jako „Them" (tap systemowy) i jako „Me" (mikrofon). Filtr akustyczny (`CrosstalkFilter`,
/// korelacja obwiedni) tego nie łapie, więc po transkrypcji porównujemy TEKST: wypowiedź „Me", której słowa (co najmniej
/// 80%) leżą w słowach wypowiedzi „Them" nakładających się czasowo, jest echem i nie trafia do notatki — inaczej model
/// przypisałby użytkownikowi cudze słowa (właściciele w Next Steps).
public enum EchoFilter {
    /// Krótkie wypowiedzi („tak", „okej") zbyt łatwo pokrywają się ze słowami rozmówcy.
    public static let minWords = 4
    /// Udział słów wypowiedzi „Me" obecnych w słowach nakładających się wypowiedzi „Them".
    public static let containment = 0.8
    /// Zapas czasu (s) na różnice w granicach okien ASR między torami.
    public static let margin = 5.0

    /// Zwraca kopię z `echoOfThem = true` na wypowiedziach „Me" będących echem. Idempotentne.
    public static func mark(_ utterances: [Utterance]) -> [Utterance] {
        let them = utterances.filter { $0.speaker == .them }
        var out = utterances
        for i in out.indices where out[i].speaker == .me {
            let m = out[i]
            let mine = tokens(m.text)
            guard mine.count >= minWords else { continue }
            var pool = Set<String>()
            for t in them where t.start - margin < m.end && m.start - margin < t.end { pool.formUnion(tokens(t.text)) }
            guard !pool.isEmpty else { continue }
            let shared = mine.filter { pool.contains($0) }.count
            if Double(shared) / Double(mine.count) >= containment { out[i].echoOfThem = true }
        }
        return out
    }

    static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }
}

public extension Transcript {
    /// Kopia z oznaczonym echem (także dla starszych transkryptów zapisanych bez znacznika).
    func echoMarked() -> Transcript {
        var copy = self
        copy.utterances = EchoFilter.mark(utterances)
        return copy
    }
}
