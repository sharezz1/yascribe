import Foundation
import YascribeProviders

/// Ponawianie żądania ASR po chwilowym błędzie dostawcy (TASK-87: MAI-2 przez OpenRouter oddał 429 na 2 z 60 okien).
public enum ASRRetry {
    /// Rosnące opóźnienia przed kolejnymi próbami (razem 26 s); po ostatniej próbie błąd idzie dalej jako luka.
    /// shortcut: bez `Retry-After` (klient gubi nagłówki), dodać razem z nagłówkami w `ProviderError`.
    public static let delays: [Duration] = [.seconds(2), .seconds(6), .seconds(18)]

    /// Ponawia tylko HTTP 429 i 5xx. Anulowanie (także w trakcie czekania) przechodzi bez kolejnej wysyłki.
    public static func run<T>(delays: [Duration] = ASRRetry.delays,
                              sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                              _ op: () async throws -> T) async throws -> T {
        for delay in delays {
            do { return try await op() }
            catch ProviderError.http(let status, _) where status == 429 || status >= 500 { try await sleep(delay) }
        }
        return try await op()
    }
}
