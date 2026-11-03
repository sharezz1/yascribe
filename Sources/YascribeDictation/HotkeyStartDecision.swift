/// Co zrobić z prośbą o start dyktowania (skrót albo pastylka).
public enum HotkeyStartDecision: Equatable, Sendable {
    /// `ignore`: sesja trwa. W trybie hold `.start` przychodzi też po starcie z pastylki; odmowa porzuciłaby to nagranie.
    case start, ignore, beep, refuse(String)

    public static let missingLanguageMessage = "Choose a dictation language in Settings."

    public static func decide(phase: DictationPhase, isRecordingMeeting: Bool, languageAvailable: Bool) -> HotkeyStartDecision {
        switch DictationGate.canStartDictation(isRecordingMeeting: isRecordingMeeting,
                                               isBusy: phase == .listening || phase == .processing) {
        case .failure(.recordingMeeting): .beep   // pastylka jest ukryta w trakcie nagrania spotkania
        case .failure(.busy): .ignore
        case .success: languageAvailable ? .start : .refuse(missingLanguageMessage)
        }
    }
}
