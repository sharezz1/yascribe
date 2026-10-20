import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes
@testable import MeetNotesTranscription

private let assignment = RoleAssignment(providerID: testProvider.id, model: "fix-model")

private func corrector(_ stub: ChatStub, maxBatchChars: Int = 6_000) -> Corrector {
    Corrector(client: chatClient(stub), assignment: assignment, maxBatchChars: maxBatchChars)
}

/// Odpowiedź modelu, która „poprawia" każdą linię na wielką literę i kropkę, zachowując numery.
private func capitalizing(_ user: String) -> String {
    user.components(separatedBy: "\n").map { line -> String in
        guard let close = line.firstIndex(of: "]") else { return line }
        let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return "\(line[...close]) \(text.prefix(1).uppercased() + text.dropFirst())."
    }.joined(separator: "\n")
}

@Test func correctorAppliesLinesWhenNumbersMatchAndKeepsTimingAndSpeaker() async {
    let t = transcript([utt("no to jest test", .them, at: 3), utt("tak dokładnie tak", .me, at: 9)])
    let r = await corrector(ChatStub { capitalizing($0.user) }).correct(t, language: .polish)
    #expect(r.transcript.utterances.map(\.text) == ["No to jest test.", "Tak dokładnie tak."])
    #expect(r.transcript.utterances.map(\.start) == [3, 9])
    #expect(r.transcript.utterances.map(\.speaker) == [.them, .me])
    #expect(r.batches == 1 && r.failedBatches == 0 && r.rejectedLines == 0)
}

@Test func batchWithWrongNumbersStaysOriginal() async {
    let t = transcript([utt("no to jest test"), utt("tak dokładnie tak", at: 5)])
    let r = await corrector(ChatStub { _ in "[1] x\n[3] y" }).correct(t, language: .polish)
    #expect(r.transcript.utterances.map(\.text) == ["no to jest test", "tak dokładnie tak"])
    #expect(r.failedBatches == 1)
}

@Test func lineOutsideLengthBandStaysOriginal() async {
    // Model skrócił drugą linię do jednego słowa — poza pasmem 0,6–1,6×, więc zostaje oryginał.
    let t = transcript([utt("no to jest test"), utt("tak dokładnie tak jak mówiłem wcześniej", at: 5)])
    let r = await corrector(ChatStub { _ in "[1] No to jest test.\n[2] Tak." }).correct(t, language: .polish)
    #expect(r.transcript.utterances[0].text == "No to jest test.")
    #expect(r.transcript.utterances[1].text == "tak dokładnie tak jak mówiłem wcześniej")
    #expect(r.rejectedLines == 1)
}

@Test func oneFailedBatchDoesNotAffectTheOthers() async {
    // Review Focus #5: długie spotkanie = wiele partii; jedna pada, reszta zostaje poprawiona, nic nie ginie.
    let t = transcript((0..<12).map { utt("wypowiedź numer \($0) o prognozie", at: Double($0) * 5) })
    // ~30 znaków na linię, partie po ~90 znaków → kilka partii po 3 linie
    let stub = ChatStub { call in
        if call.user.contains("[4]") { throw StubHTTPError(status: 500, body: "{}") } // partia z linią 4 pada
        return capitalizing(call.user)
    }
    let r = await corrector(stub, maxBatchChars: 95).correct(t, language: .polish)
    #expect(r.batches >= 3)
    #expect(r.failedBatches == 1)
    #expect(r.transcript.utterances.count == 12)
    let changed = r.transcript.utterances.filter { $0.text.hasSuffix(".") }.count
    let original = r.transcript.utterances.filter { !$0.text.hasSuffix(".") }.count
    #expect(original >= 1 && changed >= 6 && changed + original == 12) // jedna partia została oryginalna, reszta poprawiona
}

