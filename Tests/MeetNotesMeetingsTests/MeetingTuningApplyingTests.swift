import Foundation
import Testing
@testable import MeetNotesMeetings

@Test func applyingOverridesOnlyGivenValues() {
    let base = MeetingTuning()
    let original = base.startSeconds
    let applied = base.applying(startSeconds: 30, releaseSeconds: nil, silenceSeconds: nil, ignoredApps: nil)
    #expect(applied.startSeconds == 30)
    #expect(applied.releaseSeconds == base.releaseSeconds)
    #expect(applied.silenceSeconds == base.silenceSeconds)
    #expect(applied.ignoredApps == base.ignoredApps)
}

@Test func applyingNilKeepsDefaults() {
    let base = MeetingTuning()
    let applied = base.applying(startSeconds: nil, releaseSeconds: nil, silenceSeconds: nil, ignoredApps: nil)
    #expect(applied == base)
}
