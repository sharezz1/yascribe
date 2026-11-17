import Testing
@testable import YascribeApp

@Test func speakerDetectionRunsOnlyWithModelSettingTrackAndThem() async {
    func run(_ ready: Bool, _ setting: Bool?, _ track: Bool, _ them: Int) async -> Bool {
        await SpeakerDetectionDecision.shouldRun(modelReady: ready, setting: setting, themUtterances: them, hasSystemTrack: { track })
    }
    #expect(await run(true, nil, true, 3))
    #expect(await run(true, true, true, 1))
    #expect(await !run(false, true, true, 3))
    #expect(await !run(true, false, true, 3))
    #expect(await !run(true, nil, false, 3))
    #expect(await !run(true, nil, true, 0))
}

/// F04: dziennik (tor `system`) czytany dopiero po tanich warunkach.
@Test func speakerDetectionReadsJournalOnlyAfterCheapChecks() async {
    var reads = 0
    for (ready, setting, them) in [(false, true, 3), (true, false, 3), (true, nil, 0)] as [(Bool, Bool?, Int)] {
        _ = await SpeakerDetectionDecision.shouldRun(modelReady: ready, setting: setting, themUtterances: them,
                                                     hasSystemTrack: { reads += 1; return true })
    }
    #expect(reads == 0)
}

@Test func staleSpeakerTicketNeverWrites() {
    let old = SpeakerDetectionTicket(session: "s", runID: "r", generation: 1)
    let new = SpeakerDetectionTicket(session: "s", runID: "r", generation: 2)
    #expect(SpeakerDetectionTicket.mayWrite(new, current: new, cancelled: false))
    #expect(!SpeakerDetectionTicket.mayWrite(old, current: new, cancelled: false))
    #expect(!SpeakerDetectionTicket.mayWrite(new, current: new, cancelled: true))
    #expect(!SpeakerDetectionTicket.mayWrite(new, current: nil, cancelled: false))
    #expect(!SpeakerDetectionTicket.mayWrite(SpeakerDetectionTicket(session: "s", runID: "other", generation: 2), current: new, cancelled: false))
}

/// Praca, która po anulowaniu jeszcze kończy się wynikiem `true`; bez anulowania po ~5 s daje `false`.
private func cancellableWork() -> Task<Bool, any Error> {
    Task {
        for _ in 0..<500 {
            if Task.isCancelled { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

/// F02: anulowanie wywołującego anuluje pracę, a wywołujący wraca dopiero z jej wynikiem (faktyczny koniec).
@Test func cancellingCallerCancelsSpeakerWorkAndWaitsForIt() async throws {
    let work = cancellableWork()
    let caller = Task { await SpeakerDetectionWork.result(of: work) }
    try await Task.sleep(for: .milliseconds(30))
    caller.cancel()
    #expect(try await caller.value.get())
    #expect(work.isCancelled)
}

/// F02: wywołujący już anulowany przed wejściem — praca anulowana od razu.
@Test func alreadyCancelledCallerCancelsSpeakerWork() async throws {
    let work = cancellableWork()
    let caller = Task {
        while !Task.isCancelled { await Task.yield() }
        return await SpeakerDetectionWork.result(of: work)
    }
    caller.cancel()
    #expect(try await caller.value.get())
    #expect(work.isCancelled)
}
