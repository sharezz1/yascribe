import Foundation
import Testing
@testable import YascribeNotes

private func summary(_ text: String) -> NoteSummary {
    NoteSummary(title: "T", markdown: text, templateID: "standard", model: "m", context: "", generatedAt: Date(timeIntervalSince1970: 1_000))
}

private func backups(_ store: NotesStore) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? [])
        .filter { $0.hasPrefix("summary-") }.sorted()
}

@Test func regenerationKeepsThePreviousSummaryAsABackup() throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    try store.writeSummary(summary("first"), now: Date(timeIntervalSince1970: 2_000))
    #expect(backups(store).isEmpty) // pierwsze generowanie nie ma czego kopiować
    try store.writeSummary(summary("second"), now: Date(timeIntervalSince1970: 2_005))
    let names = backups(store)
    #expect(names.count == 1)
    let old = try JSONDecoder.iso.decode(NoteSummary.self, from: Data(contentsOf: store.directory.appendingPathComponent(names[0])))
    #expect(old.markdown == "first")
    #expect(try store.readSummary()?.markdown == "second")
}

@Test func twoRegenerationsInOneSecondKeepBothBackups() throws {
    // Review Focus #3: ta sama sekunda → nazwy kopii nie mogą się powtórzyć.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let now = Date(timeIntervalSince1970: 3_000)
    try store.writeSummary(summary("a"), now: now)
    try store.writeSummary(summary("b"), now: now)
    try store.writeSummary(summary("c"), now: now)
    let names = backups(store)
    #expect(names.count == 2 && Set(names).count == 2)
    let texts = try names.map { try JSONDecoder.iso.decode(NoteSummary.self, from: Data(contentsOf: store.directory.appendingPathComponent($0))).markdown }
    #expect(Set(texts) == ["a", "b"])
    #expect(try store.readSummary()?.markdown == "c")
}

@Test func myNotesAndMetaRoundTrip() throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    #expect(store.readMyNotes() == "")
    #expect(try store.writeMyNotes("ask about Sunday") == nil)
    #expect(store.readMyNotes() == "ask about Sunday")
    #expect(try store.updateMeta { $0.manualTitle = "Forecast review" } == nil)
    #expect(store.readMeta().manualTitle == "Forecast review")
    #expect(store.problems().isEmpty)
}

/// Trzy nieczytelne pliki: `my-notes.md` (niepoprawny UTF-8), `summary.json` i `meta.json` (nie-JSON).
private func writeUnreadable(_ store: NotesStore) throws {
    try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
    try Data([0xFF, 0xFE, 0x41]).write(to: store.directory.appendingPathComponent("my-notes.md"))
    try "not json".write(to: store.directory.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
    try "{".write(to: store.directory.appendingPathComponent("meta.json"), atomically: true, encoding: .utf8)
}

@Test func unreadableFilesAreReportedNotTreatedAsMissing() throws {
    // Review Focus #11: brak pliku to nie błąd odczytu — i odwrotnie.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    #expect(store.problems().isEmpty) // brak plików = brak problemów
    #expect(try store.readSummary() == nil)
    try writeUnreadable(store)
    #expect(store.problems() == ["my-notes.md", "summary.json", "meta.json"])
    #expect(throws: (any Error).self) { _ = try store.readSummary() } // nieczytelny ≠ brak
}

@Test func unreadableFilesAreSetAsideBeforeTheyAreOverwritten() throws {
    // Zapis po błędzie odczytu nie może zjeść starych bajtów: plik idzie na bok PRZED zapisem, z komunikatem z nazwą.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    try writeUnreadable(store)
    let t = Date(timeIntervalSince1970: 7_000)
    let a = try #require(try store.writeMyNotes("fresh", now: t))
    let b = try #require(try store.updateMeta(now: t) { $0.manualTitle = "New" })
    let c = try #require(try store.writeSummary(summary("s"), now: t))
    #expect(a.contains("my-notes.md") && a.contains(".corrupt-"))
    #expect(b.contains("meta.json") && c.contains("summary.json"))
    let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
    let aside = names.filter { $0.contains(".corrupt-") }
    #expect(aside.count == 3)
    let mine = try #require(aside.first { $0.hasPrefix("my-notes.md") })
    let meta = try #require(aside.first { $0.hasPrefix("meta.json") })
    #expect(try Data(contentsOf: store.directory.appendingPathComponent(mine)) == Data([0xFF, 0xFE, 0x41])) // stare bajty zachowane
    #expect(try String(contentsOf: store.directory.appendingPathComponent(meta), encoding: .utf8) == "{")
    #expect(store.problems().isEmpty) // nowe pliki są czytelne
    #expect(store.readMyNotes() == "fresh" && store.readMeta().manualTitle == "New")
    #expect(try store.readSummary()?.markdown == "s")
    #expect(!names.contains { $0.hasPrefix("summary-") }) // nieczytelny summary nie jest „wersją do kopii"
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
