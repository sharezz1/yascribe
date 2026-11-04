import Foundation
import Testing
import YascribeProviders
@testable import YascribeDictation

private func entry(_ n: Int, at date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> DictationEntry {
    DictationEntry(date: date, raw: "raw \(n)", text: "text \(n)")
}

@Suite struct DictationHistoryTests {
    @Test func addPutsNewestFirstAndTrimsToLimit() {
        var file = DictationHistoryFile()
        let first = entry(0)
        file.add(first)
        for n in 1...DictationHistoryFile.limit { file.add(entry(n)) }

        #expect(DictationHistoryFile.limit == 1000)
        #expect(file.entries.count == 1000)
        #expect(file.entries.first?.text == "text \(DictationHistoryFile.limit)")
        #expect(!file.entries.contains(where: { $0.id == first.id }))
    }

    @Test func removeAndClear() {
        var file = DictationHistoryFile()
        let a = entry(1), b = entry(2)
        file.add(a); file.add(b)

        file.remove(a.id)
        #expect(file.entries == [b])

        file.clear()
        #expect(file.entries.isEmpty)
    }

    @Test func daysGroupsNewestFirst() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day1Early = Date(timeIntervalSince1970: 1_700_000_000)        // 2023-11-14 22:13 UTC
        let day1Late = day1Early.addingTimeInterval(3_600)               // 2023-11-14 23:13 UTC
        let day2 = day1Early.addingTimeInterval(86_400)                  // 2023-11-15 22:13 UTC

        var file = DictationHistoryFile()
        let e1 = entry(1, at: day1Early), e2 = entry(2, at: day2), e3 = entry(3, at: day1Late)
        file.add(e1); file.add(e2); file.add(e3)

        let days = file.days(calendar: utc)
        #expect(days.count == 2)
        #expect(days[0].day == utc.startOfDay(for: day2))
        #expect(days[0].entries == [e2])
        #expect(days[1].day == utc.startOfDay(for: day1Early))
        #expect(days[1].entries == [e3, e1])
    }

    @Test func roundTripThroughJSONFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("dictation-history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Data w pełnych sekundach: zapis ISO 8601 nie przechowuje ułamków.
        var file = DictationHistoryFile()
        file.add(DictationEntry(date: Date(timeIntervalSince1970: 1_700_000_000), raw: "a", text: "b", inserted: false))
        try JSONFile.save(file, to: url)

        let loaded = try JSONFile.load(DictationHistoryFile.self, from: url, default: DictationHistoryFile())
        #expect(loaded == file)
        #expect(loaded.entries.first?.correctionFailed == nil)
        #expect(loaded.entries.first?.inserted == false)
    }

    @Test func corruptFileIsNotSilentlyOverwritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("dictation-history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ nie json".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            _ = try JSONFile.load(DictationHistoryFile.self, from: url, default: DictationHistoryFile())
        }
    }
}
