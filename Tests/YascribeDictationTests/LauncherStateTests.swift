import Testing
@testable import YascribeDictation

@Suite struct LauncherStateTests {
    @Test func dotByDefault() {
        #expect(LauncherState().presentation(phase: .idle, meetingRecording: false, now: 0) == .dot)
    }

    @Test func hoverExpandsAndCollapsesAfterDelay() {
        var s = LauncherState()
        s.hoverChanged(true, at: 0.5)
        #expect(s.presentation(phase: .idle, meetingRecording: false, now: 0.6) == .expanded)
        s.hoverChanged(false, at: 1.0)
        #expect(s.presentation(phase: .idle, meetingRecording: false, now: 1.2) == .expanded)
        #expect(s.presentation(phase: .idle, meetingRecording: false, now: 1.5) == .dot)
    }

    @Test func statusWinsOverHoverWhileListening() {
        var s = LauncherState()
        s.hoverChanged(true, at: 0)
        #expect(s.presentation(phase: .listening, meetingRecording: false, now: 0.1) == .status(.listening))
        #expect(s.presentation(phase: .processing, meetingRecording: false, now: 0.1) == .status(.processing))
        #expect(s.presentation(phase: .finished(.inserted), meetingRecording: false, now: 0.1) == .status(.inserted))
    }

    @Test func hiddenWhileMeetingRecording() {
        var s = LauncherState()
        s.hoverChanged(true, at: 0)
        #expect(s.presentation(phase: .idle, meetingRecording: true, now: 0.1) == nil)
        #expect(LauncherState().presentation(phase: .idle, meetingRecording: true, now: 0) == nil)
    }

    @Test func copiedMapsToCopiedStatus() {
        #expect(LauncherState().presentation(phase: .finished(.copiedOnly(reason: "x")), meetingRecording: false, now: 0)
                == .status(.copied))
    }

    @Test func blockedMapsToPasswordMessage() {
        let reason = "A password field is focused."
        #expect(LauncherState().presentation(phase: .finished(.blocked(reason: reason)), meetingRecording: false, now: 0)
                == .status(.error(reason)))
    }

    @Test func originXIsClampedToMainScreen() {
        #expect(LauncherState.originX(500, minX: 0, maxX: 1440) == 500)
        #expect(LauncherState.originX(2000, minX: 0, maxX: 1440) == 1440)
        #expect(LauncherState.originX(-300, minX: 0, maxX: 1440) == 0)
    }

    @Test func refusedMapsToErrorWithMessage() {
        let s = LauncherState()
        #expect(s.presentation(phase: .refused("Choose a dictation language in Settings."), meetingRecording: false, now: 0)
                == .status(.error("Choose a dictation language in Settings.")))
        #expect(s.presentation(phase: .failed("Network down"), meetingRecording: false, now: 0) == .status(.error("Network down")))
    }
}
