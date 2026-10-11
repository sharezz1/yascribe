import Foundation

public struct RoleAssignment: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var model: String
    public var prompt: String?

    public init(providerID: UUID, model: String, prompt: String? = nil) {
        self.providerID = providerID
        self.model = model
        self.prompt = prompt
    }
}

public enum PresetError: Error, Equatable {
    case missingName
    /// P7: bramka, nie ostrzeżenie.
    case missingLanguage
    case missingASR
}

/// Nazwany zestaw: język + ASR + korekta + podsumowanie (spec fazy 1, §1.5).
/// 🔴 Bez embeddingu — ten jest globalny (`GlobalSettings`), bo wektory
/// z różnych modeli nie są porównywalne.
public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Opcjonalny tylko w trakcie edycji. `validate()` nie przepuści `nil`.
    public var language: LanguageCode?
    public var asr: RoleAssignment?
    public var correction: RoleAssignment?
    public var summary: RoleAssignment?
    /// `nil` = jak język presetu (kopia jawnego wyboru, nie wykrywanie — §1.4).
    public var notesLanguage: LanguageCode?

    public init(id: UUID = UUID(), name: String, language: LanguageCode?, asr: RoleAssignment?,
                correction: RoleAssignment? = nil, summary: RoleAssignment? = nil, notesLanguage: LanguageCode? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.asr = asr
        self.correction = correction
        self.summary = summary
        self.notesLanguage = notesLanguage
    }

    public var effectiveNotesLanguage: LanguageCode? { notesLanguage ?? language }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingName }
        guard language != nil else { throw PresetError.missingLanguage }
        guard let asr, !asr.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingASR }
    }
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    /// Jeden model embeddingu dla całego archiwum (P13).
    public var embedding: RoleAssignment?
    public var defaultPresetID: UUID?

    public init(embedding: RoleAssignment? = nil, defaultPresetID: UUID? = nil) {
        self.embedding = embedding
        self.defaultPresetID = defaultPresetID
    }
}

public struct ProbeCache: Codable, Equatable, Sendable {
    public var results: [String: ProbeResult] = [:]

    public init() {}

    static func key(_ provider: UUID, _ model: String, _ role: Role, _ language: LanguageCode?) -> String {
        "\(provider.uuidString)|\(model)|\(role.rawValue)|\(language?.rawValue ?? "-")"
    }

    public mutating func record(_ r: ProbeResult) { results[Self.key(r.providerID, r.model, r.role, r.language)] = r }

    public func result(provider: UUID, model: String, role: Role, language: LanguageCode? = nil) -> ProbeResult? {
        results[Self.key(provider, model, role, language)]
    }
}
