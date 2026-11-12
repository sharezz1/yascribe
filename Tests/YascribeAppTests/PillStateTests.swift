import Testing
import YascribeMeetings
@testable import YascribeApp

@Test func pillResetCollapsesAndReturnsToRecordingMode() {
    let pill = PillState()
    pill.expanded = true
    pill.mode = .endPrompt(.silence)
    pill.reset()
    #expect(!pill.expanded)
    #expect(pill.mode == .recording)
}
