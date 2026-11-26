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

    /// Tekst z edytora na listę reguł; puste pole to nil. Puste linie zostają, żeby wpisanie nowej linii działało (matcher je pomija).
    public static func lines(_ text: String) -> [String]? {
        text.isEmpty ? nil : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Lista reguł z powrotem do tekstu edytora; nil daje puste pole.
    public static func text(_ lines: [String]?) -> String {
        (lines ?? []).joined(separator: "\n")
    }

    /// Reguły z trzech pól edytora; nil, gdy wszystkie trzy są puste.
    public static func make(titleText: String, domainText: String, apps: [String]?) -> PresetRules? {
        let title = lines(titleText)
        let domains = lines(domainText)
        let apps = (apps?.isEmpty ?? true) ? nil : apps
        guard title != nil || domains != nil || apps != nil else { return nil }
        return PresetRules(titleContains: title, attendeeDomains: domains, apps: apps)
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

/// Stan auto-wyboru presetu (TASK-115). Auto NIGDY nie nadpisuje ręcznego `activePresetID`; ręczny wybór zawsze wygrywa.
public struct AutoPresetState: Equatable, Sendable {
    public private(set) var match: PresetMatch?
    public private(set) var key: String?
    // shortcut: zbiór rośnie przez życie procesu (po jednym id wydarzenia), znikomy koszt; przyciąć, gdy kiedykolwiek urośnie
    private var overriddenKeys: Set<String> = []
    private var pageOverride = false
    public init() {}
    /// Wynik reguł dla kontekstu (oferta albo wydarzenie); nil, gdy użytkownik wybrał ręcznie dla tego klucza albo w menu strony.
    public func candidate(presets: [Preset], key: String, title: String?, attendeeEmails: [String], app: String?) -> PresetMatch? {
        guard !pageOverride, !overriddenKeys.contains(key) else { return nil }
        return PresetRuleMatcher.match(presets: presets, title: title, attendeeEmails: attendeeEmails, app: app)
    }
    /// Idempotentne dla tego samego klucza (powtórne `present` nie przelicza i nie gubi wyniku z aplikacją).
    public mutating func apply(presets: [Preset], key: String, title: String?, attendeeEmails: [String], app: String?) {
        guard key != self.key else { return }
        self.key = key
        match = candidate(presets: presets, key: key, title: title, attendeeEmails: attendeeEmails, app: app)
    }
    /// key != nil: wybór w pigułce dla oferty/wydarzenia o tym kluczu; key == nil: wybór w menu strony (dotyczy najbliższego nagrania). Zawsze zdejmuje bieżące dopasowanie.
    public mutating func chooseManually(key: String?) {
        if let key { overriddenKeys.insert(key) } else { pageOverride = true }
        if let current = self.key { overriddenKeys.insert(current) }
        match = nil
    }
    /// Oferta znikła (dismiss/ukrycie): zdejmuje dopasowanie i klucz, zostawia ręczne wybory.
    public mutating func clearContext() {
        match = nil
        key = nil
    }
    /// Nagranie wystartowało: preset zamrożony w sesji; zużywa wybór ze strony.
    public mutating func consume() {
        match = nil
        key = nil
        pageOverride = false
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
