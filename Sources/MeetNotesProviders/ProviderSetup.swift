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
    /// Klucz możliwy, ale niewymagany (oMLX: użytkownik może go ustawić w serwerze). Pusty klucz nie trafia do pęku.
    public var keyOptional: Bool = false

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
    /// llama.cpp (`llama-server`, domyślny port 8080): jak Ollama, korekta i podsumowanie; ASR rozstrzyga sonda.
    public static let llamaCpp = ProviderPreset(id: "llamacpp", name: "llama.cpp", baseURL: "http://localhost:8080/v1", needsKey: false,
                                                note: nil, role: "Runs on this Mac · correction and summary",
                                                kind: nil, keyPage: nil)
    /// oMLX (port 8000 z jego konfiguracji): serwer użytkownika może mieć ustawiony klucz API (S2 §6: 401), więc klucz jest opcjonalny.
    public static let omlx = ProviderPreset(id: "omlx", name: "oMLX", baseURL: "http://localhost:8000/v1", needsKey: false,
                                            note: nil, role: "Runs on this Mac · correction and summary",
                                            kind: nil, keyPage: nil, keyOptional: true)
    /// Parakeet w procesie (FluidAudio): bez klucza i bez adresu sieciowego (`local://fluidaudio`), tylko transkrypcja.
    public static let onThisMac = ProviderPreset(id: "on-this-mac", name: "On this Mac · Parakeet",
                                                 baseURL: Provider.fluidAudioBaseURL.absoluteString, needsKey: false, note: nil,
                                                 role: "Speech-to-text on this Mac · no network",
                                                 kind: .fluidAudio, keyPage: nil)
    public static let custom = ProviderPreset(id: "custom", name: "Custom endpoint", baseURL: "", needsKey: true,
                                              note: "Any OpenAI-compatible server.",
                                              role: "Any OpenAI-compatible API · address and key",
                                              kind: nil, keyPage: nil)
    public static let all: [ProviderPreset] = [openRouter, elevenLabs, ollama, llamaCpp, omlx, custom]
    /// Gotowi (z wpisanym adresem), w kolejności listy.
    public static let ready: [ProviderPreset] = [openRouter, elevenLabs, ollama, llamaCpp, omlx, onThisMac]

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
        if provider.api == .fluidAudio { return onThisMac } // po rodzaju, nie po adresie: `local://` nie ma hosta
        return [openRouter, ollama, llamaCpp, omlx].first { URL(string: $0.baseURL).map(addressKey) == addressKey(provider.baseURL) }
    }

    /// Dopasowanie samego adresu (bez rodzaju API).
    public static func matching(_ url: URL) -> ProviderPreset? {
        matching(Provider(name: "", baseURL: url))
    }
}

/// Jedyny model lokalnego ASR. Stała w `MeetNotesProviders`, żeby `AppModel.loadModels` nie importował `MeetNotesLocalASR`.
public enum LocalASRModels {
    public static let parakeetV3 = "parakeet-tdt-0.6b-v3"

    /// Modele dla roli — stała lista, bez sieci (jak `ElevenLabsClient.models`). Poza ASR pusto.
    public static func models(for role: Role) -> [ModelInfo] {
        role == .asr ? [ModelInfo(id: parakeetV3, inputModalities: ["audio"], outputModalities: ["transcription"])] : []
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

    /// Lista wszystkich obsługiwanych dostawców jeden pod drugim, także nieskonfigurowanych: OpenRouter, ElevenLabs, Ollama, On this Mac,
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
    /// Klucz działa do transkrypcji, ale test przez listę modeli go odrzucił (ElevenLabs: klucz z zakresem tylko STT → 403).
    /// To ostrzeżenie, nie błąd: bez Retry, tekst do pokazania.
    case limited(String)

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
            case .replyCutOff: return "The reply was cut off before the end."
            case .inputTruncated: return "The server cut off the start of the input: the Context window setting is higher than what it really uses."
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
        do { return .verified(models: try await listModels().count) } catch {
            // Lokalny serwer: nazwa i podpowiedź zamiast ogólnego „Can't connect".
            return .failed(LocalServerHint.message(for: provider, error: error) ?? ProviderCheck.describe(error))
        }
    }
}

/// Czytelny komunikat dla błędów lokalnego serwera tekstowego (Ollama, llama.cpp, oMLX, własny na loopbacku). `nil` = nie nasz
/// przypadek (dostawca nielokalny — także LAN — albo inny błąd): wołający zostaje przy dotychczasowym tekście.
/// Przekroczenie czasu to NIE „serwer nie działa" (serwer zwykle liczy — za wolno albo za duży model).
public enum LocalServerHint {
    /// `timeout` = limit w sekundach, jeśli wołający go zna (trafia do komunikatu o przekroczeniu czasu).
    public static func message(for provider: Provider, error: Error, timeout: Double? = nil) -> String? {
        guard provider.isLocal, provider.api == .openAICompatible else { return nil }
        let name = provider.name
        if let e = error as? URLError {
            switch e.code {
            case .cannotConnectToHost, .cannotFindHost:
                return "Can't reach \(name) at \(ProviderPreset.displayAddress(provider.baseURL)). \(start(provider)) and try again."
            case .timedOut:
                let after = timeout.map { " within \(Int($0.rounded())) s" } ?? " in time"
                return "\(name) didn't answer\(after). Try a smaller model, a longer limit or a lower Context window."
            case .networkConnectionLost:
                return "\(name) dropped the connection."
            default: return nil
            }
        }
        if case ProviderError.http(let status, _)? = error as? ProviderError {
            switch status {
            case 401: return "\(name) asks for an API key. Add the key you set in \(name) with Edit key…"
            case 507: return "\(name) can't load the model: not enough free memory. Close other apps or choose a smaller model."
            default: return nil
            }
        }
        return nil
    }

    private static func start(_ provider: Provider) -> String {
        switch ProviderPreset.matching(provider) {
        case ProviderPreset.ollama?: "Start it (ollama serve)"
        case ProviderPreset.llamaCpp?: "Start it (llama-server -m <model>)"
        case ProviderPreset.omlx?: "Start it (open the oMLX app and press Start)"
        default: "Start it"
        }
    }
}
