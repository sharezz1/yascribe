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
        case .elevenLabs: return false
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

    /// Jedyna bramka klucza (`AppModel.providerWithKey`): lokalny dostawca obejdzie się bez niego.
    public var requiresKey: Bool { !isLocal }
}

/// Rodzaj API: OpenAI-compatible (OpenRouter, Ollama, własny serwer) albo ElevenLabs bezpośrednio
/// (`xi-api-key`, multipart, Scribe v2 — macos.md §11.5, odbiór 2026-10-16).
public enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case elevenLabs
    /// Parakeet w procesie (`MeetNotesLocalASR`); bez adresu i bez klucza.
    case fluidAudio
}

/// Klient, który trzyma zasoby (model ASR w pamięci); aplikacja woła `release()` po przebiegu.
public protocol ReleasableClient: Sendable {
    func release() async
}

/// Zaślepka dla `.fluidAudio` w `MeetNotesProviders`, który nie może zależeć od `MeetNotesLocalASR`.
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
}
