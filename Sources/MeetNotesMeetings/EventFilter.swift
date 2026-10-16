import Foundation

/// Filtr wydarzeń kalendarza (spec §4.3). Czysta logika, bez EventKit.
public enum EventFilter {
    /// Link do spotkania online: szukany w `notes`, potem `url`, `location` (pomiar T0: Exchange trzyma go w treści).
    /// Wzorzec porównywany bez względu na wielkość liter. Zwraca pełny adres wycięty z tekstu; gdy w tekście jest sam
    /// fragment bez schematu (`zoom.us/j/55`), dopisuje `https://`.
    /// ponytail: pierwszy token zawierający wzorzec wygrywa, bez sprawdzania hosta; wzmocnić, gdy pojawi się fałszywy trafiony.
    public static func meetingURL(in event: CalendarEventInfo, patterns: [String]) -> URL? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"'()[]"))
        for text in [event.notes, event.url?.absoluteString, event.location] {
            for raw in (text ?? "").components(separatedBy: separators) {
                let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
                guard patterns.contains(where: { token.range(of: $0, options: .caseInsensitive) != nil }) else { continue }
                let hasScheme = token.lowercased().hasPrefix("http://") || token.lowercased().hasPrefix("https://")
                if let url = URL(string: hasScheme ? token : "https://" + token) { return url }
            }
        }
        return nil
    }

    /// Wydarzenie kwalifikuje się do oferty pigułki, gdy spełnia wszystkie warunki naraz.
    /// `availability` celowo poza filtrem: OOO z Exchange ma dostępność busy (T0); OOO odcinają brak linku,
    /// całodniowość i długość.
    public static func isOfferable(_ event: CalendarEventInfo, tuning: MeetingTuning) -> Bool {
        guard meetingURL(in: event, patterns: tuning.linkPatterns) != nil,
              !event.isAllDay, !event.isCanceled,
              event.end.timeIntervalSince(event.start) <= tuning.maxEventHours * 3600,
              Calendar.current.isDate(event.start, inSameDayAs: event.end - 1) else { return false }
        switch event.myStatus {
        case .accepted, .tentative, .none: return true  // .none = wydarzenie własne
        case .pending, .declined: return false
        }
    }

    /// Lista ręcznego wyboru: ukrywa całodniowe i OOO. OOO wykrywamy jak w `isOfferable` (całodniowe / długość),
    /// nie flagą dostępności. Link i status odpowiedzi nie grają roli (spotkanie stacjonarne jest wybieralne).
    public static func isPickable(_ event: CalendarEventInfo) -> Bool {
        !event.isAllDay && event.end.timeIntervalSince(event.start) < 24 * 3600
    }
}
