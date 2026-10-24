import Foundation

/// Czy sekcja roli w Settings startuje rozwinięta (faza 2.1 „okna").
public enum RoleAdvanced {
    /// Rozwinięta, gdy sonda zawodzi, nie rozstrzyga obsługi języka albo preset ma własny prompt.
    public static func startsExpanded(probe: ProbeResult?, prompt: String?) -> Bool {
        if let probe, !probe.works || probe.languageHandling == .unknown || probe.languageHandling == .automatic {
            return true
        }
        return !(prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
