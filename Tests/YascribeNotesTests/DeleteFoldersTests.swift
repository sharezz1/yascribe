import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes

/// TASK-25/26: bramka usuwania, zapis bez odtwarzania sesji, foldery spotkań.

@Test func deleteBlockerRefusesRecordingBusyAndMoving() {
    #expect(DeleteMeeting.blocker(recording: false, busy: false, moving: false) == nil)
    #expect(DeleteMeeting.blocker(recording: true, busy: false, moving: false)?.contains("recorded") == true)
    #expect(DeleteMeeting.blocker(recording: false, busy: true, moving: false)?.contains("processed") == true)
    #expect(DeleteMeeting.blocker(recording: false, busy: false, moving: true)?.contains("moved") == true)
    // Przenoszenie wygrywa: komunikat mówi o zmianie lokalizacji, nie o samym przetwarzaniu.
    #expect(DeleteMeeting.blocker(recording: true, busy: true, moving: true)?.contains("moved") == true)
}

@Test func folderNamesAreNormalizedAndUniqueCaseInsensitively() throws {
    var file = FoldersFile()
    let folder = try file.create("  Sales   Calls ")
    #expect(folder.name == "Sales Calls")
    #expect(file.folders.count == 1)
    #expect(throws: FolderError.duplicate("sales calls")) { try file.create("sales calls") }
    #expect(throws: FolderError.emptyName) { try file.create("   ") }
    #expect(throws: FolderError.tooLong(FoldersFile.maxNameLength)) { try file.create(String(repeating: "a", count: 61)) }
}

@Test func renamingAFolderKeepsItsID() throws {
    var file = FoldersFile()
    let folder = try file.create("Sales")
    try file.create("Hiring")
    try file.rename(folder.id, to: "  Sales   EMEA ")
    #expect(file.folder(folder.id)?.name == "Sales EMEA")
    // Własna nazwa nie koliduje ze sobą, cudza (bez różnicy wielkości liter) tak.
    try file.rename(folder.id, to: "sales emea")
    #expect(throws: FolderError.duplicate("hiring")) { try file.rename(folder.id, to: " hiring ") }
}

@Test func deletingAFolderKeepsMeetingsAndFallsBackToNoFolder() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = root.appendingPathComponent("2026-10-28T10-00-00Z-abcd")
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    var file = FoldersFile()
    let folder = try file.create("Sales")
    let store = NotesStore(session: session)
    try store.updateMeta { $0.folderID = folder.id }
    #expect(store.readMeta().folderID == folder.id)
    let deleted = file.delete(folder.id)
    #expect(deleted)
    // Spotkanie zostaje, meta nietknięte, folder znika → sesja liczy się jako „No folder".
    #expect(FileManager.default.fileExists(atPath: session.path))
    #expect(store.readMeta().folderID == folder.id)
    #expect(file.folder(store.readMeta().folderID) == nil)
    let deletedAgain = file.delete(folder.id)
    #expect(!deletedAgain)
}

@Test func oldMetaWithoutFolderIDStillReads() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = root.appendingPathComponent("old-session")
    let notes = session.appendingPathComponent("notes")
    try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    let legacy = Data(#"{"autoTitle":"Kickoff","calendarEvent":null}"#.utf8)
    try legacy.write(to: notes.appendingPathComponent("meta.json"))
    let meta = NotesStore(session: session).readMeta()
    #expect(meta.autoTitle == "Kickoff")
    #expect(meta.folderID == nil)
}

@Test func strictStoreRefusesToRecreateADeletedSession() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = root.appendingPathComponent("gone")
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    let store = NotesStore(session: session, requiresExistingSession: true)
    try store.writeMyNotes("hello")
    // Sesja poszła do Kosza — późny zapis nie może odtworzyć katalogu.
    try FileManager.default.removeItem(at: session)
    #expect(throws: NotesStoreError.sessionMissing) { try store.writeMyNotes("late") }
    #expect(throws: NotesStoreError.sessionMissing) { try store.updateMeta { $0.manualTitle = "late" } }
    #expect(!FileManager.default.fileExists(atPath: session.path))
}

