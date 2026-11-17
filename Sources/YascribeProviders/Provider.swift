import Foundation

/// Dostawca to **instancja**, nie typ: dwa OpenRoutery z różnymi kluczami to dwaj
/// dostawcy (spec fazy 1, §3). Klucz nie jest polem tej struktury — mieszka
/// w pęku kluczy, pod `id`.
public struct Provider: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Np. `https://openrouter.ai/api/v1`, `http://localhost:11434/v1`.
    public var baseURL: URL
    /// API dostawcy. Opcjonalne (E6): `nil` w starych `providers.json` = OpenAI-compatible.
    public var kind: ProviderKind?
    /// Okno kontekstu serwera lokalnego (tokeny), wpisywane przez użytkownika. Opcjonalne (E6): `nil` = 4096 (`ContextBudget`).
    public var contextTokens: Int?

    public init(id: UUID = UUID(), name: String, baseURL: URL, kind: ProviderKind? = nil, contextTokens: Int? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
        self.contextTokens = contextTokens
    }

    public var api: ProviderKind { kind ?? .openAICompatible }

    /// Adres „dostawcy" transkrypcji w procesie (FluidAudio) — nie jest adresem sieciowym.
    public static let fluidAudioBaseURL = URL(string: "local://fluidaudio")!

    /// „Lokalny" = ta maszyna: `.fluidAudio` albo OpenAI-compatible na loopbacku. LAN, tunel i host zdalny to nie lokalny;
    /// ElevenLabs to zawsze chmura, nawet gdy ktoś wskaże mu loopback.
    public var isLocal: Bool {
        switch api {
        case .fluidAudio: return true
        case .elevenLabs, .mistral, .codexCLI, .claudeCLI: return false // agent CLI wysyła transkrypt do OpenAI/Anthropic
        case .openAICompatible:
            var host = baseURL.host()?.lowercased() ?? ""
            if host.hasSuffix(".") { host.removeLast() } // FQDN: „localhost."
            return host == "localhost" || host == "::1" || host == "0.0.0.0" || host.hasSuffix(".localhost") || Self.isLoopbackIPv4(host)
        }
    }

    /// `127.0.0.0/8`: cztery liczbowe oktety, pierwszy = 127 (nie „127.evil.com").
    private static func isLoopbackIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets[0] == "127" && octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// Jedyna bramka klucza (`AppModel.providerWithKey`): lokalny dostawca obejdzie się bez niego, agent CLI też —
    /// logowanie zostaje w CLI (subskrypcja albo klucz w CLI), Yascribe nie trzyma żadnego klucza (TASK-86).
    public var requiresKey: Bool { !isLocal && !api.isAgentCLI }

    /// Czy dostawca może obsłużyć rolę (F20 P4). Poprawa, podsumowanie i embedding to czat/embeddingi OpenAI-compatible;
    /// ElevenLabs (sam ASR) i Yascribe (Parakeet, sam ASR) ich nie mają. ASR: wszyscy poza agentem CLI (o wyniku decyduje sonda).
    /// Agent CLI (TASK-86) robi tylko czat: poprawę i podsumowanie.
    public func supports(_ role: Role) -> Bool {
        if api == .mistral { return false }
        return switch role {
        case .asr: !api.isAgentCLI
        case .correction, .summary: api == .openAICompatible || api.isAgentCLI
        case .embedding: api == .openAICompatible
        }
    }

    /// Nazwa w menu dostawcy roli: model w procesie to „Yascribe", a nie dostawca. Zapisany rekord i jego nazwa zostają bez zmian.
    public var roleLabel: String { api == .fluidAudio ? "Yascribe" : name }
}

public enum RoleProviders {
    /// Dostawcy do wyboru w roli presetu: ci, którzy ją obsługują, plus bieżący wybór, gdy zapisany preset już wskazuje
    /// nieobsługującego — menu nie pokaże „None" przy istniejącym przypisaniu i nic nie ginie po cichu.
    public static func choices(_ providers: [Provider], role: Role, current: UUID?) -> [Provider] {
        providers.filter { $0.supports(role) || $0.id == current }
    }
}

