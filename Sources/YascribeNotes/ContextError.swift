import Foundation
import YascribeProviders

/// Zbyt długi transkrypt dla modelu → czytelny komunikat z nazwą modelu (spec 1.5, decyzja 20).
/// Dzielenie na części (map-reduce) wchodzi w fazie 2.
public enum ContextError {
    public static func isContextOverflow(_ error: Error) -> Bool {
        guard case ProviderError.http(let status, let body)? = error as? ProviderError, [400, 413, 422].contains(status) else { return false }
        if status == 413 { return true }
        let b = body.lowercased()
        if b.contains("<html") || b.contains("<!doctype") { return false }
        let phrases = ["context", "too long", "too many tokens", "token limit", "maximum context"]
        return phrases.contains { b.contains($0) }
    }

    /// Zwięzły fragment ciała odpowiedzi dla komunikatu (spec §4.1): jedna linia, do ~160 znaków, bez znaczników HTML.
    private static func bodySnippet(_ body: String) -> String? {
        let oneLine = body
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let withoutTags = oneLine.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = withoutTags.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let snippet = String(collapsed.prefix(160))
        return snippet.isEmpty ? nil : snippet
    }

    /// Serwer uciął wyjście (`finish_reason: "length"`): brak miejsca na odpowiedź w kontekście albo w limicie tokenów.
    public static func isCutOff(_ error: Error) -> Bool { (error as? ProviderError) == .replyCutOff }

    /// Lokalny serwer obciął wejście bez błędu (`usage.prompt_tokens` za małe wobec promptu) — `OpenAICompatibleClient.chat`.
    public static func isInputTruncated(_ error: Error) -> Bool {
        if case ProviderError.inputTruncated? = error as? ProviderError { return true }
        return false
    }

    /// Odpowiedź pusta po oczyszczeniu z rozumowania (`OpenAICompatibleClient.chat`).
    public static func isEmptyReply(_ error: Error) -> Bool { (error as? ProviderError) == .badResponse("empty reply") }

    /// Lokalny serwer: nazwa, adres i podpowiedź (`LocalServerHint`); także miękki limit (`DeadlineExceeded`) to „nie odpowiedział w czasie",
    /// nie „serwer nie działa". `nil` dla dostawców nielokalnych i innych błędów. `transport` = limit żądania w sekundach, jeśli znany.
    public static func localHint(provider: Provider, _ error: Error, transport: Double? = nil) -> String? {
        if let d = error as? DeadlineExceeded { return LocalServerHint.message(for: provider, error: URLError(.timedOut), timeout: d.seconds) }
        return LocalServerHint.message(for: provider, error: error, timeout: transport)
    }

    /// Z `provider` błędy lokalnego serwera dostają `LocalServerHint` zamiast surowego `URLError` (spec fazy 2.0 §5.2).
    /// Rada przy ucięciu zależy od miejsca: lokalny serwer ma pokrętło kontekstu, API ma limit wyjścia. Lokalność wynika
    /// z `provider` albo z `isLocal` (plan T13: parametr `isLocal: Bool = false`). `maxTokens` = limit wyjścia, który SAMI wysłaliśmy:
    /// ucięcie przy nim to „odpowiedź trafiła w limit wyjścia", nie rada o oknie kontekstu (przegląd T13).
    public static func describe(model: String, _ error: Error, provider: Provider? = nil, transport: Double? = nil,
                                isLocal: Bool = false, maxTokens: Int? = nil) -> String {
        if let provider, let hint = localHint(provider: provider, error, transport: transport) { return hint }
        let local = isLocal || provider?.isLocal == true
        if isCutOff(error) {
            if let maxTokens {
                return "\(model)'s reply hit the output limit (\(maxTokens) tokens) before the end. Try a shorter template or another model."
            }
            return local
                ? "\(model)'s reply was cut off before the end: it ran out of context or token room. Raise the Context window "
                    + "for this provider in Settings and the server's context length, or use a model with a longer context."
                : "\(model)'s reply was cut off before the end. Try a model with a longer output limit."
        }
        if isInputTruncated(error) {
            return "\(model)'s server cut off the start of the input — the Context window setting is higher than what the server really uses. "
                + "Lower the field or raise the server's context (e.g. OLLAMA_CONTEXT_LENGTH=16384)."
        }
        if isEmptyReply(error) { return "\(model) returned an empty reply." }
        if isContextOverflow(error) {
            // Lokalnie długie transkrypty są dzielone (map-reduce), więc przepełnienie znaczy: kontekst serwera < „Context window" w Settings.
            let body: String? = {
                guard case ProviderError.http(_, let text)? = error as? ProviderError else { return nil }
                return bodySnippet(text)
            }()
            let suffix = body.map { " (\($0))" } ?? ""
            return local
                ? "\(model) can't take this much text\(suffix): the server's context length is smaller than the Context window set in Settings. "
                    + "Lower the Context window to the server's value, raise the server's context length, or use a model with a longer context."
                : "\(model) can't take a transcript this long\(suffix). Try a model with a longer context. (Splitting long transcripts arrives later.)"
        }
        return "\(model) failed: \(error)"
    }
}
