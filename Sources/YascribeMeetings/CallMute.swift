import Foundation

/// Stan mikrofonu w aplikacji rozmów, odczytany z opisu jej przycisku mute (Teams: Accessibility).
public enum CallMuteState: Equatable, Sendable {
    case muted, unmuted

    /// Teams opisuje przycisk akcją, nie stanem: "Wycisz mikrofon" = jesteś włączony, "Wyłącz wyciszenie mikrofonu" = jesteś wyciszony
    /// (pomiar 2026-10-27, okno kompaktowe i pełne, Teams po polsku). Angielskie opisy są z domysłu, niezmierzone.
    /// Prefiks, nie równość (opis może dostać skrót klawiszowy), ale nie samo "wycisz": "Wycisz wszystkich" to inny przycisk.
    public init?(buttonLabel: String) {
        let s = buttonLabel.trimmingCharacters(in: .whitespaces).lowercased()
        if ["wyłącz wyciszenie mikrofonu", "unmute mic"].contains(where: s.hasPrefix) || s == "unmute" { self = .muted }
        else if ["wycisz mikrofon", "mute mic"].contains(where: s.hasPrefix) || s == "mute" { self = .unmuted }
        else { return nil }
    }
}

/// Przenosi wyciszenie z aplikacji rozmów na tor mikrofonu. Działa na zmianach, nie na stanie: wyciszenie z pigułki,
/// gdy Teams jest włączony, zostaje do następnej zmiany w Teams. Start w stanie włączonym niczego nie rusza.
public struct CallMuteSync {
    private var applied: CallMuteState?

    public init() {}

    /// `apply(micMuted)` zwraca `false`, gdy rdzeń odmówił (np. jedyny żywy tor): wtedy próbujemy znowu przy następnym odczycie.
    public mutating func step(read: CallMuteState?, apply: (Bool) -> Bool) {
        guard let read, read != applied else { return }
        if applied == nil && read == .unmuted { applied = read; return }
        if apply(read == .muted) { applied = read }
    }
}
