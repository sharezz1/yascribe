import Testing
@testable import YascribeDictation

@Suite struct DictationGateTests {
    @Test func refusesWhileRecordingMeeting() {
        let r = DictationGate.canStartDictation(isRecordingMeeting: true, isBusy: false)
        guard case .failure(let refusal) = r else { Issue.record("expected refusal"); return }
        #expect(refusal == .recordingMeeting)
        #expect(refusal.message == "Recording a meeting.")
    }

    @Test func refusesWhileBusy() {
        let r = DictationGate.canStartDictation(isRecordingMeeting: false, isBusy: true)
        guard case .failure(let refusal) = r else { Issue.record("expected refusal"); return }
        #expect(refusal == .busy)
        #expect(refusal.message == "Dictation in progress.")
    }

    @Test func allowsWhenIdle() {
        #expect((try? DictationGate.canStartDictation(isRecordingMeeting: false, isBusy: false).get()) != nil)
    }

    @Test func meetingBlockedWhileDictating() {
        #expect(!DictationGate.canStartMeeting(dictationBusy: true))
    }

    @Test func meetingAllowedWhenNotDictating() {
        #expect(DictationGate.canStartMeeting(dictationBusy: false))
    }
}