/// Dokąd trafia tekst przy wybranym agencie CLI (TASK-86, §6): podpis przy każdym wyborze dostawcy korekty i podsumowania.
public enum AgentPrivacy {
    public static func caption(_ provider: Provider?) -> String? {
        guard let provider, let vendor = provider.api.agentVendor else { return nil }
        return "The transcript goes to \(vendor) through \(provider.api == .codexCLI ? "Codex" : "Claude Code"), with your sign-in in that app."
    }
}

/// Korekta dyktowania bez agentów CLI (TASK-86, R3): start trwa sekundy, a dyktowanie czeka na wynik.
public enum DictationChoices {
    /// Jak `RoleProviders.choices(role: .correction)`, ale bez CLI — poza bieżącym zapisanym wyborem, żeby nic nie znikło po cichu.
    public static func correction(_ providers: [Provider], current: UUID?) -> [Provider] {
        RoleProviders.choices(providers, role: .correction, current: current).filter { !$0.api.isAgentCLI || $0.id == current }
    }

    /// Jawny błąd, gdy zapisana korekta dyktowania wskazuje agenta CLI; `nil` = dozwolony.
    public static func refusal(_ provider: Provider?) -> ProviderError? {
        guard let provider, provider.api.isAgentCLI else { return nil }
        return .agentFailed("\(provider.name) can't correct dictation. Pick another model in Dictation settings.")
    }
}

/// Rodzaj API: OpenAI-compatible (OpenRouter, Ollama, własny serwer) albo ElevenLabs bezpośrednio
/// (`xi-api-key`, multipart, Scribe v2 — macos.md §11.5, odbiór 2026-10-16).
public enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case elevenLabs
    case mistral
    /// Parakeet w procesie (`YascribeLocalASR`); bez adresu i bez klucza.
    case fluidAudio
    /// Agent CLI na tym Macu (TASK-86): `codex exec` / `claude -p` z logowaniem użytkownika w CLI. `baseURL` = `file://` binarki.
    case codexCLI
    case claudeCLI

    public var isAgentCLI: Bool { self == .codexCLI || self == .claudeCLI }

    /// Dokąd agent wysyła transkrypt (podpis w interfejsie).
    public var agentVendor: String? {
        switch self {
        case .codexCLI: "OpenAI"
        case .claudeCLI: "Anthropic"
        default: nil
        }
    }
}

/// Klient, który trzyma zasoby (model ASR w pamięci); aplikacja woła `release()` po przebiegu.
public protocol ReleasableClient: Sendable {
    func release() async
}

/// Zaślepka dla `.fluidAudio` w `YascribeProviders`, który nie może zależeć od `YascribeLocalASR`.
/// Aplikacja podstawia prawdziwego klienta; tu zawsze błąd — nigdy sieć, nigdy cichy fallback.
public struct UnlinkedLocalClient: TranscriptionClient {
    public let provider: Provider
    public init(provider: Provider) { self.provider = provider }

    public func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        throw ProviderError.badResponse("On-device transcription isn't linked in this build.")
    }
}

public enum ProviderError: Error, Equatable {
    case http(Int, String)
    case badResponse(String)
    case missingKey
    /// `finish_reason: "length"` — serwer uciął wyjście (limit tokenów albo kontekstu); odpowiedź nie jest pełna.
    case replyCutOff
    /// Lokalny serwer po cichu obciął wejście (HTTP 200, `finish_reason: "stop"`): przeczytał `readTokens` tokenów z `sentChars`
    /// znaków promptu (`OpenAICompatibleClient.truncationRatio`). Odpowiedź dotyczy ogona promptu, więc nie jest wynikiem.
    case inputTruncated(sentChars: Int, readTokens: Int)
    /// Agent CLI (TASK-86) nie jest zalogowany; tekst mówi, jak się zalogować w Terminalu.
    case agentNotSignedIn(String)
    /// Agent CLI użył narzędzia (polecenie, przeglądarka…) — odpowiedź odrzucona, korekta przerwana (spec §4.5).
    case agentUsedTool(String)
    /// Agent CLI zawiódł (kod wyjścia, przerwany turn, niezweryfikowana wersja, limit czasu); tekst do pokazania.
    case agentFailed(String)
}

extension ProviderError {
    /// Błąd agenta CLI (logowanie, narzędzie, proces) — opis dla użytkownika daje `ProviderCheck.describe`.
    public var isAgentError: Bool {
        switch self {
        case .agentNotSignedIn, .agentUsedTool, .agentFailed: true
        default: false
        }
    }
}
