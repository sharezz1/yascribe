import Testing
@testable import YascribeDictation

@Suite struct HotkeyStartDecisionTests {
    @Test func listeningIsIgnored() {
        #expect(HotkeyStartDecision.decide(phase: .listening, isRecordingMeeting: false, languageAvailable: true) == .ignore)
        #expect(HotkeyStartDecision.decide(phase: .listening, isRecordingMeeting: false, languageAvailable: false) == .ignore)
    }

    @Test func processingIsIgnored() {
        #expect(HotkeyStartDecision.decide(phase: .processing, isRecordingMeeting: false, languageAvailable: true) == .ignore)
    }

    @Test func meetingRecordingBeeps() {
        #expect(HotkeyStartDecision.decide(phase: .idle, isRecordingMeeting: true, languageAvailable: true) == .beep)
    }

    @Test func missingLanguageIsRefused() {
        #expect(HotkeyStartDecision.decide(phase: .idle, isRecordingMeeting: false, languageAvailable: false)
                == .refuse("Choose a dictation language in Settings."))
    }

    @Test func idleOrResultStarts() {
        for phase: DictationPhase in [.idle, .finished(.inserted), .failed("x"), .refused("y")] {
            #expect(HotkeyStartDecision.decide(phase: phase, isRecordingMeeting: false, languageAvailable: true) == .start)
        }
    }
}
