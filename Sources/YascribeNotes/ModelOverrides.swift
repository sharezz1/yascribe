import Foundation
import YascribeProviders

/// Model wybrany dla jednego nagrania zamiast modelu z presetu (faza 2.0.1). Zapisywany w `notes/meta.json`.
public struct RoleOverride: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var model: String
    /// Tylko podsumowanie; `nil` = ustawienie globalne.
    public var thinking: Bool?

    public init(providerID: UUID, model: String, thinking: Bool? = nil) {
        self.providerID = providerID
        self.model = model
        self.thinking = thinking
    }
}

public struct ModelOverrides: Codable, Equatable, Sendable {
    public var summary: RoleOverride?
    public var correction: RoleOverride?

    public init(summary: RoleOverride? = nil, correction: RoleOverride? = nil) {
        self.summary = summary
        self.correction = correction
    }

    public var isEmpty: Bool { summary == nil && correction == nil }

    /// Nadpisanie do użycia. `nil`, gdy brak, rola nie jest `.summary`/`.correction`, model jest pusty albo dostawca już nie istnieje.
    public func usable(_ role: Role, knownProviders: Set<UUID>) -> RoleOverride? {
        guard let o = raw(role), !o.model.trimmingCharacters(in: .whitespaces).isEmpty,
              knownProviders.contains(o.providerID) else { return nil }
        return o
    }

    /// Jest zapisane, ale nie działa (np. dostawca usunięty): wracamy do presetu i pokazujemy użytkownikowi, że wybór wygasł.
    public func isStale(_ role: Role, knownProviders: Set<UUID>) -> Bool {
        raw(role) != nil && usable(role, knownProviders: knownProviders) == nil
    }

    /// Zapisana wartość bez sprawdzania; do pokazania w chipie.
    public func raw(_ role: Role) -> RoleOverride? {
        switch role {
        case .summary: summary
        case .correction: correction
        default: nil
        }
    }

    public mutating func set(_ role: Role, _ value: RoleOverride?) {
        switch role {
        case .summary: summary = value
        case .correction: correction = value
        default: break
        }
    }
}

extension NoteMeta {
    /// Pusty wynik czyści pole, żeby `meta.json` wracał do postaci sprzed nadpisań.
    public mutating func setOverride(_ role: Role, _ value: RoleOverride?) {
        var o = modelOverrides ?? ModelOverrides()
        o.set(role, value)
        modelOverrides = o.isEmpty ? nil : o
    }
}

public enum CorrectionModel {
    /// Ważne nadpisanie (już po `usable`) wygrywa, ale prompt zostaje z presetu. Inaczej rola korekty presetu z niepustym modelem.
    public static func resolve(frozen: Preset?, override: RoleOverride?) -> RoleAssignment? {
        if let o = override {
            return RoleAssignment(providerID: o.providerID, model: o.model, prompt: frozen?.correction?.prompt)
        }
        guard let c = frozen?.correction, !c.model.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return c
    }
}
