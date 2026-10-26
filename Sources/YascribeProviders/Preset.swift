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

    /// „Fully local": każda **przypisana** rola (ASR, korekta, podsumowanie) ma dostawcę lokalnego (`Provider.isLocal`). Pusta rola
    /// się nie liczy; nieznany dostawca psuje wynik; preset bez żadnej roli nie jest „fully local". Embedding jest globalny, poza presetem.
    public func isFullyLocal(providers: [Provider]) -> Bool {
        let assigned = [asr, correction, summary].compactMap { $0 }
        return !assigned.isEmpty && assigned.allSatisfy { a in providers.first { $0.id == a.providerID }?.isLocal ?? false }
    }

    /// Kopia do jednorazowego „Transcribe again": podmienia tylko `asr` i język (`id`, `name`, korekta, podsumowanie bez zmian).
    /// `language == nil` = jawny wybór „Auto" (opcja awaryjna), nie brak wyboru — wynik nadal przechodzi `validate()`.
    public func withASR(_ asr: RoleAssignment, language: LanguageCode?) -> Preset {
        var copy = self
        copy.asr = asr
        copy.languageChoice = language.map { .code($0) } ?? .auto
        return copy
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingName }
        guard language != nil || isAutoLanguage else { throw PresetError.missingLanguage }
        guard let asr, !asr.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingASR }
    }
}

public struct MeetingSettings: Codable, Equatable, Sendable {
    /// Włączyć detekcję rozmów Teams (nigdy samego kalendarza do auto-startu).
    public var detectCalls: Bool?
    /// Automatycznie nagrywaj rozmowę Teams (tylko, nigdy samo wydarzenie kalendarza).
    public var autoStart: Bool?
    /// Uruchamiaj aplikację przy logowaniu.
    public var launchAtLogin: Bool?
    /// Włączyć dostęp do Kalendarza Apple.
    public var appleCalendarEnabled: Bool?
    /// ID kalendarzy Apple do śledzenia; `nil` = wszystkie dostępne.
    public var calendarIDs: [String]?
    /// Nadpisanie progu dla ciągłego użycia mikrofonu rozmowy, zanim padnie oferta (sekundy; `nil` = domyślny z T0).
    public var startSeconds: Double?
    /// Nadpisanie progu dla zwolnienia mikrofonu (sekundy; `nil` = domyślny).
    public var releaseSeconds: Double?
    /// Nadpisanie progu dla ciszy (sekundy; `nil` = domyślny).
    public var silenceSeconds: Double?
    /// Aplikacje do ignorowania przy detekcji (np. dyktowanie).
    public var ignoredApps: [String]?

    public init(detectCalls: Bool? = nil, autoStart: Bool? = nil, launchAtLogin: Bool? = nil,
                appleCalendarEnabled: Bool? = nil, calendarIDs: [String]? = nil,
                startSeconds: Double? = nil, releaseSeconds: Double? = nil, silenceSeconds: Double? = nil,
                ignoredApps: [String]? = nil) {
        self.detectCalls = detectCalls
        self.autoStart = autoStart
        self.launchAtLogin = launchAtLogin
        self.appleCalendarEnabled = appleCalendarEnabled
        self.calendarIDs = calendarIDs
        self.startSeconds = startSeconds
        self.releaseSeconds = releaseSeconds
        self.silenceSeconds = silenceSeconds
        self.ignoredApps = ignoredApps
    }

    public var detectCallsOrDefault: Bool { detectCalls ?? true }
    public var autoStartOrDefault: Bool { autoStart ?? false }
    public var launchAtLoginOrDefault: Bool { launchAtLogin ?? false }
    public var appleCalendarOrDefault: Bool { appleCalendarEnabled ?? false }
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
    /// Ustawienia detekcji spotkań i kalendarza (opcjonalne, E6).
    public var meetings: MeetingSettings?
    /// Czy model API może „myśleć" przy podsumowaniu (F20 P1). `nil` = tak, jak dotąd (nic nie wysyłamy). Czytaj przez `summaryThinkingEnabled`.
    public var summaryThinking: Bool?
    /// Usuwanie przerywników z poprawionego transkryptu (F20 P2). Opcjonalne (E6): `nil` = włączone, domyślna lista (`FillerWords.defaults`).
    public var removeFillers: Bool?
    /// Własna lista przerywników; `nil` = domyślna.
    public var fillerWords: [String]?

    public static let defaultKeepAudioDays = 30

    public var summaryThinkingEnabled: Bool { summaryThinking ?? true }
    public var removeFillersEnabled: Bool { removeFillers ?? true }

    public init(embedding: RoleAssignment? = nil, defaultPresetID: UUID? = nil, recordingsPath: String? = nil,
                keepAudioDays: Int? = nil, keepAudioForever: Bool? = nil, meetings: MeetingSettings? = nil,
                summaryThinking: Bool? = nil, removeFillers: Bool? = nil, fillerWords: [String]? = nil) {
        self.removeFillers = removeFillers
        self.fillerWords = fillerWords
        self.summaryThinking = summaryThinking
        self.embedding = embedding
        self.defaultPresetID = defaultPresetID
        self.recordingsPath = recordingsPath
        self.keepAudioDays = keepAudioDays
        self.keepAudioForever = keepAudioForever
        self.meetings = meetings
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
