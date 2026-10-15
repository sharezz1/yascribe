import Foundation

/// Tytuły spotkania: ręczny i automatyczny (`notes/meta.json`).
public struct NoteMeta: Codable, Equatable, Sendable {
    public var manualTitle: String?
    public var autoTitle: String?
    public init(manualTitle: String? = nil, autoTitle: String? = nil) {
        self.manualTitle = manualTitle
        self.autoTitle = autoTitle
    }
}

public enum NoteTitle {
    public static let untitled = "Untitled meeting"

    /// Reguła tytułu wspólna dla promptu notatki i promptu autotytułu (odbiór T13, uwaga 5: tytuł z przedrostkiem
    /// „Notatki z rozmowy: …" i na 15 słów).
    public static let rule = "The title is short (at most 8 words) and names the topic directly. It never starts with a "
        + "label such as \"Meeting notes\", \"Notes from the conversation\", \"Summary of the meeting\", "
        + "\"Notatki z rozmowy\" or \"Podsumowanie\"."

    /// Etykiety, które modele lubią dokleić przed tytułem (porównanie bez względu na wielkość liter).
    static let labels = ["notatki z rozmowy", "notatki ze spotkania", "podsumowanie rozmowy", "podsumowanie spotkania",
                         "meeting notes", "notes from the conversation", "notes from the meeting", "summary of the meeting",
                         "podsumowanie", "notatki", "notes", "summary"].sorted { $0.count > $1.count }

    /// „Notatki z rozmowy: presja na wygląd" → „Presja na wygląd". Etykieta musi być po niej oddzielona `:` albo myślnikiem;
    /// sama etykieta albo zwykłe słowo na początku tytułu zostają.
    public static func stripLabel(_ title: String) -> String {
        let lower = title.lowercased()
        for label in labels where lower.hasPrefix(label) {
            let rest = title.dropFirst(label.count).drop(while: { $0 == " " })
            guard let sep = rest.first, ":–—-".contains(sep) else { continue }
            let after = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { return after.prefix(1).uppercased() + after.dropFirst() }
        }
        return title
    }

    /// Tytuł = pierwszy nagłówek `# ` w pierwszych trzech niepustych liniach odpowiedzi (wstęp i ogrodzenie
    /// bloku kodu są tolerowane). Brak nagłówka → `title == nil`, `body` = cała odpowiedź.
    public static func parse(_ response: String) -> (title: String?, body: String) {
        var lines = response.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.count >= 2, lines.first!.trimmingCharacters(in: .whitespaces).hasPrefix("```"),
           lines.last!.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeFirst()
            lines.removeLast()
        }
        var seen = 0
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            seen += 1
            if t.hasPrefix("# ") {
                let title = stripLabel(clean(String(t.dropFirst(2))))
                let body = lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return (title.isEmpty ? nil : title, body)
            }
            if seen >= 3 { break }
        }
        return (nil, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "*\"“”' ").union(.whitespaces))
    }

    /// Ręczny > auto > tytuł z notatki > „Untitled meeting". Tytuł z notatki nie nadpisuje istniejącego.
    public static func display(meta: NoteMeta, noteTitle: String?) -> String {
        for c in [meta.manualTitle, meta.autoTitle, noteTitle] {
            if let c, !c.trimmingCharacters(in: .whitespaces).isEmpty { return c }
        }
        return untitled
    }
}
