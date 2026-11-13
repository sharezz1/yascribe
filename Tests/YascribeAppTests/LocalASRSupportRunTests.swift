import Foundation
import Testing
import YascribeLocalASR
@testable import YascribeApp

/// Magazyn w katalogu tymczasowym, który nie istnieje: status `.missing`, nic nie jest pobierane ani kasowane u użytkownika.
@MainActor private func support() -> LocalASRSupport {
    LocalASRSupport(store: isolatedModelStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")))
}

private let inUse = "Can't remove the on-device model while it is downloading or in use."

@Test @MainActor func removeIsBlockedUntilEveryRunEnds() {
    let s = support()
    s.beginRun()   // spotkanie
    s.beginRun()   // dyktowanie
    s.endRun()     // dyktowanie kończy się pierwsze
    s.remove()
    #expect(s.downloadError == inUse)
    s.endRun()
    s.remove()
    #expect(s.downloadError != inUse)
}

@Test @MainActor func releaseOfOneRunKeepsPreparingOfAnother() {
    let s = support()
    s.beginRun()
    s.apply(.preparing)   // spotkanie ładuje model
    s.beginRun()
    s.apply(.idle)        // `release()` dyktowania
    s.endRun()
    #expect(s.phase == .preparing)
    s.endRun()
    #expect(s.phase == .idle)
}

@Test @MainActor func runWithoutPreparingStillBalances() {
    let s = support()
    s.beginRun()   // np. krótkie nagranie: klient wraca przed ładowaniem, `.preparing` nie przychodzi
    s.endRun()
    s.remove()
    #expect(s.downloadError != inUse)
    #expect(s.phase == .idle)
}