@Test func correctedTranscriptKeepsLanguageFlagsAndNeverSendsFlaggedLines() async {
    // Review Focus #4: flaga zostaje, wypowiedź zaflagowana nie idzie do modelu.
    // Flaga w ŚRODKU: numer linii musi trafić we właściwą wypowiedź także wtedy, gdy zaflagowaną pominięto.
    let t = transcript([utt("no to jest test"), utt("GIBBERISH-FROM-A-WRONG-LANGUAGE", at: 5, flagged: true), utt("tak dokładnie tak", at: 9)])
    let stub = ChatStub { capitalizing($0.user) }
    let r = await corrector(stub).correct(t, language: .polish)
    #expect(stub.calls.allSatisfy { !$0.user.contains("GIBBERISH") })
    #expect(r.transcript.utterances[1].languageMismatch == .english)
    #expect(r.transcript.utterances[1].text == "GIBBERISH-FROM-A-WRONG-LANGUAGE")
    #expect(r.transcript.utterances[1].excludedFromNotes)
    #expect(r.transcript.utterances[0].text == "No to jest test." && r.transcript.utterances[2].text == "Tak dokładnie tak.")
}

@Test func emptyOrFullyFlaggedTranscriptSendsNothingToTheCorrector() async {
    let stub = ChatStub { _ in "[1] x" }
    let r1 = await corrector(stub).correct(transcript([]), language: .polish)
    let r2 = await corrector(stub).correct(transcript([utt("zaflagowane", flagged: true)]), language: .polish)
    #expect(stub.calls.isEmpty)
    #expect(r1.batches == 0 && r2.batches == 0)
}

@Test func multiLineUtteranceIsSentAsOneLineSoItsTailIsNotLost() async {
    // Przegląd T6, D1: ogon po `\n` nie może znikać z poprawionego transkryptu.
    let t = transcript([utt("Akapit pierwszy długi.\nkoniec wypowiedzi")])
    let stub = ChatStub { capitalizing($0.user) }
    let r = await corrector(stub).correct(t, language: .polish)
    #expect(stub.calls.allSatisfy { !$0.user.dropFirst(4).contains("\n") }) // jedna wypowiedź = jedna linia
    #expect(r.transcript.utterances[0].text.contains("koniec wypowiedzi"))
    #expect(CorrectionBatches.render([(n: 1, text: "a\r\nb\nc")]) == "[1] a b c")
}

@Test func slowBatchIsGivenUpOnAndTheOriginalIsKept() async {
    // Odbiór T13: korekta „wisiała" kilkanaście minut — jedno wywołanie modelu bez całkowitego limitu czasu.
    let t = transcript([utt("no to jest test")])
    let stub = ChatStub(delay: .seconds(5)) { capitalizing($0.user) }
    var c = corrector(stub)
    c.batchTimeout = 0.2
    let started = ContinuousClock.now
    let r = await c.correct(t, language: .polish)
    #expect(ContinuousClock.now - started < .seconds(3)) // nie czekamy na 5 s odpowiedzi
    #expect(r.transcript.utterances[0].text == "no to jest test")
    #expect(r.failedBatches == 1 && r.failedCompletely)
    #expect(r.firstError?.contains("didn't answer") == true)
}

@Test func cutOffBatchFailsWithAReadableReason() async {
    let t = transcript([utt("no to jest test")])
    let stub = ChatStub(finishReason: "length") { capitalizing($0.user) }
    let r = await corrector(stub).correct(t, language: .polish)
    #expect(r.failedBatches == 1 && r.failedCompletely)
    #expect(r.firstError?.contains("cut off") == true && r.firstError?.contains("fix-model") == true)
    #expect(r.transcript.utterances[0].text == "no to jest test")
}

@Test func emptyReplyBatchFailsWithAReadableReason() async {
    let t = transcript([utt("no to jest test")])
    let r = await corrector(ChatStub { _ in "<think>nic</think>" }).correct(t, language: .polish)
    #expect(r.failedBatches == 1)
    #expect(r.firstError == "fix-model returned an empty reply.")
}

@Test func correctorPassesItsLimitsToTheChatCall() async {
    let t = transcript([utt("no to jest test")])
    let stub = ChatStub { capitalizing($0.user) }
    let c = Corrector(client: chatClient(stub), assignment: assignment, batchTimeout: 300, chatTimeout: 330, temperature: 0.2)
    _ = await c.correct(t, language: .polish)
    #expect(stub.calls[0].timeout == 330 && stub.calls[0].temperature == 0.2 && stub.calls[0].maxTokens == nil)
}
