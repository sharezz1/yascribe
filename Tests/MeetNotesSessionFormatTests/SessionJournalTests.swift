import Foundation
import Testing
@testable import MeetNotesSessionFormat

private func tempDir() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func journalRoundTripsEvents() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    let j = try SessionJournal(url: url)
    let tb = Timebase(numer: 1, denom: 1)
    try j.append(.sessionStarted(hostTime: 10, timebase: tb, wallClock: Date(timeIntervalSince1970: 0)))
    try j.append(.trackOpened("system", hostTime: 11, sampleRate: 48_000, channels: 2, deviceUID: "BuiltInSpeakerDevice"))
    try j.close()
    let events = try SessionJournal.read(url: url)
    #expect(events.count == 2)
    #expect(events[1].type == .trackOpened)
    #expect(events[1].deviceUID == "BuiltInSpeakerDevice")
    #expect(events[0].timebase == tb)
}

@Test func journalRefusesToOverwriteExistingSession() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    _ = try SessionJournal(url: url)
    #expect(throws: JournalError.alreadyExists(url.path)) { _ = try SessionJournal(url: url) }
}

@Test func readerSkipsTruncatedLastLine() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    let j = try SessionJournal(url: url)
    try j.append(.sessionStarted(hostTime: 1, timebase: Timebase(numer: 1, denom: 1), wallClock: Date()))
    try j.close()
    let h = try FileHandle(forWritingTo: url)
    try h.seekToEnd()
    try h.write(contentsOf: Data("{\"type\":\"track.op".utf8))
    try h.close()
    #expect(try SessionJournal.read(url: url).count == 1)
}

@Test func readerRejectsCorruptLineInTheMiddle() throws {
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    try Data("{\"type\":\"session.started\",\"hostTime\":1}\nGARBAGE\n{\"type\":\"session.ended\",\"hostTime\":2}\n".utf8).write(to: url)
    #expect(throws: JournalError.corruptLine(2)) { _ = try SessionJournal.read(url: url) }
}

@Test func completeButCorruptLastLineIsAnError() throws {
    // ChatGPT #12: tolerujemy tylko urwany fragment BEZ kończącego LF.
    let url = try tempDir().appendingPathComponent("journal.jsonl")
    try Data("{\"type\":\"session.started\",\"hostTime\":1}\nGARBAGE\n".utf8).write(to: url)
    #expect(throws: JournalError.corruptLine(2)) { _ = try SessionJournal.read(url: url) }
}
