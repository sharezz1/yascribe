import Foundation
import Testing
import YascribeMeetings
@testable import YascribeNotes
@testable import YascribeTranscription

extension CalendarLink {
    static func fixture(title: String = "Standup") -> CalendarLink {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return CalendarLink(title: title, start: start, end: start + 1800, calendarName: "Work",
                            attendees: [.init(name: "Ala", email: nil)], eventIdentifier: "id", externalIdentifier: "ext", occurrenceStart: start)
    }
}

@Test func linkRoundTripsAndOldMetaWithoutItDecodes() throws {
    let old = #"{"manualTitle":"A"}"#.data(using: .utf8)!
    let m = try JSONDecoder().decode(NoteMeta.self, from: old)
    #expect(m.calendarEvent == nil && m.manualTitle == "A")
    var n = NoteMeta(); n.calendarEvent = .fixture()
    let again = try JSONDecoder().decode(NoteMeta.self, from: JSONEncoder().encode(n))
    #expect(again == n)
}

@Test func titleOrderIsManualThenCalendarThenAutoThenNote() {
    var m = NoteMeta(manualTitle: nil, autoTitle: "Auto"); m.calendarEvent = .fixture(title: "Weekly")
    #expect(NoteTitle.display(meta: m, noteTitle: "Note") == "Weekly")
    m.manualTitle = "Mine"; #expect(NoteTitle.display(meta: m, noteTitle: "Note") == "Mine")
    m.manualTitle = nil; m.calendarEvent = nil; #expect(NoteTitle.display(meta: m, noteTitle: "Note") == "Auto")
}

@Test func autoTitleDoesNothingWhenAnEventIsLinked() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    try store.updateMeta { $0.calendarEvent = .fixture() }
    let stub = ChatStub { _ in "Auto" }
    let r = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Prognoza na sobotę.")]),
                                     notesLanguage: .polish, store: store)
    #expect(r == nil && stub.calls.isEmpty)
    #expect(store.readMeta().autoTitle == nil && store.readMeta().calendarEvent != nil)
}

@Test func autoTitleDoesNotOverwriteAnEventLinkedWhileTheModelIsAnswering() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let stub = ChatStub { _ in
        try store.updateMeta { $0.calendarEvent = .fixture() }
        return "Auto"
    }
    let r = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Prognoza na sobotę.")]),
                                     notesLanguage: .polish, store: store)
    #expect(stub.calls.count == 1 && r == nil)
    #expect(store.readMeta().autoTitle == nil)
}

@Test func unlinkingRestoresTheAutoTitle() {
    var m = NoteMeta(autoTitle: "Auto"); m.calendarEvent = .fixture(title: "Weekly")
    #expect(NoteTitle.display(meta: m, noteTitle: nil) == "Weekly")
    m.calendarEvent = nil
    #expect(NoteTitle.display(meta: m, noteTitle: nil) == "Auto")
}

@Test func linkSnapshotSurvivesWithoutCalendarAccess() throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    try NotesStore(session: session).updateMeta { $0.calendarEvent = .fixture(title: "Weekly") }
    let reread = NotesStore(session: session).readMeta() // świeży odczyt z meta.json, bez EventKit
    #expect(reread.calendarEvent == .fixture(title: "Weekly"))
    #expect(NoteTitle.display(meta: reread, noteTitle: nil) == "Weekly")
}