@Test func strictStoreCreatesOnlyTheNotesLeaf() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = root.appendingPathComponent("fresh")
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    let store = NotesStore(session: session, requiresExistingSession: true)
    try store.writeMyNotes("first")
    #expect(FileManager.default.fileExists(atPath: store.directory.path))
    #expect(try String(contentsOf: store.directory.appendingPathComponent("my-notes.md"), encoding: .utf8) == "first")
}

@Test func defaultStoreStillCreatesAMissingSession() throws {
    // Zachowanie innych klientów bez zmian: domyślny zapis nadal tworzy katalog.
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = root.appendingPathComponent("created-by-write")
    try NotesStore(session: session).writeMyNotes("x")
    #expect(FileManager.default.fileExists(atPath: session.appendingPathComponent("notes/my-notes.md").path))
}

@Test func foldersRoundTripThroughJSON() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("folders.json")
    var file = FoldersFile()
    try file.create("Sales")
    try JSONFile.save(file, to: url)
    let loaded = try JSONFile.load(FoldersFile.self, from: url, default: FoldersFile())
    #expect(loaded == file)
    // Brak pliku = brak folderów (stare dane bez folders.json).
    let missing = root.appendingPathComponent("missing.json")
    #expect(try JSONFile.load(FoldersFile.self, from: missing, default: FoldersFile()).folders.isEmpty)
}

@Test func strictMetaSaveRefusesWhenTheSessionVanishesDuringTheWrite() throws {
    // Regresja: `prepareDirectory()` sprawdza sesję, a zapis JSON następuje później. Zmiana w `updateMeta`
    // wykonuje się po przygotowaniu katalogu, więc tutaj usuwamy całą sesję w tym oknie.
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = root.appendingPathComponent("vanishing")
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    let store = NotesStore(session: session, requiresExistingSession: true)
    try store.updateMeta { $0.manualTitle = "before" }
    #expect(throws: (any Error).self) {
        try store.updateMeta { meta in
            meta.manualTitle = "late"
            try? FileManager.default.removeItem(at: session)
        }
    }
    // Zapis padł i NIE odtworzył katalogu spotkania (ani `notes/`).
    #expect(!FileManager.default.fileExists(atPath: session.path))
}

@Test func jsonSaveCreatesParentsOnlyWhenAsked() throws {
    // Domyślnie zgodnie ze starym zachowaniem: brakujące katalogi powstają.
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("a/b/notes/meta.json")
    try JSONFile.save(NoteMeta(manualTitle: "x"), to: nested)
    #expect(FileManager.default.fileExists(atPath: nested.path))
    // `createParents: false` nie tworzy niczego i kończy się błędem zapisu.
    let refused = root.appendingPathComponent("gone/session/notes/meta.json")
    #expect(throws: (any Error).self) { try JSONFile.save(NoteMeta(manualTitle: "y"), to: refused, createParents: false) }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("gone").path))
}

@Test func testTrashMustBeAnExistingFolderInsideTheDataFolder() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = root.appendingPathComponent("data")
    let trash = data.appendingPathComponent("test-trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    // Produkcja i brak zmiennej: Kosz systemowy.
    #expect(try MeetingTrash.destination(requested: nil, dataRoot: data) == .systemTrash)
    #expect(try MeetingTrash.destination(requested: "   ", dataRoot: data) == .systemTrash)
    // Właściwy katalog testowy wewnątrz katalogu danych.
    let destination = try MeetingTrash.destination(requested: trash.path, dataRoot: data)
    let expected = URL(fileURLWithPath: trash.path).standardizedFileURL.resolvingSymlinksInPath()
    #expect(destination == .directory(expected))
    // Poza katalogiem danych, sąsiad o wspólnym prefiksie, brak katalogu, sam katalog danych: błąd, nie Kosz.
    let outside = root.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let sibling = URL(fileURLWithPath: data.path + "-evil/test-trash")
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    for bad in [outside.path, sibling.path, root.appendingPathComponent("data/missing").path, data.path] {
        #expect(throws: MeetingTrash.TrashError.self) { try MeetingTrash.destination(requested: bad, dataRoot: data) }
        #expect(throws: MeetingTrash.TrashError.self) { try MeetingTrash.destination(requested: bad, dataRoot: nil) }
    }
}
