import Foundation
import Testing
@testable import YascribeProviders

/// Fałszywe katalogi `mn-<UUID>` (wzorzec sprzątający `scripts/test.sh`); prawdziwego `Application Support` nie ruszamy.
private struct Sandbox {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    var old: URL { base.appendingPathComponent("MeetNotes") }
    var new: URL { base.appendingPathComponent("Yascribe") }

    init() throws { try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }

    func write(_ name: String, _ text: String, in root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: root.appendingPathComponent(name))
    }

    func read(_ name: String, in root: URL) -> String? {
        (try? Data(contentsOf: root.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) }
    }

    func exists(_ root: URL) -> Bool { FileManager.default.fileExists(atPath: root.path) }

    func migration(running: Bool = false) -> DataDirectoryMigration {
        DataDirectoryMigration(oldRoot: old, newRoot: new, isOldAppRunning: { running })
    }

    func cleanup() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        try? FileManager.default.removeItem(at: base)
    }
}

@Test func movesOldDirectoryWhenNewIsMissing() throws {
    let s = try Sandbox(); defer { s.cleanup() }
    try s.write("providers.json", "{\"providers\":[]}", in: s.old)
    #expect(s.migration().run() == .moved)
    #expect(s.read("providers.json", in: s.new) == "{\"providers\":[]}")
    #expect(!s.exists(s.old))
}

@Test func emptyNewDirectoryIsTreatedAsMissing() throws {
    let s = try Sandbox(); defer { s.cleanup() }
    try s.write("providers.json", "A", in: s.old)
    try FileManager.default.createDirectory(at: s.new, withIntermediateDirectories: true)
    #expect(s.migration().run() == .moved)
    #expect(s.read("providers.json", in: s.new) == "A")
    // Finder dokłada `.DS_Store` po samym otwarciu pustego folderu — to nadal „pusty".
    let t = try Sandbox(); defer { t.cleanup() }
    try t.write("providers.json", "B", in: t.old)
    try t.write(".DS_Store", "x", in: t.new)
    #expect(t.migration().run() == .moved)
    #expect(t.read("providers.json", in: t.new) == "B")
}

@Test func bothDirectoriesWithDataAreReportedNotMerged() throws {
    let s = try Sandbox(); defer { s.cleanup() }
    try s.write("settings.json", "old", in: s.old)
    try s.write("settings.json", "new", in: s.new)
    #expect(s.migration().run() == .bothHaveData)
    #expect(s.read("settings.json", in: s.old) == "old")
    #expect(s.read("settings.json", in: s.new) == "new")
}

@Test func runningOldAppBlocksTheMove() throws {
    let s = try Sandbox(); defer { s.cleanup() }
    try s.write("providers.json", "A", in: s.old)
    #expect(s.migration(running: true).run() == .oldAppRunning)
    #expect(s.read("providers.json", in: s.old) == "A")
    #expect(!s.exists(s.new))
}

@Test func nothingToDoWhenOldIsMissing() throws {
    let s = try Sandbox(); defer { s.cleanup() }
    #expect(s.migration().run() == .notNeeded)
    #expect(!s.exists(s.new))
}

@Test func moveFailureLeavesOldDirectoryIntactAndReportsError() throws {
    let s = try Sandbox(); defer { s.cleanup() }
    let parent = s.base.appendingPathComponent("readonly")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    try s.write("providers.json", "A", in: s.old)
    try s.write("sessions", "S", in: s.old)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path) }
    let m = DataDirectoryMigration(oldRoot: s.old, newRoot: parent.appendingPathComponent("Yascribe"), isOldAppRunning: { false })
    guard case .failed = m.run() else { Issue.record("expected .failed"); return }
    #expect(s.read("providers.json", in: s.old) == "A")
    #expect(s.read("sessions", in: s.old) == "S")
}

@Test func unknownFilesInNewDirectoryAreNotOverwritten() throws {
    let s = try Sandbox(); defer { s.cleanup() }
    try s.write("providers.json", "A", in: s.old)
    try s.write("foreign.txt", "F", in: s.new)
    guard case .failed(let message) = s.migration().run() else { Issue.record("expected .failed"); return }
    #expect(message.hasPrefix("unexpected files in"))
    #expect(s.read("providers.json", in: s.old) == "A")
    #expect(s.read("foreign.txt", in: s.new) == "F")
}

@Test func dataDirOverrideIsDetected() {
    #expect(YascribePaths.isOverridden(["YASCRIBE_DATA_DIR": "/x"]))
    #expect(!YascribePaths.isOverridden([:]))
    #expect(!YascribePaths.isOverridden(["YASCRIBE_DATA_DIR": ""]))
}
