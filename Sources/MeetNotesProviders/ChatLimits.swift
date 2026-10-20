import Foundation

/// Rodzaj wywołania czatu — `Role` nie odróżnia tytułu ani części mapy (reduce = `.note`).
public enum ChatCall: Sendable { case note, correctionBatch, title, mapPart }

/// Limity jednego wywołania czatu. `soft` = całkowity limit czasu (`withDeadline`), `transport` = `timeoutInterval`
/// żądania (bez streamu serwer milczy do końca generacji, więc lokalnie transport ≥ soft + 30 s). `maxTokens`/`temperature`
/// tylko lokalnie; `nil` = nie wysyłaj (partia korekty i część mapy liczą `maxTokens` z budżetu — T12/T13).
public struct ChatLimits: Equatable, Sendable {
    public var soft: Double
    public var transport: Double
    public var maxTokens: Int?
    public var temperature: Double?

    public init(soft: Double, transport: Double, maxTokens: Int? = nil, temperature: Double? = nil) {
        self.soft = soft
        self.transport = transport
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    public static let localNoteMaxTokens = 2048

    /// Wartości z S2 (spec fazy 2.0 §14 pkt 5). API: dzisiejsze, bez zmian (niespójność notatki 180 > 120 zostaje).
    public static func `for`(_ provider: Provider, call: ChatCall) -> ChatLimits {
        if provider.isLocal {
            switch call {
            case .note: return ChatLimits(soft: 600, transport: 660, maxTokens: localNoteMaxTokens)
            case .correctionBatch: return ChatLimits(soft: 300, transport: 330, temperature: 0.2)
            case .title: return ChatLimits(soft: 120, transport: 150, maxTokens: 64)
            case .mapPart: return ChatLimits(soft: 300, transport: 330, temperature: 0.2)
            }
        }
        switch call {
        case .note: return ChatLimits(soft: 180, transport: 120)
        case .correctionBatch, .mapPart: return ChatLimits(soft: 120, transport: 120)
        case .title: return ChatLimits(soft: 60, transport: 120)
        }
    }
}
