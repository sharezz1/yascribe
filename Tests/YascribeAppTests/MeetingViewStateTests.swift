import Testing
@testable import YascribeApp

@Suite("MeetingViewState") @MainActor struct MeetingViewStateTests {
    @Test func summarySourceFollowsTranscriptVersionUntilSet() {
        let state = MeetingViewState()
        #expect(state.summaryCorrected)
        state.useCorrected = false
        #expect(!state.summaryCorrected)
    }

    @Test func summarySourceOverrideIgnoresTranscriptToggle() {
        let state = MeetingViewState()
        state.summaryUseCorrected = false
        state.useCorrected = true
        #expect(!state.summaryCorrected)
    }
}
