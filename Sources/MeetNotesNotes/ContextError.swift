import Foundation
import MeetNotesProviders

/// Zbyt długi transkrypt dla modelu → czytelny komunikat z nazwą modelu (spec 1.5, decyzja 20).
/// Dzielenie na części (map-reduce) wchodzi w fazie 2.
public enum ContextError {
    public static func isContextOverflow(_ error: Error) -> Bool {
        guard case ProviderError.http(let status, let body)? = error as? ProviderError, [400, 413, 422].contains(status) else { return false }
        let b = body.lowercased()
        return ["context", "too long", "maximum", "too many tokens", "token limit"].contains { b.contains($0) }
    }

    /// Serwer uciął wyjście (`finish_reason: "length"`): brak miejsca na odpowiedź w kontekście albo w limicie tokenów.
    public static func isCutOff(_ error: Error) -> Bool { (error as? ProviderError) == .replyCutOff }

    /// Lokalny serwer: nazwa, adres i podpowiedź (`LocalServerHint`); także miękki limit (`DeadlineExceeded`) to „nie odpowiedział w czasie",
    /// nie „serwer nie działa". `nil` dla dostawców nielokalnych i innych błędów. `transport` = limit żądania w sekundach, jeśli znany.
    public static func localHint(provider: Provider, _ error: Error, transport: Double? = nil) -> String? {
        if let d = error as? DeadlineExceeded { return LocalServerHint.message(for: provider, error: URLError(.timedOut), timeout: d.seconds) }
        return LocalServerHint.message(for: provider, error: error, timeout: transport)
    }

    /// Z `provider` błędy lokalnego serwera dostają `LocalServerHint` zamiast surowego `URLError` (spec fazy 2.0 §5.2).
    public static func describe(model: String, _ error: Error, provider: Provider? = nil, transport: Double? = nil) -> String {
        if let provider, let hint = localHint(provider: provider, error, transport: transport) { return hint }
        if isCutOff(error) {
            return "\(model)'s reply was cut off before the end: it ran out of context or token room. "
                + "Use a model with a longer context or raise the server's context length."
        }
        if isContextOverflow(error) {
            return "\(model) can't take a transcript this long. Try a model with a longer context. (Splitting long transcripts arrives later.)"
        }
        return "\(model) failed: \(error)"
    }
}
