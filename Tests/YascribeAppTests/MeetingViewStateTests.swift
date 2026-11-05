import Foundation
import Testing
@testable import YascribeApp

@Suite("MeetingViewState") @MainActor struct MeetingViewStateTests {
    @Test func summaryIsFirstAndManualSelectionPersists() {
        #expect(MeetingTab.allCases == [.summary, .myNotes, .transcript])
        let item = SessionItem(url: URL(fileURLWithPath: "/tmp/meeting"), startedAt: Date())
        #expect(MeetingDetailView.defaultTab(for: item) == .summary)
        let state = MeetingViewState()
        state.tab = .myNotes
        #expect(state.tab == .myNotes)
    }

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
