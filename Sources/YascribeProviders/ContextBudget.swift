import Foundation

/// Budżet okna kontekstu lokalnego modelu tekstowego (spec fazy 2.0 §14 pkt 4). Dwie reguły, obie na CAŁYM prompcie:
/// stała odpowiedź (notatka, reduce) → `promptChars`; odpowiedź proporcjonalna do wejścia (korekta, mapa) → `pairedInputChars`.
public struct ContextBudget: Equatable, Sendable {
    public var tokens: Int

    public init(tokens: Int) { self.tokens = tokens }

    /// S2: 2,65 znaku/token (Mistral), 2,9 (Qwen); 2,4 = ~10 % zapasu.
    public static let charsPerToken = 2.4
    /// Domyślny kontekst Ollamy; wyższy dawałby 400 u domyślnej instalacji.
    public static let defaultTokens = 4_096
    public static let marginTokens = 256
    public static let noteReplyTokens = ChatLimits.localNoteMaxTokens
    public static let correctionReplyFactor = 1.3
    public static let mapReplyFactor = 0.5
    /// Limity czasowe rozmiaru: przy dużym kontekście partia/część nie może trwać dłużej niż limit miękki.
    public static let correctionBatchCap = 4_000
    public static let mapPartCap = 8_000
    /// Zakres pola „Context window (tokens)" w Settings.
    public static let userRange = 2_048...1_048_576

    /// Limit znaków CAŁEGO promptu (`system.count + user.count`) przy stałej odpowiedzi (notatka, reduce).
    public func promptChars(replyTokens: Int) -> Int {
        Int(Double(tokens - Self.marginTokens - replyTokens) * Self.charsPerToken)
    }

    /// Limit znaków `user`, gdy odpowiedź jest proporcjonalna do wejścia (korekta, mapa); `fixedChars` = `system.count`.
    public func pairedInputChars(fixedChars: Int, replyFactor: Double) -> Int {
        Int((Double(tokens - Self.marginTokens) * Self.charsPerToken - Double(fixedChars)) / (1 + replyFactor))
    }

    public static func maxTokens(inputChars: Int, replyFactor: Double) -> Int {
        Int((Double(inputChars) / charsPerToken * replyFactor).rounded(.up))
    }

    /// `nil` dla dostawców bez budżetu (API, LAN, `.fluidAudio`). Wykrycie tylko OBNIŻA (spec §14 pkt 4).
    public static func resolve(provider: Provider, detected: Int?) -> ContextBudget? {
        guard provider.isLocal, provider.api == .openAICompatible else { return nil }
        let base = provider.contextTokens ?? defaultTokens
        return ContextBudget(tokens: min(base, detected ?? base))
    }
}
