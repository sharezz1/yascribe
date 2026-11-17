import Foundation
import Testing
import YascribeProviders
import YascribeTranscription
@testable import YascribeApp

@Test func speakerDetectionRunsOnlyWithCapableModelTrackAndThem() async {
    func run(_ capable: Bool, _ track: Bool, _ them: Int) async -> Bool {
        await SpeakerDetectionDecision.shouldRun(capable: capable, themUtterances: them, hasSystemTrack: { track })
    }
    #expect(await run(true, true, 1))
    #expect(await !run(false, true, 1))
    #expect(await !run(true, false, 1))
    #expect(await !run(true, true, 0))
}

@Test func speakerDetectionReadsJournalOnlyAfterCheapChecks() async {
    var reads = 0
    for (capable, them) in [(false, 3), (true, 0)] {
        _ = await SpeakerDetectionDecision.shouldRun(capable: capable, themUtterances: them,
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

@Test func oldSettingsWithSpeakerFieldsDecode() throws {
    let json = Data(#"{"speakerSource":"mistral","detectSpeakers":true,"speakerSensitivity":"high"}"#.utf8)
    let settings = try JSONDecoder().decode(GlobalSettings.self, from: json)
    let encoded = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
    #expect(!encoded.contains("speakerSource"))
    #expect(!encoded.contains("detectSpeakers"))
    #expect(!encoded.contains("speakerSensitivity"))
}

private actor SpeakerWorkGate {
    var starts = 0
    var continuation: CheckedContinuation<Void, Never>?
    func work() async throws -> SpeakerDiarization {
        starts += 1
        if starts == 1 { await withCheckedContinuation { continuation = $0 } }
        throw MistralDiarizationError.rejectedKey
    }
    func release() { continuation?.resume(); continuation = nil }
}

@Test @MainActor func speakerReplacementWaitsForPreviousWork() async throws {
    let gate = SpeakerWorkGate()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())")
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", root.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    defer { try? FileManager.default.removeItem(at: root) }
    model.speakerWorkOverride = { try await gate.work() }
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("speaker-\(UUID())")
    let a = Task { await model.detectSpeakers(sessionURL: session, runID: "a", sensitivity: .medium) }
    while await gate.starts == 0 { await Task.yield() }
    let b = Task { await model.detectSpeakers(sessionURL: session, runID: "b", sensitivity: .medium) }
    while model.speakerTickets[session.lastPathComponent]?.runID != "b", await gate.starts < 2 { await Task.yield() }
    #expect(await gate.starts == 1)
    #expect(model.speakerTickets[session.lastPathComponent] != nil)
    await gate.release()
    await a.value
    await b.value
    #expect(await gate.starts == 2)
    #expect(model.speakerTickets[session.lastPathComponent] == nil)
}
