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

    public init(id: UUID = UUID(), name: String, baseURL: URL, kind: ProviderKind? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
    }

    public var api: ProviderKind { kind ?? .openAICompatible }
}

/// Rodzaj API: OpenAI-compatible (OpenRouter, Ollama, własny serwer) albo ElevenLabs bezpośrednio
/// (`xi-api-key`, multipart, Scribe v2 — macos.md §11.5, odbiór 2026-10-16).
public enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case elevenLabs
}

public enum ProviderError: Error, Equatable {
    case http(Int, String)
    case badResponse(String)
    case missingKey
}
