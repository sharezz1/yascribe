import Foundation
import Testing
@testable import MeetNotesProviders

@Test func embeddingChangeAsksOnlyWhenOneWasAlreadySet() {
    let a = RoleAssignment(providerID: UUID(), model: "emb-a")
    let b = RoleAssignment(providerID: a.providerID, model: "emb-b")
    #expect(!GlobalSettings.embeddingChangeNeedsConfirmation(old: nil, new: a)) // pierwsze ustawienie — bez pytania
    #expect(!GlobalSettings.embeddingChangeNeedsConfirmation(old: a, new: a))
    #expect(GlobalSettings.embeddingChangeNeedsConfirmation(old: a, new: b))
    #expect(GlobalSettings.embeddingChangeNeedsConfirmation(old: a, new: nil))
}

@Test func duplicateProviderNamesAreRejected() {
    let file = ProvidersFile(providers: [openRouter])
    #expect(file.nameError("openrouter ") != nil) // ta sama nazwa, inna wielkość liter i spacja
    #expect(file.nameError("Ollama") == nil)
    #expect(file.nameError("  ") != nil)
}

@Test func keychainFailureIsNotShownAsNoKey() {
    struct Boom: Error {}
    #expect(KeyStatus.of { "test-fake-abcd1234" } == .set("••••1234")) // fałszywy klucz testowy, nie prawdziwy
    #expect(KeyStatus.of { nil } == .missing)
    if case .unreadable = KeyStatus.of({ throw Boom() }) {} else { Issue.record("oczekiwano .unreadable") }
}
