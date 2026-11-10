import CryptoKit
import Foundation
import YascribeProviders

/// Które polecenie systemowe użytkownik może zmienić w Settings (TASK-96).
public enum PromptKind: String, CaseIterable, Sendable {
    case correction, summary

    public var defaultBody: String { self == .correction ? CorrectionPrompt.defaultBody : SummaryPrompt.defaultBody }
    /// Limit liczony na domyślnym lokalnym kontekście 4096 tokenów (cały prompt notatki ≈ 4 300 znaków), z zapasem na stałe bloki.
    public var maxChars: Int { self == .correction ? 1_500 : 2_000 }
}

/// Własny tekst podstawy i skrót domyślnej podstawy, na której go oparto (do wykrycia, że domyślna się zmieniła).
public struct PromptEntry: Codable, Equatable, Sendable {
    public var text: String
    public var basedOn: String
    public init(text: String, basedOn: String) { self.text = text; self.basedOn = basedOn }
}

/// Ślad użytej podstawy przy wyniku (`corrected.json`, `summary.json`): pełny tekst, bo domyślny zmienia się między wersjami.
public struct PromptTrace: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case `default`, custom }
    public var source: Source
    public var text: String
    public init(source: Source, text: String) { self.source = source; self.text = text }
}

/// `prompts.json`: wpis tylko dla poleceń zmienionych przez użytkownika; brak wpisu = domyślne (pola opcjonalne, lekcja E6).
public struct PromptOverrides: Codable, Equatable, Sendable {
    public var correction: PromptEntry?
    public var summary: PromptEntry?
    public init(correction: PromptEntry? = nil, summary: PromptEntry? = nil) { self.correction = correction; self.summary = summary }

    public enum SetError: Error, Equatable { case tooLong(max: Int) }

    public func entry(_ kind: PromptKind) -> PromptEntry? { kind == .correction ? correction : summary }
    private mutating func put(_ entry: PromptEntry?, _ kind: PromptKind) { if kind == .correction { correction = entry } else { summary = entry } }

    /// Podstawa do użycia przez builder: własna albo domyślna.
    public func body(_ kind: PromptKind) -> String { entry(kind)?.text ?? kind.defaultBody }

    public func trace(_ kind: PromptKind) -> PromptTrace {
        PromptTrace(source: entry(kind) == nil ? .default : .custom, text: body(kind))
    }

    /// Własny tekst oparty na starej domyślnej podstawie: pokazujemy notkę, nie ruszamy tekstu.
    public func isStale(_ kind: PromptKind) -> Bool {
        entry(kind).map { $0.basedOn != Self.hash(kind.defaultBody) } ?? false
    }

    /// Tekst równy domyślnemu albo pusty kasuje wpis (jak `fillerWords`); ponad limit — błąd, nic się nie zmienia.
    public mutating func set(_ kind: PromptKind, text: String) throws {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= kind.maxChars else { throw SetError.tooLong(max: kind.maxChars) }
        put(t.isEmpty || t == kind.defaultBody.trimmingCharacters(in: .whitespacesAndNewlines) ? nil
            : PromptEntry(text: t, basedOn: Self.hash(kind.defaultBody)), kind)
    }

    /// „Keep mine": ten sam tekst, oparty teraz na bieżącej domyślnej.
    public mutating func acknowledge(_ kind: PromptKind) {
        guard var e = entry(kind) else { return }
        e.basedOn = Self.hash(kind.defaultBody)
        put(e, kind)
    }

    /// SHA-256, 12 pierwszych znaków hex.
    public static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

public enum PromptStore {
    /// Brak pliku = domyślne. Uszkodzony: domyślne w pamięci i `problem` do pokazania; pliku nie ruszamy aż do zapisu.
    public static func load(from url: URL) -> (overrides: PromptOverrides, problem: String?) {
        do {
            return (try JSONFile.load(PromptOverrides.self, from: url, default: PromptOverrides()), nil)
        } catch {
            return (PromptOverrides(), "Couldn't read your custom prompts (\(error.localizedDescription)). The defaults are in use; saving will keep the old file as \(url.lastPathComponent).bak.")
        }
    }

    /// Nieczytelny plik idzie na bok (`.bak`) przed zapisem: `JSONFile.save` sam nie robi kopii.
    public static func save(_ overrides: PromptOverrides, to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path), (try? JSONFile.load(PromptOverrides.self, from: url, default: PromptOverrides())) == nil {
            let bak = url.appendingPathExtension("bak")
            try? fm.removeItem(at: bak)
            try fm.moveItem(at: url, to: bak)
        }
        try JSONFile.save(overrides, to: url)
    }
}
