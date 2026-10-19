import Foundation
import MeetNotesProviders

/// Który model podsumowania obsłuży to nagranie i skąd (decyzja użytkownika 2026-10-14).
public struct SummaryChoice: Equatable, Sendable {
    public var assignment: RoleAssignment
    public var presetName: String
    public var isFallback: Bool

    /// „Using <model> from preset <nazwa>" tylko dla zastępstwa; model z presetu nagrania nie wymaga wyjaśnień.
    public var label: String? { isFallback ? "Using \(assignment.model) from preset \(presetName)" : nil }
}

public enum SummaryModel {
    /// Kolejność: (1) rola `summary` zamrożonego presetu nagrania, (2) preset domyślny, (3) dowolny inny preset z `summary`.
    /// `nil` tylko wtedy, gdy żaden preset nie ma modelu podsumowania.
    public static func resolve(frozen: Preset?, defaultPresetID: UUID?, presets: [Preset]) -> SummaryChoice? {
        func usable(_ p: Preset) -> RoleAssignment? {
            p.summary.flatMap { $0.model.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        if let f = frozen, let a = usable(f) { return SummaryChoice(assignment: a, presetName: f.name, isFallback: false) }
        let candidates = presets.filter { $0.id == defaultPresetID } + presets.filter { $0.id != defaultPresetID }
        for p in candidates {
            if let a = usable(p) { return SummaryChoice(assignment: a, presetName: p.name, isFallback: true) }
        }
        return nil
    }
}
