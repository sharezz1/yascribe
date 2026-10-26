import Testing
@testable import YascribeUpdates

@MainActor
private final class FakeActivity: RecordingActivity {
    var isBusy = false
}

@MainActor
private final class Counter {
    var calls = 0
}

@MainActor @Test func postponesWhileBusy() {
    let a = FakeActivity(); a.isBusy = true
    let gate = RestartGate(activity: a), c = Counter()
    #expect(gate.shouldPostpone { c.calls += 1 })
    #expect(c.calls == 0)
    #expect(gate.phase == .restartPostponed)
}

@MainActor @Test func proceedsWhenIdle() {
    let a = FakeActivity()
    let gate = RestartGate(activity: a), c = Counter()
    #expect(!gate.shouldPostpone { c.calls += 1 })
    #expect(c.calls == 0)
    #expect(gate.phase == .idle)
}

@MainActor @Test func releasesBlockExactlyOnceWhenActivityEnds() {
    let a = FakeActivity(); a.isBusy = true
    let gate = RestartGate(activity: a), c = Counter()
    _ = gate.shouldPostpone { c.calls += 1 }
    gate.activityDidChange() // nadal zajęte: bez wywołania
    #expect(c.calls == 0)
    a.isBusy = false
    gate.activityDidChange()
    gate.activityDidChange()
    #expect(c.calls == 1)
}

@MainActor @Test func terminationIsRefusedWhileBusy() {
    let a = FakeActivity(); a.isBusy = true
    let gate = RestartGate(activity: a)
    #expect(!gate.shouldTerminate())
    a.isBusy = false
    #expect(gate.shouldTerminate())
}

@MainActor @Test func installingBlocksNewRecording() {
    let gate = RestartGate(activity: FakeActivity())
    #expect(gate.canStartRecording)
    gate.installationStarted()
    #expect(!gate.canStartRecording)
}

@MainActor @Test func installFailureReleasesRecordingBlock() {
    let a = FakeActivity(); a.isBusy = true
    let gate = RestartGate(activity: a), c = Counter()
    gate.installationStarted()
    _ = gate.shouldPostpone { c.calls += 1 }
    gate.installationEnded()
    #expect(gate.canStartRecording)
    a.isBusy = false
    gate.activityDidChange()
    #expect(c.calls == 0) // porzucony blok nie wraca
}

@MainActor @Test func recordingStartBlockedDuringPostponedRestart() {
    let a = FakeActivity(); a.isBusy = true
    let gate = RestartGate(activity: a)
    gate.installationStarted()
    _ = gate.shouldPostpone {}
    #expect(gate.phase == .restartPostponed)
    #expect(!gate.canStartRecording)
}
