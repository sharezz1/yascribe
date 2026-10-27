import Foundation
import YascribeMeetings

/// Tytuły spotkania: ręczny i automatyczny (`notes/meta.json`).
public struct NoteMeta: Codable, Equatable, Sendable {
    public var manualTitle: String?
    public var autoTitle: String?
    /// Powiązane wydarzenie z kalendarza (migawka). Opcjonalne: stary `meta.json` czyta się bez zmian.
    public var calendarEvent: CalendarLink?
    /// Model wybrany dla tego nagrania zamiast presetowego (faza 2.0.1). Opcjonalne: stary `meta.json` czyta się bez zmian.
    public var modelOverrides: ModelOverrides?
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
            let after = rest.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty { return after.prefix(1).uppercased() + after.dropFirst() }
        }
        return title
    }

    /// Tytuł = pierwszy nagłówek `# ` w pierwszych trzech niepustych liniach odpowiedzi (wstęp i ogrodzenie
    /// bloku kodu są tolerowane). Brak nagłówka → `title == nil`, `body` = cała odpowiedź.
    public static func parse(_ response: String) -> (title: String?, body: String) {
        let normalized = response.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let firstNonEmpty = lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let opensWithFence = firstNonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") ?? false
        let closesWithFence = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```"
        if lines.count >= 2, lines.first!.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```"),
           closesWithFence {
            lines.removeFirst()
            lines.removeLast()
        }
        var seen = 0
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            seen += 1
            if t.hasPrefix("# ") {
                let title = stripLabel(clean(String(t.dropFirst(2))))
                var bodyLines = Array(lines[0..<i] + lines[(i + 1)...])
                if opensWithFence && !closesWithFence {
                    if let fenceIdx = bodyLines.firstIndex(where: {
                        let s = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        return !s.isEmpty && s.hasPrefix("```")
                    }) {
                        bodyLines.remove(at: fenceIdx)
                    }
                }
                let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return (title.isEmpty ? nil : title, body)
            }
            if seen >= 3 { break }
        }
        return (nil, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Znaczniki listy na początku (razem z jedną spacją) zostają zdjęte przed parowaniem ozdobników.
        let bullets = ["* ", "- ", "\u{2022} "]
        for b in bullets where t.hasPrefix(b) {
            t = String(t.dropFirst(b.count))
            break
        }
        // Nieparowane gwiazdki z końców (parytet ze starym zachowaniem z master).
        while t.hasPrefix("*") { t.removeFirst() }
        while t.hasSuffix("*") { t.removeLast() }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = [("**", "**"), ("\"", "\""), ("'", "'"), ("„", "”"), ("«", "»"), ("“", "”"), ("‘", "’")]
        while let pair = pairs.first(where: { t.hasPrefix($0.0) && t.hasSuffix($0.1) && t.count >= $0.0.count + $0.1.count }) {
            t = String(t.dropFirst(pair.0.count).dropLast(pair.1.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    /// Ręczny > kalendarz > auto > tytuł z notatki > „Untitled meeting". Tytuł z notatki nie nadpisuje istniejącego.
    public static func display(meta: NoteMeta, noteTitle: String?) -> String {
        for c in [meta.manualTitle, meta.calendarEvent?.title, meta.autoTitle, noteTitle] {
            if let c, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return c }
        }
        return untitled
    }

    /// Tekst pola tytułu w widoku spotkania: tytuł z `display` w kolorze tekstu; tylko „Untitled meeting" zostaje
    /// placeholderem (puste pole). Liczone przy każdym odświeżeniu, nie kopiowane raz przy otwarciu (odbiór 2026-10-16,
    /// błąd 4: autotytuł zapisany w trakcie oglądania spotkania nie trafiał do pola).
    public static func fieldText(meta: NoteMeta, noteTitle: String?) -> String {
        let t = display(meta: meta, noteTitle: noteTitle)
        return t == untitled ? "" : t
    }

    /// Bufor edycji pola po zmianie tekstu: `nil`, gdy tekst jest dokładnie bieżącym tytułem (pole znów śledzi
    /// sesję). Porównanie bez przycinania — inaczej spacja dopisana na końcu autotytułu znikałaby przy pisaniu.
    public static func fieldEdit(_ text: String, meta: NoteMeta, noteTitle: String?) -> String? {
        text == fieldText(meta: meta, noteTitle: noteTitle) ? nil : text
    }

    /// Czy tekst z pola to nowy tytuł ręczny. Enter albo fokus bez zmiany nie zamienia autotytułu (ani tytułu
    /// z notatki) w ręczny — inaczej późniejszy autotytuł już by go nie zastąpił.
    public static func isEdit(_ edited: String, meta: NoteMeta, noteTitle: String?) -> Bool {
        edited.trimmingCharacters(in: .whitespacesAndNewlines) != fieldText(meta: meta, noteTitle: noteTitle)
    }
}
