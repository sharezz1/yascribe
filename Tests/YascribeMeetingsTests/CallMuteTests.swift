import Testing
@testable import YascribeMeetings

@Suite struct CallMuteTests {
    @Test func polishLabelsMeasuredInTeams() {
        #expect(CallMuteState(buttonLabel: "Wycisz mikrofon") == .unmuted)
        #expect(CallMuteState(buttonLabel: "Wyłącz wyciszenie mikrofonu") == .muted)
    }

    @Test func otherButtonsAreNotMuteState() {
        #expect(CallMuteState(buttonLabel: "Wycisz wszystkich") == nil)
        #expect(CallMuteState(buttonLabel: "Otwórz opcje dźwięku") == nil)
        #expect(CallMuteState(buttonLabel: "") == nil)
    }

    private func run(_ reads: [CallMuteState?], refuse: Bool = false) -> [Bool] {
        var sync = CallMuteSync()
        var calls: [Bool] = []
        for r in reads { sync.step(read: r) { calls.append($0); return !refuse } }
        return calls
    }

    @Test func muteAndUnmuteFollowTeams() {
        #expect(run([.unmuted, .unmuted, .muted, .muted, nil, .unmuted]) == [true, false])
    }

    @Test func startingUnmutedLeavesTheMicAlone() {
        #expect(run([.unmuted, .unmuted]) == [])
    }

    @Test func startingMutedMutesTheMic() {
        #expect(run([.muted, .muted]) == [true])
    }

    @Test func refusedApplyIsRetriedOnNextRead() {
        #expect(run([.muted, .muted, .muted], refuse: true) == [true, true, true])
    }
}
