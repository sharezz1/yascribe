import Foundation

/// Progi i listy wykrywania spotkań; wartości z raportu spike'a T0 (`docs/superpowers/spikes/2026-10-16-faza16-wykrywanie.md` §5).
public struct MeetingTuning: Equatable, Sendable {
    /// Oferta z kalendarza od `start - offerLead` s do `start + offerGrace` s.
    public var offerLead: Double = 60
    public var offerGrace: Double = 600
    public var maxEventHours: Double = 8
    /// Ciągłe użycie mikrofonu przez aplikację rozmów, zanim padnie oferta.
    public var startSeconds: Double = 12
    /// Zwolnienie mikrofonu trwające tyle, zanim uznamy rozmowę za zakończoną.
    public var releaseSeconds: Double = 20
    public var silenceSeconds: Double = 180
    public var snoozeSeconds: Double = 600
    /// Aplikacje rozmów. Dopasowanie po PREFIKSIE bundle ID (Teams trzyma mikrofon w procesach pomocniczych,
    /// np. `com.microsoft.teams2.modulehost`).
    public var callApps: [String] = ["com.microsoft.teams2"]
    public var ignoredApps: [String] = ["com.apple.CoreSpeech", "com.electron.wispr-flow"]
    public var linkPatterns: [String] = ["teams.microsoft.com", "teams.live.com", "meet.google.com", "zoom.us/j"]

    public init() {}
}

extension MeetingTuning {
    /// Rodzina aplikacji rozmów: wpis z `callApps` dopasowany po prefiksie na granicy członu
    /// (`com.microsoft.teams2.modulehost` tak, `com.microsoft.teams2extra` nie). Wspólne dla `OfferDetector` i `EndDetector`.
    func family(of bundleID: String) -> String? {
        callApps.first { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    /// Zwraca kopię, w której nadpisane są TYLKO wartości niebędące `nil`.
    public func applying(startSeconds: Double?, releaseSeconds: Double?, silenceSeconds: Double?, ignoredApps: [String]?) -> MeetingTuning {
        var copy = self
        if let s = startSeconds { copy.startSeconds = s }
        if let r = releaseSeconds { copy.releaseSeconds = r }
        if let sl = silenceSeconds { copy.silenceSeconds = sl }
        if let ia = ignoredApps { copy.ignoredApps = ia }
        return copy
    }
}
