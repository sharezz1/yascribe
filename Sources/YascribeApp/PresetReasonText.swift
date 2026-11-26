import Foundation
import YascribeMeetings
import YascribeProviders

enum PresetReasonText {
    /// „Reguła: …" — powód wyboru presetu (TASK-115).
    static func reason(_ r: PresetMatch.Reason) -> String {
        switch r {
        case .title(let x): String(localized: "Rule: title contains “\(x)”")
        case .domain(let x): String(localized: "Rule: attendee domain \(x)")
        case .app(let x): String(localized: "Rule: call app \(OfferDetector.appName(x))")
        }
    }

    /// Powód; dla presetu z językiem Auto ostrzeżenie idzie przed nim.
    static func line(_ match: PresetMatch, preset: Preset?) -> String {
        let base = reason(match.reason)
        guard preset?.isAutoLanguage == true else { return base }
        // Ostrzeżenie na początku: przy obcięciu tekstu to powód, nie ostrzeżenie, ma zniknąć.
        return String(localized: "⚠ Auto language, check it before you start") + " · " + base
    }
}
