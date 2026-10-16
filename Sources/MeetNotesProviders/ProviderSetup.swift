import Foundation

/// Gotowi dostawcy listy w Settings (macos.md §11.5): użytkownik wkleja tylko klucz, adres jest wpisany.
/// Modele zostają w presetach; dostawcy — w Settings.
public struct ProviderPreset: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var needsKey: Bool
    public var note: String?
    /// Opis roli pod nazwą w wierszu listy i w nagłówku arkusza.
    public var role: String
    /// API dostawcy; `nil` = OpenAI-compatible (jak `Provider.kind`).
    public var kind: ProviderKind?
    /// Strona z kluczem API („Get an API key"); Ollama i Custom nie mają.
    public var keyPage: URL?

    public static let openRouter = ProviderPreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
                                                  needsKey: true, note: nil,
                                                  role: "Transcription, correction and summary · hundreds of models",
                                                  kind: nil, keyPage: URL(string: "https://openrouter.ai/keys"))
    /// ElevenLabs bezpośrednio: Scribe v2, klucz w nagłówku `xi-api-key` (decyzja 2026-10-16).
    public static let elevenLabs = ProviderPreset(id: "elevenlabs", name: "ElevenLabs", baseURL: "https://api.elevenlabs.io/v1",
                                                  needsKey: true, note: nil,
                                                  role: "Scribe v2 transcription · direct API",
                                                  kind: .elevenLabs, keyPage: URL(string: "https://elevenlabs.io/app/settings/api-keys"))
    /// Ollama nie robi ASR (docs/wymagania.md §2): tylko korekta i podsumowanie.
    public static let ollama = ProviderPreset(id: "ollama", name: "Ollama", baseURL: "http://localhost:11434/v1", needsKey: false,
                                              note: "correction and summary only, no transcription",
                                              role: "Runs on this Mac · correction and summary only, no transcription",
                                              kind: nil, keyPage: nil)
    public static let custom = ProviderPreset(id: "custom", name: "Custom endpoint", baseURL: "", needsKey: true,
                                              note: "Any OpenAI-compatible server.",
                                              role: "Any OpenAI-compatible API · address and key",
                                              kind: nil, keyPage: nil)
    public static let all: [ProviderPreset] = [openRouter, elevenLabs, ollama, custom]
    /// Gotowi (z wpisanym adresem), w kolejności listy.
    public static let ready: [ProviderPreset] = [openRouter, elevenLabs, ollama]

    /// Adres bez schematu: host[:port] + ścieżka bez końcowego „/” („openrouter.ai/api/v1"). Służy też do porównań.
    public static func displayAddress(_ url: URL) -> String {
        var path = url.path()
        while path.hasSuffix("/") { path.removeLast() }
        return (url.host() ?? "") + (url.port.map { ":\($0)" } ?? "") + path
    }

    /// Porównanie jak `displayAddress`, ale host bez rozróżniania wielkości liter (ścieżka je rozróżnia).
    static func addressKey(_ url: URL) -> String {
        let shown = displayAddress(url)
        let hostLength = (url.host() ?? "").count
        return shown.prefix(hostLength).lowercased() + shown.dropFirst(hostLength)
    }

    /// Gotowy dostawca pasujący do zapisanego dostawcy (rodzaj API, a dla OpenAI-compatible adres); Custom nigdy.
    public static func matching(_ provider: Provider) -> ProviderPreset? {
        if provider.api == .elevenLabs { return elevenLabs }
        return [openRouter, ollama].first { URL(string: $0.baseURL).map(addressKey) == addressKey(provider.baseURL) }
    }

    /// Dopasowanie samego adresu (bez rodzaju API).
    public static func matching(_ url: URL) -> ProviderPreset? {
        matching(Provider(name: "", baseURL: url))
    }
}

/// Wiersz karty Providers: gotowy dostawca (z zapisanym albo bez), własny adres albo „Custom endpoint" na końcu.
public enum ProviderListRow: Identifiable, Equatable, Sendable {
    case preset(ProviderPreset, Provider?)
    case custom(Provider)
    case addCustom

    public var id: String {
        switch self {
        case .preset(let p, _): "preset-\(p.id)"
        case .custom(let p): "custom-\(p.id.uuidString)"
        case .addCustom: "add-custom"
        }
    }

    /// Lista wszystkich obsługiwanych dostawców jeden pod drugim, także nieskonfigurowanych: OpenRouter, ElevenLabs, Ollama,
    /// potem zapisani własni (także drugi OpenRouter — dostawca to instancja), na końcu „Custom endpoint".
    public static func rows(for providers: [Provider]) -> [ProviderListRow] {
        var used = Set<UUID>()
        var rows: [ProviderListRow] = ProviderPreset.ready.map { preset in
            let match = providers.first { !used.contains($0.id) && ProviderPreset.matching($0) == preset }
            if let match { used.insert(match.id) }
            return .preset(preset, match)
        }
        rows += providers.filter { !used.contains($0.id) }.map { .custom($0) }
        rows.append(.addCustom)
        return rows
    }
}

/// Archive search (macos.md §11.5, uwaga 6): wybór dostawcy i modelu embeddingu.
public enum EmbeddingChoice {
    /// Dostawcy z listą modeli embeddingu: OpenAI-compatible (ElevenLabs nie ma embeddingów).
    public static func providers(_ providers: [Provider]) -> [Provider] {
        providers.filter { $0.api == .openAICompatible }
    }

    /// Zmiana dostawcy czyści model (inny dostawca = inna lista); ten sam dostawca zachowuje wybór. `nil` = brak embeddingu.
    public static func select(provider id: UUID?, current: RoleAssignment?) -> RoleAssignment? {
        guard let id else { return nil }
        if let current, current.providerID == id { return current }
        return RoleAssignment(providerID: id, model: "")
    }

    /// Wiersz „Provider" jest zbędny, gdy do wyboru jest najwyżej jeden dostawca.
    public static func showsProviderRow(candidates: [Provider]) -> Bool { candidates.count > 1 }
}

/// Wynik próby połączenia po dodaniu dostawcy (`listModels`): „✓ Verified" albo powód po ludzku.
public enum ProviderCheck: Equatable, Sendable {
    case verified(models: Int)
    case failed(String)

    public static func describe(_ error: Error) -> String {
        if let p = error as? ProviderError {
            switch p {
            case .http(401, _): return "Invalid API key."
            case .http(403, _): return "Not allowed: check the key's permissions and your provider's guardrails."
            case .http(404, _): return "Wrong address: the server has no model list at this URL."
            case .http(429, _): return "Rate limited. Try again in a moment."
            case .http(let status, _): return "The server answered with error \(status)."
            case .badResponse: return "The answer wasn't a model list. Is this an OpenAI-compatible address?"
            case .missingKey: return "No API key."
            }
        }
        if let u = error as? URLError {
            switch u.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "Can't connect. Is the server running and the address correct?"
            case .timedOut: return "The server didn't answer in time."
            default: break
            }
        }
        return error.localizedDescription
    }
}

public extension OpenAICompatibleClient {
    func verify() async -> ProviderCheck {
        do { return .verified(models: try await listModels().count) } catch { return .failed(ProviderCheck.describe(error)) }
    }
}
