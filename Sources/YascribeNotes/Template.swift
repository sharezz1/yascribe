import Foundation
import YascribeProviders

/// Jedna sekcja notatki: tytuł (nagłówek w notatce) + instrukcja dla modelu.
/// `id` służy tylko interfejsowi (stabilna tożsamość przy przesuwaniu); nie jest zapisywany ani porównywany.
public struct TemplateSection: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var instruction: String

    public init(title: String, instruction: String) { self.title = title; self.instruction = instruction }

    enum CodingKeys: String, CodingKey { case title, instruction }

    public static func == (a: TemplateSection, b: TemplateSection) -> Bool { a.title == b.title && a.instruction == b.instruction }

    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Szablon podsumowania: rodzaj spotkania → lista sekcji notatki (spec 1.5 §3, macos.md §11.5 „Templates").
/// Preset = język + modele; szablon wybiera się przy „Generate notes" i można go zmienić przy regeneracji.
/// Nowe pola (`sections`, `about`) są opcjonalne (lekcja E6): stary plik z jednym promptem (`instructions`) wczytuje się
/// jako jedna sekcja bez tytułu (`effectiveSections`), a ponowne zakodowanie zachowuje wszystkie klucze.
public struct Template: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Prompt z czasów jednego pola. Przy zapisie z edytora odzwierciedla sekcje (dla starszych wersji aplikacji).
    public var instructions: String
    public var builtin: Bool
    public var sections: [TemplateSection]?
    /// „About this meeting type": opcjonalny opis rodzaju spotkania, na początku promptu.
    public var about: String?

    public init(id: String = UUID().uuidString, name: String, instructions: String = "", builtin: Bool = false,
                sections: [TemplateSection]? = nil, about: String? = nil) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.builtin = builtin
        self.sections = sections
        self.about = about
    }

    /// Sekcje po migracji przy odczycie: zapisane albo — dla starego szablonu — jedna sekcja bez tytułu z całym promptem.
    public var effectiveSections: [TemplateSection] {
        if let sections { return sections }
        return instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [TemplateSection(title: "", instruction: instructions)]
    }

    /// Czysta funkcja: opis rodzaju spotkania (jeśli jest) + sekcje po kolei → tekst bloku „Structure" w prompcie.
    public var promptText: String {
        var parts: [String] = []
        if let about = about?.trimmingCharacters(in: .whitespacesAndNewlines), !about.isEmpty {
            parts.append("About this meeting type: \(about)")
        }
        let body = sectionsText
        if !body.isEmpty { parts.append(body) }
        return parts.joined(separator: "\n\n")
    }

    /// Same sekcje. Jedna sekcja bez tytułu (stary szablon) idzie dosłownie, jak przed zmianą.
    var sectionsText: String {
        let secs = effectiveSections.filter { !$0.isBlank }
        if secs.count == 1, secs[0].title.trimmingCharacters(in: .whitespaces).isEmpty { return secs[0].instruction }
        guard !secs.isEmpty else { return "" }
        let lines = secs.enumerated().map { i, s -> String in
            let t = s.title.trimmingCharacters(in: .whitespacesAndNewlines), ins = s.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(i + 1). " + (t.isEmpty ? ins : ins.isEmpty ? t : "\(t): \(ins)")
        }
        return (["Write these sections in this order, each titled section under a \"## <title>\" heading:"] + lines).joined(separator: "\n")
    }

    /// Kopia do edycji — zawsze własna (niewbudowana), z tą samą treścią.
    public func duplicate() -> Template {
        Template(name: "\(name) copy", instructions: instructions, sections: effectiveSections, about: about)
    }

    /// Ta sama treść (nazwa, opis, sekcje) — bez id, flagi i lustra `instructions`.
    func sameContent(as o: Template) -> Bool { name == o.name && about == o.about && effectiveSections == o.effectiveSections }

    private static func builtIn(_ id: String, _ name: String, _ sections: [(String, String)]) -> Template {
        var t = Template(id: id, name: name, builtin: true, sections: sections.map { TemplateSection(title: $0.0, instruction: $0.1) })
        t.instructions = t.sectionsText
        return t
    }

    private static let nextSteps = ("Next steps", "One bullet per action: the task in bold, the owner in parentheses (use the name said in the conversation; if nobody was named write “(owner unclear)”), then one sentence of reasoning.")

    public static let standard = builtIn("standard", "Standard", [
        ("Summary", "One paragraph: what was discussed and what was agreed."),
        ("Topics", "One heading per topic with the concrete details: numbers, names, dates, the options discussed; mark the favored option. A side issue gets its own heading."),
        nextSteps,
    ])

    public static let oneToOne = builtIn("one-to-one", "1:1", [
        ("Summary", "A short summary of the conversation."),
        ("Updates", "What each person reported, with specifics."),
        ("Feedback and concerns", "What was raised, by whom, and how it was received."),
        nextSteps,
    ])

    public static let weeklyTeam = builtIn("weekly-team", "Weekly team meeting", [
        ("Summary", "A short summary of the meeting."),
        ("Progress", "What moved since last time, per topic, with numbers where given."),
        ("Blockers and risks", "What is stuck, who is affected."),
        ("Decisions", "What was decided and by whom."),
        nextSteps,
    ])

    public static let discoveryCall = builtIn("discovery-call", "Customer: Discovery", [
        ("Summary", "A short summary: who the customer is and why they called."),
        ("Needs and pain points", "In the customer's own terms, with specifics."),
        ("Current situation", "Tools, process, constraints they described."),
        ("Objections and open questions", "What the customer doubted or left unanswered."),
        nextSteps,
    ])

    public static let builtIns: [Template] = [standard, oneToOne, weeklyTeam, discoveryCall]
}

