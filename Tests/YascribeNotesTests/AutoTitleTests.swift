import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes
@testable import YascribeTranscription

@Test func autoTitleRemovesOnlyMatchingQuotePairs() {
    #expect(AutoTitle.clean("„Prognoza na sobotę”") == "Prognoza na sobotę")
    #expect(AutoTitle.clean("«Plan zmian»") == "Plan zmian")
    #expect(AutoTitle.clean("‘Plan zmian’") == "Plan zmian")
    #expect(AutoTitle.clean("Review of \"Plan B\"") == "Review of \"Plan B\"")
    #expect(AutoTitle.clean("\"Plan") == "\"Plan")
    #expect(AutoTitle.clean("**„Plan”**") == "Plan")
}

@Test func autoTitleRejectsUntitledWithoutCaseSensitivity() {
    #expect(AutoTitle.clean("untitled meeting") == nil)
    #expect(AutoTitle.clean(" Untitled meeting. ") == nil)
}

@Test func autoTitleSkipsFencesAndThinkTags() {
    for input in ["```", "```markdown", "</think>", "<think>myślę nad tytułem</think>"] {
        #expect(AutoTitle.clean(input) == nil)
    }
    #expect(AutoTitle.clean("```\nForecast gap\n```") == "Forecast gap")
    #expect(AutoTitle.clean("  <THINK>\n </THINK>\n Forecast gap") == "Forecast gap")
}

@Test func autoTitleSkipsThinkBlock() {
    #expect(AutoTitle.clean("<think>\nUżytkownik prosi o tytuł.\n</think>\nPrognoza na sobotę") == "Prognoza na sobotę")
    #expect(AutoTitle.clean("<think>x</think>\nTytuł") == "Tytuł")
    #expect(AutoTitle.clean("<think>\nniezamknięte") == nil)
}

@Test func autoTitleIsStoredOnlyWhenNoTitleExists() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let stub = ChatStub { _ in "\"Forecast gap with Piotr.\"" }
    let t = transcript([utt("Prognoza na sobotę jest wyższa.")])
    let first = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: t, notesLanguage: .polish, store: store)
    #expect(first == "Forecast gap with Piotr")
    #expect(store.readMeta().autoTitle == "Forecast gap with Piotr")
    // Drugi raz: tytuł już jest — ani zapytania, ani zmiany.
    let second = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: t, notesLanguage: .polish, store: store)
    #expect(second == nil && stub.calls.count == 1)
    // Ręczny tytuł blokuje autotytuł.
    let other = tempDir()
    defer { try? FileManager.default.removeItem(at: other) }
    let store2 = NotesStore(session: other)
    try store2.updateMeta { $0.manualTitle = "Mine" }
    let stub2 = ChatStub { _ in "Auto" }
    _ = await AutoTitle.generate(client: chatClient(stub2), model: "m", transcript: t, notesLanguage: nil, store: store2)
    #expect(stub2.calls.isEmpty)
    #expect(store2.readMeta().autoTitle == nil && store2.readMeta().manualTitle == "Mine")
}

@Test func autoTitleIsNotStoredWhenItsRunIsNoLongerCurrent() async {
    // R23 fix round 1: w czasie wywołania modelu nowszy przebieg został bieżącym — odpowiedź przepada, `meta.json` bez tytułu.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let stub = ChatStub { _ in "Old run title" }
    let r = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Prognoza na sobotę.")]),
                                     notesLanguage: .polish, store: store, stillCurrent: { false })
    #expect(r == nil && stub.calls.count == 1)
    #expect(store.readMeta().autoTitle == nil)
}

@Test func autoTitleSkipsAnEmptyTranscript() async {
    // Review Focus #1: bez treści nie wołamy modelu.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "Title" }
    let r = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("x", flagged: true)]),
                                     notesLanguage: .polish, store: NotesStore(session: session))
    #expect(r == nil && stub.calls.isEmpty)
}

@Test func autoTitleReplyIsCleanedAndCapped() {
    #expect(AutoTitle.clean("# “Weekly sync.”\nextra line") == "Weekly sync")
    #expect(AutoTitle.clean(String(repeating: "a", count: 120))?.count == 80)
    #expect(AutoTitle.clean("Untitled meeting") == nil)
    #expect(AutoTitle.clean("  \n ") == nil)
}

