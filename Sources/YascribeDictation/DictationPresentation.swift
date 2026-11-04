import YascribeProviders

/// Teksty wiersza i stanu pustego w sekcji Dictation (czysta logika widoku).
public enum DictationPresentation {
    public static let correctionFailedNote = "Correction failed — original text used"
    public static let copiedOnlyNote = "Copied only"
    public static let fnHint = "If pressing 🌐/Fn opens the emoji picker or system dictation, set System Settings → Keyboard → “Press 🌐 key to” to “Do Nothing”."

    /// Uwagi pod tekstem wpisu: nieudana korekta, tekst tylko w schowku.
    public static func notes(for e: DictationEntry) -> [String] {
        var out: [String] = []
        if e.correctionFailed == true { out.append(correctionFailedNote) }
        if e.inserted == false { out.append(copiedOnlyNote) }
        return out
    }

    /// „Copy original” ma sens tylko, gdy surowy tekst jest inny niż wstawiony.
    public static func hasDistinctOriginal(_ e: DictationEntry) -> Bool { !e.raw.isEmpty && e.raw != e.text }

    /// Aplikacja i modele w jednej linii, np. „Notes · model-a → model-b”; `name` skraca identyfikator modelu.
    public static func metaLine(_ e: DictationEntry, name: (String) -> String) -> String {
        let models = [e.asrModel, e.correctionModel].compactMap { $0 }.map(name).joined(separator: " → ")
        return [e.app ?? "", models].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Stan pusty: „Hold Fn and speak…” / „Press Fn and speak…” (tryb przełączania).
    public static func emptyHint(hotkey: DictationHotkey, mode: DictationTriggerMode) -> String {
        "\(mode == .hold ? "Hold" : "Press") \(HotkeyCapture.label(hotkey)) and speak. Your dictations will show up here."
    }
}