public enum TemplateError: Error, Equatable {
    case builtinCantBeRemoved
    case builtinIsReadOnly
    case nameTaken(String)
    case missingName
    case noSections
}

/// Szablony użytkownika (`templates.json`): własne + nadpisania wbudowanych. Wbudowane żyją w kodzie;
/// edycja wbudowanego zapisuje nadpisanie obok (`overrides`), a „Reset to default" je usuwa.
public struct TemplatesFile: Codable, Equatable, Sendable {
    public var templates: [Template] = []
    /// Opcjonalne (E6): stary plik go nie ma.
    public var overrides: [Template]?
    public init(templates: [Template] = [], overrides: [Template]? = nil) { self.templates = templates; self.overrides = overrides }

    /// Wbudowane (z nadpisaniami) + własne.
    public func all() -> [Template] {
        Template.builtIns.map { b in overrides?.first { $0.id == b.id } ?? b } + templates
    }

    public func isBuiltin(id: String) -> Bool { Template.builtIns.contains { $0.id == id } }
    public func isEdited(id: String) -> Bool { overrides?.contains { $0.id == id } == true }

    public mutating func upsert(_ t: Template) throws {
        let isBuiltinID = isBuiltin(id: t.id)
        guard isBuiltinID || !t.builtin else { throw TemplateError.builtinIsReadOnly } // nowych wbudowanych nie ma
        var t = t
        t.name = t.name.trimmingCharacters(in: .whitespaces)
        guard !t.name.isEmpty else { throw TemplateError.missingName }
        guard !all().contains(where: { $0.id != t.id && $0.name.caseInsensitiveCompare(t.name) == .orderedSame }) else {
            throw TemplateError.nameTaken(t.name)
        }
        t.about = t.about?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        t.sections = t.effectiveSections.map {
            TemplateSection(title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                            instruction: $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard t.effectiveSections.contains(where: { !$0.isBlank }) else { throw TemplateError.noSections }
        t.instructions = t.sectionsText
        if isBuiltinID {
            t.builtin = true
            overrides = (overrides ?? []).filter { $0.id != t.id }
            // Bez różnicy względem domyślnego nie ma czego nadpisywać.
            if let def = Template.builtIns.first(where: { $0.id == t.id }), !t.sameContent(as: def) { overrides?.append(t) }
            if overrides?.isEmpty == true { overrides = nil }
        } else if let i = templates.firstIndex(where: { $0.id == t.id }) {
            templates[i] = t
        } else {
            templates.append(t)
        }
    }

    /// Przywraca wbudowany do domyślnej treści (usuwa nadpisanie).
    public mutating func reset(id: String) {
        overrides?.removeAll { $0.id == id }
        if overrides?.isEmpty == true { overrides = nil }
    }

    /// Usuwa własny szablon; wbudowanych nie da się usunąć (wystarcza reset).
    public mutating func remove(id: String) throws {
        guard !isBuiltin(id: id) else { throw TemplateError.builtinCantBeRemoved }
        templates.removeAll { $0.id == id }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