@Test func autoTitleSamplesTheStartMiddleAndEndOfALongTranscript() throws {
    // ~100 wypowiedzi po ~100 znaków; znaczniki na początku, w środku, na końcu i jeden w „dziurze" między oknami.
    func line(_ i: Int, _ mark: String) -> Utterance { utt("\(mark) " + String(repeating: "słowo ", count: 15), at: Double(i) * 5) }
    var u = (0..<100).map { line($0, "plain-\($0)") }
    u[0] = line(0, "START-MARK")
    u[25] = line(25, "DROPPED-MARK")
    u[50] = line(50, "MID-MARK")
    u[99] = line(99, "END-MARK")
    let p = try #require(AutoTitle.prompt(transcript: transcript(u), notesLanguage: .polish))
    #expect(p.user.contains("START-MARK") && p.user.contains("MID-MARK") && p.user.contains("END-MARK"))
    #expect(!p.user.contains("DROPPED-MARK"))
    #expect(p.user.contains("[…]"))
    #expect(p.user.count < 8_000) // nie cały transkrypt (~11 000 znaków)
    // Krótki transkrypt idzie w całości.
    let short = try #require(AutoTitle.prompt(transcript: transcript([utt("alfa", at: 1), utt("beta", at: 9)]), notesLanguage: .polish))
    #expect(short.user.contains("alfa") && short.user.contains("beta") && !short.user.contains("[…]"))
}

@Test func autoTitleDoesNotOverwriteATitleTypedWhileTheModelIsAnswering() async throws {
    // Okno wyścigu: `shouldRun` przepuszcza, użytkownik wpisuje tytuł W TRAKCIE wywołania modelu.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let stub = ChatStub { _ in
        try store.updateMeta { $0.manualTitle = "Mine" }
        return "Auto"
    }
    let r = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Prognoza na sobotę.")]),
                                     notesLanguage: .polish, store: store)
    #expect(stub.calls.count == 1)
    #expect(r == nil)
    #expect(store.readMeta().manualTitle == "Mine" && store.readMeta().autoTitle == nil)
}

@Test func autoTitleGivesUpOnASlowModel() async {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let stub = ChatStub(delay: .seconds(5)) { _ in "Title" }
    let started = ContinuousClock.now
    let r = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Prognoza na sobotę.")]),
                                     notesLanguage: .polish, store: store, timeout: 0.2)
    #expect(r == nil && ContinuousClock.now - started < .seconds(3))
    #expect(store.readMeta().autoTitle == nil) // brak tytułu zamiast wiszącego „Naming…"
}

@Test func cutOffTitleStaysUntitledSilently() async {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let stub = ChatStub(finishReason: "length") { _ in "Forecast gap" }
    let r = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Prognoza na sobotę.")]),
                                     notesLanguage: .polish, store: store)
    #expect(r == nil && store.readMeta().autoTitle == nil)
}

@Test func autoTitlePassesItsLimitsToTheChatCall() async {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "Forecast gap" }
    _ = await AutoTitle.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Prognoza na sobotę.")]),
                                 notesLanguage: .polish, store: NotesStore(session: session), timeout: 120, chatTimeout: 150, maxTokens: 64)
    #expect(stub.calls[0].timeout == 150 && stub.calls[0].maxTokens == 64)
}

@Test func truncatedInputGivesNoAutoTitle() async {
    // Serwer obciął prompt: odpowiedź to ogon bez sensu — tytuł nie powstaje (cicho "Untitled meeting").
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let stub = ChatStub(promptTokens: { _ in 20 }) { _ in "Fragment ogona" }
    let t = transcript([utt(String(repeating: "Prognoza na sobotę jest wyższa. ", count: 300))])
    let title = await AutoTitle.generate(client: localChatClient(stub), model: "m", transcript: t, notesLanguage: .polish, store: store)
    #expect(title == nil && store.readMeta().autoTitle == nil && stub.calls.count == 1)
}
