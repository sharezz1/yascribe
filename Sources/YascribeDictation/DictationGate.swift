/// Powód odmowy startu dyktowania.
public enum DictationRefusal: Error, Equatable, Sendable {
    case recordingMeeting, busy

    public var message: String {
        switch self {
        case .recordingMeeting: "Recording a meeting."
        case .busy: "Dictation in progress."
        }
    }
}

/// Dyktowanie i nagrywanie spotkania wykluczają się (oba trzymają mikrofon).
public enum DictationGate {
    public static func canStartDictation(isRecordingMeeting: Bool, isBusy: Bool) -> Result<Void, DictationRefusal> {
        if isRecordingMeeting { return .failure(.recordingMeeting) }
        if isBusy { return .failure(.busy) }
        return .success(())
    }

    public static func canStartMeeting(dictationBusy: Bool) -> Bool { !dictationBusy }
}
