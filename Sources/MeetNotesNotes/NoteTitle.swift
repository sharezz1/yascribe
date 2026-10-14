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
                let title = clean(String(t.dropFirst(2)))
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
