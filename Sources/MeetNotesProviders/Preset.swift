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

/// Wybór języka w edytorze presetu. `auto` to opcja awaryjna (spotkania mieszane), nigdy domyślna.
public enum LanguageChoice: Hashable, Sendable {
    case unset
    case auto
    case code(LanguageCode)
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

    /// `true` = język „Auto" (spec 1.5 §3.8): tylko razem z `language == nil`. Opcjonalne — stare pliki go nie mają.
    public var languageAuto: Bool?

    public init(id: UUID = UUID(), name: String, language: LanguageCode?, asr: RoleAssignment?,
                correction: RoleAssignment? = nil, summary: RoleAssignment? = nil, notesLanguage: LanguageCode? = nil,
                languageAuto: Bool? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.asr = asr
        self.correction = correction
        self.summary = summary
        self.notesLanguage = notesLanguage
        self.languageAuto = languageAuto
    }

    public var isAutoLanguage: Bool { language == nil && languageAuto == true }

    /// Krótka etykieta do list i chipów: „PL", „Auto ⚠", „?".
    public var languageLabel: String { isAutoLanguage ? "Auto ⚠" : (language?.rawValue.uppercased() ?? "?") }

    public var languageChoice: LanguageChoice {
        get { isAutoLanguage ? .auto : (language.map { .code($0) } ?? .unset) }
        set {
            switch newValue {
            case .unset: language = nil; languageAuto = nil
            case .auto: language = nil; languageAuto = true
            case .code(let c): language = c; languageAuto = nil
            }
        }
    }

    public var effectiveNotesLanguage: LanguageCode? { notesLanguage ?? language }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingName }
        guard language != nil || isAutoLanguage else { throw PresetError.missingLanguage }
        guard let asr, !asr.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingASR }
    }
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    /// Jeden model embeddingu dla całego archiwum (P13).
    public var embedding: RoleAssignment?
    public var defaultPresetID: UUID?
    /// Folder ze wszystkimi spotkaniami (ścieżka, nie `URL` — Codable `URL` pisze obiekt). `nil` = `<dane>/sessions`.
    /// Opcjonalne (E6), jak oba pola niżej.
    public var recordingsPath: String?
    /// Ile dni trzymać audio spotkania; `nil` = `defaultKeepAudioDays`. Czytaj przez `audioRetentionDays`.
    public var keepAudioDays: Int?
    /// `true` = audio zostaje na zawsze. Osobna flaga, bo żadna liczba dni nie może znaczyć „nigdy” (0 skasowałoby wszystko).
    public var keepAudioForever: Bool?

    public static let defaultKeepAudioDays = 30

    public init(embedding: RoleAssignment? = nil, defaultPresetID: UUID? = nil, recordingsPath: String? = nil,
                keepAudioDays: Int? = nil, keepAudioForever: Bool? = nil) {
        self.embedding = embedding
        self.defaultPresetID = defaultPresetID
        self.recordingsPath = recordingsPath
        self.keepAudioDays = keepAudioDays
        self.keepAudioForever = keepAudioForever
    }

    /// Retencja audio w dniach; `nil` = Forever (nic nie kasujemy). Co najmniej 1 dzień.
    public var audioRetentionDays: Int? {
        keepAudioForever == true ? nil : max(keepAudioDays ?? Self.defaultKeepAudioDays, 1)
    }

    /// Zmiana modelu embeddingu przeindeksuje całe archiwum (P13) — pytamy tylko, gdy jakiś model już był.
    public static func embeddingChangeNeedsConfirmation(old: RoleAssignment?, new: RoleAssignment?) -> Bool {
        guard let old else { return false }
        return old.providerID != new?.providerID || old.model != new?.model
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
