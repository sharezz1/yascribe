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

    /// TASK-95: tor mikrofonu może zacząć wcześniej niż oś sesji (system.caf) — start < 0 nie może dać „0:00:-21".
    @Test func timeNeverShowsMinus() {
        #expect(MeetingDetailView.time(-21.9) == "0:00:00")
        #expect(MeetingDetailView.time(-0.001) == "0:00:00")
        #expect(MeetingDetailView.time(0) == "0:00:00")
        #expect(MeetingDetailView.time(3725.9) == "1:02:05")
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
