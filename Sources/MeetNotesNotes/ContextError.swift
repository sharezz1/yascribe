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

    /// Odpowiedź pusta po oczyszczeniu z rozumowania (`OpenAICompatibleClient.chat`).
    public static func isEmptyReply(_ error: Error) -> Bool { (error as? ProviderError) == .badResponse("empty reply") }

    /// `isLocal` (domyślnie `false`) wybiera radę przy ucięciu: lokalny serwer ma pokrętło kontekstu, API ma limit wyjścia.
    public static func describe(model: String, _ error: Error, isLocal: Bool = false) -> String {
        if isCutOff(error) {
            return isLocal
                ? "\(model)'s reply was cut off before the end: it ran out of context or token room. "
                    + "Use a model with a longer context or raise the server's context length."
                : "\(model)'s reply was cut off before the end. Try a model with a longer output limit."
        }
        if isEmptyReply(error) { return "\(model) returned an empty reply." }
        if isContextOverflow(error) {
            return "\(model) can't take a transcript this long. Try a model with a longer context. (Splitting long transcripts arrives later.)"
        }
        return "\(model) failed: \(error)"
    }
}
