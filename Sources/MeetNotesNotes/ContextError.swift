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

    public static func describe(model: String, _ error: Error) -> String {
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
