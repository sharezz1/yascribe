import Foundation
import YascribeProviders

public struct NoteSummary: Codable, Equatable, Sendable {
    public var title: String?
    public var markdown: String
    public var templateID: String
    public var model: String
    public var context: String
    public var generatedAt: Date
    /// Liczba części pierwszego przebiegu kondensacji, gdy transkrypt był dzielony (map-reduce, spec fazy 2.0 §11.1); `nil` = jeden przebieg.
    /// Pole opcjonalne: stare `summary.json` go nie mają (lekcja E6).
    public var condensedParts: Int?

    public init(title: String?, markdown: String, templateID: String, model: String, context: String, generatedAt: Date,
                condensedParts: Int? = nil) {
        self.condensedParts = condensedParts
        self.title = title
        self.markdown = markdown
        self.templateID = templateID
        self.model = model
        self.context = context
        self.generatedAt = generatedAt
    }
}

/// Nazwa kopii zapasowej `summary-<yyyyMMdd-HHmmss>.json`; przy kolizji (ta sama sekunda) sufiks `-2`, `-3`…
public enum BackupName {
    public static func name(for date: Date, existing: (String) -> Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = "summary-\(f.string(from: date))"
        var n = 1
        var candidate = "\(base).json"
        while existing(candidate) { n += 1; candidate = "\(base)-\(n).json" }
        return candidate
    }
}

/// `<sesja>/notes/`: `my-notes.md`, `summary.json`, `meta.json`, `summary-<ts>.json` (kopie przy regeneracji).
/// Katalog `notes/` leży obok `runs/` — `summarize()` i wyszukiwanie przebiegów go nie czytają.
///
/// Brak pliku to nie to samo co plik, którego nie da się odczytać (Review Luna #2): nieczytelny plik jest przed
/// PIERWSZYM zapisem odkładany jako `<nazwa>.corrupt-<yyyyMMdd-HHmmss>` (jak `AppModel.load()`), a metody zapisu
/// zwracają komunikat z nazwą. `problems()` mówi, które pliki są nieczytelne, zanim cokolwiek zapiszemy.
public struct NotesStore: Sendable {
    public let directory: URL

    public init(session: URL) { directory = session.appendingPathComponent("notes") }

    var myNotesURL: URL { directory.appendingPathComponent("my-notes.md") }
    var summaryURL: URL { directory.appendingPathComponent("summary.json") }
    var metaURL: URL { directory.appendingPathComponent("meta.json") }

    /// Do wyświetlania: brak albo nieczytelny plik → pusty tekst (nieczytelny zgłasza `problems()`).
    public func readMyNotes() -> String { (try? String(contentsOf: myNotesURL, encoding: .utf8)) ?? "" }

    /// Do wyświetlania: brak albo nieczytelny plik → puste tytuły (nieczytelny zgłasza `problems()`).
    public func readMeta() -> NoteMeta { (try? JSONFile.load(NoteMeta.self, from: metaURL, default: NoteMeta())) ?? NoteMeta() }

    /// Brak pliku → `nil`; nieczytelny → rzuca.
    public func readSummary() throws -> NoteSummary? { try JSONFile.load(NoteSummary?.self, from: summaryURL, default: nil) }

    /// Nazwy plików, które istnieją, ale nie dają się odczytać (kolejność stała).
    public func problems() -> [String] {
        var out: [String] = []
        if unreadable(myNotesURL, { _ = try String(contentsOf: myNotesURL, encoding: .utf8) }) { out.append("my-notes.md") }
        if unreadable(summaryURL, { _ = try JSONFile.load(NoteSummary?.self, from: summaryURL, default: nil) }) { out.append("summary.json") }
        if unreadable(metaURL, { _ = try JSONFile.load(NoteMeta.self, from: metaURL, default: NoteMeta()) }) { out.append("meta.json") }
        return out
    }

    /// Zwraca komunikat, gdy odłożono nieczytelny plik; `nil` — nic nie było do odłożenia.
    @discardableResult
    public func writeMyNotes(_ text: String, now: Date = Date()) throws -> String? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = try setAsideIfUnreadable(myNotesURL, now: now) { _ = try String(contentsOf: myNotesURL, encoding: .utf8) }
        try text.write(to: myNotesURL, atomically: true, encoding: .utf8)
        return note
    }

    /// Czyta, zmienia, zapisuje. Nieczytelny `meta.json` jest najpierw odkładany (nie kasujemy cudzych danych).
    @discardableResult
    public func updateMeta(now: Date = Date(), _ change: (inout NoteMeta) -> Void) throws -> String? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = try setAsideIfUnreadable(metaURL, now: now) { _ = try JSONFile.load(NoteMeta.self, from: metaURL, default: NoteMeta()) }
        var m = (try? JSONFile.load(NoteMeta.self, from: metaURL, default: NoteMeta())) ?? NoteMeta()
        change(&m)
        try JSONFile.save(m, to: metaURL)
        return note
    }

    /// Czytelny stary `summary.json` idzie do kopii przed nadpisaniem (kopia, potem atomowy zapis nowego);
    /// nieczytelny jest odkładany jako `.corrupt-…` (nie ma czego kopiować jako wersji notatki).
    @discardableResult
    public func writeSummary(_ s: NoteSummary, now: Date = Date()) throws -> String? {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = try setAsideIfUnreadable(summaryURL, now: now) { _ = try JSONFile.load(NoteSummary?.self, from: summaryURL, default: nil) }
        if fm.fileExists(atPath: summaryURL.path) {
            let name = BackupName.name(for: now) { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }
            try fm.copyItem(at: summaryURL, to: directory.appendingPathComponent(name))
        }
        try JSONFile.save(s, to: summaryURL)
        return note
    }

    private func unreadable(_ url: URL, _ check: () throws -> Void) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do { try check(); return false } catch { return true }
    }

    /// Odkłada nieczytelny plik jako `<nazwa>.corrupt-<yyyyMMdd-HHmmss>` (przy kolizji `-2`, `-3`…). Gdy przeniesienie się
    /// nie uda, rzuca — wtedy NIC nie jest zapisywane.
    private func setAsideIfUnreadable(_ url: URL, now: Date, _ check: () throws -> Void) throws -> String? {
        guard unreadable(url, check) else { return nil }
        let fm = FileManager.default
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(url.lastPathComponent).corrupt-\(f.string(from: now))"
        var n = 1
        var name = base
        while fm.fileExists(atPath: directory.appendingPathComponent(name).path) { n += 1; name = "\(base)-\(n)" }
        try fm.moveItem(at: url, to: directory.appendingPathComponent(name))
        return "\(url.lastPathComponent) couldn't be read, so it was kept as \(name) and a new one was started."
    }
}
