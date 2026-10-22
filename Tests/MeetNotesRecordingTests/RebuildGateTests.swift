import Testing
@testable import MeetNotesRecording

@Test func gateAllowsTheFirstRebuild() {
    var gate = RebuildGate()
    #expect(gate.decide(now: 100) == .now)
}

@Test func gateDefersASecondRebuildWithinTheMinimumInterval() {
    var gate = RebuildGate()
    #expect(gate.decide(now: 0) == .now)
    #expect(gate.decide(now: 0.5) == .deferred(until: 1.0))
    #expect(gate.decide(now: 1.2) == .now)
}

@Test func gateDefersToTheEndOfTheMinuteAfterTheCap() {
    var gate = RebuildGate()
    for t in stride(from: 0.0, through: 10.0, by: 2.0) { #expect(gate.decide(now: t) == .now) }
    #expect(gate.decide(now: 12.5) == .deferred(until: 60.0))
    #expect(gate.decide(now: 61) == .now)
}
