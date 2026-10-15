import Foundation

/// Gotowe kafelki „Add Provider" (odbiór T13, uwaga 7): użytkownik wkleja tylko klucz, adres jest wpisany.
/// Modele zostają w presetach; dostawcy — w Settings.
public struct ProviderPreset: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var needsKey: Bool
    public var note: String?

    public static let openRouter = ProviderPreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
                                                  needsKey: true, note: nil)
    /// Ollama nie robi ASR (docs/wymagania.md §2): tylko korekta i podsumowanie.
    public static let ollama = ProviderPreset(id: "ollama", name: "Ollama", baseURL: "http://localhost:11434/v1", needsKey: false,
                                              note: "Corrections and summaries only — Ollama can't transcribe audio.")
    public static let custom = ProviderPreset(id: "custom", name: "Custom", baseURL: "", needsKey: true,
                                              note: "Any OpenAI-compatible server.")
    public static let all: [ProviderPreset] = [openRouter, ollama, custom]
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
