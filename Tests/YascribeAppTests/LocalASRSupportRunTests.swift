import Foundation
import Testing
import YascribeLocalASR
@testable import YascribeApp

/// Magazyn w katalogu tymczasowym, który nie istnieje: status `.missing`, nic nie jest pobierane ani kasowane u użytkownika.
@MainActor private func support() -> LocalASRSupport {
    LocalASRSupport(store: ModelStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")))
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

/// Każdy wariant ma własny magazyn i stan karty: przebieg Ultra nie może trzymać (ani blokować usunięcia) v3.
@Test @MainActor func localASRPicksTheSupportOfTheAssignedModel() {
    let data = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", data.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    defer { try? FileManager.default.removeItem(at: data) }
    #expect(model.localASR("")?.store.variant == .parakeetV3)
    #expect(model.localASR("parakeet-tdt-0.6b-v3")?.store.variant == .parakeetV3)
    #expect(model.localASR("parakeet-ultra")?.store.variant == .parakeetUltra)
    #expect(model.localASR("whisper-1") == nil)
    #expect(model.localASR("parakeet-ultra") !== model.localASR(""))
}

private actor Downloads {
    var forced: [Bool] = []
    func record(_ force: Bool) { forced.append(force) }
}

@Test @MainActor func downloadAgainWaitsUntilEveryRunEnds() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let calls = Downloads()
    let store = ModelStore(directory: root, download: { _, force, _ in await calls.record(force) }, modelsExist: { _ in true })
    // Uszkodzony plik uruchamia destrukcyjną naprawę force, jeśli bramka przepuści.
    let broken = store.modelDirectory.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin")
    try FileManager.default.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([1]).write(to: broken)
    let s = LocalASRSupport(store: store)
    s.beginRun()
    s.beginRun()
    s.endRun()
    await s.download()
    #expect(s.downloadError?.contains("in use") == true)
    #expect(await calls.forced.isEmpty)
    s.endRun()
    await s.download()
    #expect(await calls.forced == [true])
}

@Test @MainActor func downloadAndRemoveAreBlockedDuringPreparation() async {
    let calls = Downloads()
    let s = LocalASRSupport(store: ModelStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)"),
                                             download: { _, force, _ in await calls.record(force) }))
    s.apply(.preparing)
    s.remove()
    #expect(s.downloadError == inUse)
    await s.download()
    #expect(await calls.forced.isEmpty)
    #expect(s.phase == .preparing)
}
