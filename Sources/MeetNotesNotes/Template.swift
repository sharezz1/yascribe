import Foundation
import MeetNotesProviders

/// Szablon podsumowania: rodzaj spotkania → struktura notatki (spec 1.5 §3, decyzja 2).
/// Preset = język + modele; szablon wybiera się przy „Generate notes" i można go zmienić przy regeneracji.
public struct Template: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var instructions: String
    public var builtin: Bool

    public init(id: String = UUID().uuidString, name: String, instructions: String, builtin: Bool = false) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.builtin = builtin
    }

    /// Kopia do edycji — wbudowane są tylko do odczytu.
    public func duplicate() -> Template { Template(name: "\(name) copy", instructions: instructions) }

    public static let standard = Template(id: "standard", name: "Standard", instructions: """
        1. A one-paragraph summary: what was discussed and what was agreed.
        2. Topics: one "## " heading per topic, with bullet points that keep the concrete details (numbers, names, dates, \
        the options discussed; mark a favored option with "(favored)"). A side issue gets its own heading.
        3. "## Next Steps": one bullet per action — the task in bold, the owner in parentheses (use the name said in the \
        conversation; if nobody was named write "(owner unclear)"), then one sentence of reasoning.
        """, builtin: true)

    public static let oneToOne = Template(id: "one-to-one", name: "1:1", instructions: """
        1. A short summary of the conversation.
        2. "## Updates": what each person reported, with specifics.
        3. "## Feedback and concerns": what was raised, by whom, and how it was received.
        4. "## Next Steps": bullets — the task in bold, the owner in parentheses, one sentence of reasoning.
        """, builtin: true)

    public static let weeklyTeam = Template(id: "weekly-team", name: "Weekly team meeting", instructions: """
        1. A short summary of the meeting.
        2. "## Progress": what moved since last time, per topic, with numbers where given.
        3. "## Blockers and risks": what is stuck, who is affected.
        4. "## Decisions": what was decided and by whom.
        5. "## Next Steps": bullets — the task in bold, the owner in parentheses, one sentence of reasoning.
        """, builtin: true)

    public static let discoveryCall = Template(id: "discovery-call", name: "Customer: Discovery", instructions: """
        1. A short summary: who the customer is and why they called.
        2. "## Needs and pain points": in the customer's own terms, with specifics.
        3. "## Current situation": tools, process, constraints they described.
        4. "## Objections and open questions".
        5. "## Next Steps": bullets — the task in bold, the owner in parentheses, one sentence of reasoning.
        """, builtin: true)

    public static let builtIns: [Template] = [standard, oneToOne, weeklyTeam, discoveryCall]
}

public enum TemplateError: Error, Equatable {
    case builtinIsReadOnly
    case nameTaken(String)
    case missingName
}

/// Własne szablony użytkownika (`templates.json`). Wbudowane żyją w kodzie, nie w pliku.
public struct TemplatesFile: Codable, Equatable, Sendable {
    public var templates: [Template] = []
    public init(templates: [Template] = []) { self.templates = templates }

    public func all() -> [Template] { Template.builtIns + templates }

    public mutating func upsert(_ t: Template) throws {
        guard !t.builtin, !Template.builtIns.contains(where: { $0.id == t.id }) else { throw TemplateError.builtinIsReadOnly }
        let name = t.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw TemplateError.missingName }
        guard !all().contains(where: { $0.id != t.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw TemplateError.nameTaken(name)
        }
        var t = t
        t.name = name
        if let i = templates.firstIndex(where: { $0.id == t.id }) { templates[i] = t } else { templates.append(t) }
    }

    public mutating func remove(id: String) { templates.removeAll { $0.id == id } }
}
