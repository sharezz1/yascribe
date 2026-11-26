import Foundation

/// Reguły auto-wyboru presetu (TASK-115). Wszystkie warunki w jednym presecie są OR.
public struct PresetRules: Codable, Equatable, Sendable {
    public var titleContains: [String]?
    public var attendeeDomains: [String]?
    public var apps: [String]?

    public init(titleContains: [String]? = nil, attendeeDomains: [String]? = nil, apps: [String]? = nil) {
        self.titleContains = titleContains
        self.attendeeDomains = attendeeDomains
        self.apps = apps
    }

    /// Puste reguły nie mogą niczego wybrać — same białe znaki też się nie liczą.
    public var isEmpty: Bool {
        let t = (titleContains ?? []).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let d = (attendeeDomains ?? []).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let a = (apps ?? []).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !(t || d || a)
    }
}

public struct PresetMatch: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case title(String)
        case domain(String)
        case app(String)
    }

    public var presetID: UUID
    public var reason: Reason

    public init(presetID: UUID, reason: Reason) {
        self.presetID = presetID
        self.reason = reason
    }
}

public enum PresetRuleMatcher {
    /// Kolejność presetów jest priorytetem: wygrywa pierwszy pasujący. Niepoprawne presety pomijamy.
    public static func match(presets: [Preset], title: String?, attendeeEmails: [String],
                             app: String?) -> PresetMatch? {
        for preset in presets {
            guard (try? preset.validate()) != nil, let rules = preset.rules, !rules.isEmpty else { continue }

            if let title, let fragment = firstTitleFragment(in: rules.titleContains, title: title) {
                return PresetMatch(presetID: preset.id, reason: .title(fragment))
            }
            if let domain = firstMatchingDomain(in: rules.attendeeDomains, emails: attendeeEmails) {
                return PresetMatch(presetID: preset.id, reason: .domain(domain))
            }
            if let app, let hit = rules.apps?.first(where: { $0 == app }) {
                return PresetMatch(presetID: preset.id, reason: .app(hit))
            }
        }
        return nil
    }

    private static func firstTitleFragment(in fragments: [String]?, title: String) -> String? {
        for raw in fragments ?? [] {
            let fragment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fragment.isEmpty else { continue }
            if title.range(of: fragment, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return fragment
            }
            // Foundation nie zwija `ł` (to nie znak diakrytyczny), więc dodatkowo mapujemy je ręcznie.
            if fold(title).range(of: fold(fragment)) != nil {
                return fragment
            }
        }
        return nil
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "L")
    }

    private static func firstMatchingDomain(in rules: [String]?, emails: [String]) -> String? {
        let ruleDomains = (rules ?? []).map(normalizeDomain).filter { !$0.isEmpty }
        guard !ruleDomains.isEmpty else { return nil }
        let emailDomains = emails.compactMap(emailDomain)
        for rule in ruleDomains where emailDomains.contains(where: { $0 == rule || $0.hasSuffix("." + rule) }) {
            return rule
        }
        return nil
    }

    private static func normalizeDomain(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        return value
    }

    private static func emailDomain(_ email: String) -> String? {
        guard let at = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: at)...].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return domain.isEmpty ? nil : domain
    }
}
