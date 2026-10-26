import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes
@testable import YascribeTranscription

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
    // ~30 znaków na linię, partie po ~90 znaków → kilka partii po 3 linie. Numeracja jest 1…N w każdej partii,
    // więc porażkę wywołuje treść wypowiedzi, nie jej numer.
    let stub = ChatStub { call in
        if call.user.contains("numer 4 ") { throw StubHTTPError(status: 500, body: "{}") } // partia z wypowiedzią 4 pada
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

@Test func correctorNeverLetsTheModelThink() async {
    // F20 P1: model hybrydowy z myśleniem milczał ponad 120 s; korekta zawsze prosi o odpowiedź bez rozumowania.
    let t = transcript([utt("no to jest test")])
    let stub = ChatStub { capitalizing($0.user) }
    _ = await corrector(stub).correct(t, language: .polish)
    #expect(stub.calls.count == 1 && stub.calls[0].reasoningEnabled == false)
}

// MARK: Budżet kontekstu i numeracja 1…N (F20 T12)

private func longTranscript(_ n: Int = 100) -> Transcript {
    transcript((0..<n).map { utt(String(repeating: "x", count: 100), at: Double($0) * 5) })
}

@Test func correctorBatchSizeFollowsTheBudget() async {
    let api = ChatStub { capitalizing($0.user) }
    _ = await corrector(api).correct(longTranscript(), language: .polish)
    let local = ChatStub { capitalizing($0.user) }
    let c = Corrector(client: chatClient(local), assignment: assignment, budget: ContextBudget(tokens: 4_096))
    _ = await c.correct(longTranscript(), language: .polish)
    let limit = c.batchLimit(language: .polish)
    #expect(limit > 0 && limit < 4_000)
    #expect(local.calls.count > api.calls.count)
    #expect(local.calls.allSatisfy { $0.user.count <= limit })
}

@Test func localBatchesAreCappedAt4000EvenWithAHugeContext() async {
    let stub = ChatStub { capitalizing($0.user) }
    let c = Corrector(client: chatClient(stub), assignment: assignment, budget: ContextBudget(tokens: 1_048_576))
    _ = await c.correct(longTranscript(), language: .polish)
    #expect(stub.calls.count >= 3 && stub.calls.allSatisfy { $0.user.count <= ContextBudget.correctionBatchCap })
}

@Test func shortLinesStillFitTheBudgetOnceRendered() async {
    // Sonda przeglądu T12: 400 krótkich linii — prefiks `[k] ` i `\n` to kilkadziesiąt procent rozmiaru, nie szum.
    let t = transcript((0..<400).map { utt("Tak, jasne.", at: Double($0)) })
    let stub = ChatStub { capitalizing($0.user) }
    let c = Corrector(client: chatClient(stub), assignment: assignment, budget: ContextBudget(tokens: 4_096))
    let r = await c.correct(t, language: .polish)
    let limit = c.batchLimit(language: .polish)
    #expect(stub.calls.count > 1 && r.failedBatches == 0)
    #expect(stub.calls.allSatisfy { $0.user.count <= limit })
    // I cały prompt z odpowiedzią mieści się w oknie: dokładnie to, co obiecuje reguła „sparowana".
    for call in stub.calls {
        let tokens = Double(call.system.count + call.user.count) / ContextBudget.charsPerToken + Double(call.maxTokens ?? 0)
        #expect(tokens + Double(ContextBudget.marginTokens) <= 4_096 + 1)
    }
}

@Test func splitCountsTheRenderedLength() {
    // 10 linii po 10 znaków: renderowana partia to `[k] ` + tekst + `\n` — limit 40 mieści 2 takie linie, nie 4.
    let lines = (1...10).map { (n: $0, text: String(repeating: "x", count: 10)) }
    let batches = CorrectionBatches.split(lines, maxChars: 40)
    #expect(batches.allSatisfy { CorrectionBatches.render($0.enumerated().map { (n: $0.offset + 1, text: $0.element.text) }).count <= 40 })
    #expect(batches.map(\.count) == [2, 2, 2, 2, 2])
}

@Test func localBatchSendsMaxTokensAndApiDoesNot() async {
    let t = transcript([utt("no to jest test"), utt("tak dokładnie tak", at: 5)])
    let local = ChatStub { capitalizing($0.user) }
    _ = await Corrector(client: chatClient(local), assignment: assignment, budget: ContextBudget(tokens: 4_096)).correct(t, language: .polish)
    #expect(local.calls[0].maxTokens == ContextBudget.maxTokens(inputChars: local.calls[0].user.count, replyFactor: ContextBudget.correctionReplyFactor))
    let api = ChatStub { capitalizing($0.user) }
    _ = await corrector(api).correct(t, language: .polish)
    #expect(api.calls[0].maxTokens == nil)
}

@Test func batchIsNumberedWithoutGapsAndMapsBack() async {
    // Wypowiedź b jest zaflagowana → pominięta; model dostaje [1] [2] [3] bez dziury i odpowiada tymi samymi numerami.
    let t = transcript([utt("aaa aaa"), utt("GIBBERISH", at: 3, flagged: true), utt("ccc ccc", at: 6), utt("ddd ddd", at: 9)])
    let stub = ChatStub { capitalizing($0.user) }
    let r = await corrector(stub).correct(t, language: .polish)
    #expect(stub.calls[0].user == "[1] aaa aaa\n[2] ccc ccc\n[3] ddd ddd")
    #expect(r.transcript.utterances.map(\.text) == ["Aaa aaa.", "GIBBERISH", "Ccc ccc.", "Ddd ddd."])
    #expect(r.failedBatches == 0 && r.rejectedLines == 0)
}

@Test func everyBatchStartsAtOne() async {
    let t = transcript((0..<12).map { utt("wypowiedź numer \($0) o prognozie", at: Double($0) * 5) })
    let stub = ChatStub { capitalizing($0.user) }
    let r = await corrector(stub, maxBatchChars: 95).correct(t, language: .polish)
    #expect(stub.calls.count >= 3 && stub.calls.allSatisfy { $0.user.hasPrefix("[1] ") })
    #expect(r.failedBatches == 0 && r.transcript.utterances.allSatisfy { $0.text.hasSuffix(".") })
    // Każda odpowiedź trafiła we właściwą wypowiedź (numer lokalny → oryginalna pozycja).
    #expect(r.transcript.utterances.enumerated().allSatisfy { $0.element.text.contains("numer \($0.offset) ") })
}

@Test func tooSmallBudgetFailsWithoutCallingTheModel() async {
    let stub = ChatStub { capitalizing($0.user) }
    let c = Corrector(client: chatClient(stub), assignment: assignment, budget: ContextBudget(tokens: 300))
    let t = transcript([utt("no to jest test")])
    let r = await c.correct(t, language: .polish)
    #expect(stub.calls.isEmpty)
    #expect(r.batches == 1 && r.failedBatches == 1 && r.failedCompletely)
    #expect(r.firstError == "fix-model's Context window (300 tokens) is too small for correction.")
    #expect(r.transcript.utterances[0].text == "no to jest test")
    let empty = await c.correct(transcript([]), language: .polish)
    #expect(empty.batches == 0 && stub.calls.isEmpty)
}

@Test func truncatedInputBatchFailsWithAReadableReason() async {
    // Odbiór 2.0b, pkt 2c: serwer obciął partię (HTTP 200) — partia liczy się jako nieudana, a oryginał zostaje.
    let t = transcript([utt(String(repeating: "no to jest test ", count: 300))])
    let stub = ChatStub(promptTokens: { _ in 30 }) { capitalizing($0.user) }
    let c = Corrector(client: localChatClient(stub), assignment: assignment, maxBatchChars: 6_000)
    let r = await c.correct(t, language: .polish)
    #expect(r.failedBatches == 1 && r.failedCompletely)
    #expect(r.firstError?.contains("fix-model's server cut off the start of the input") == true)
    #expect(r.transcript.utterances[0].text == t.utterances[0].text)
}

// MARK: Słownik w poleceniach (F21 T6)

/// Zestawy testów w dwóch plikach: korektor tutaj, podsumowanie i mapa w `PromptTests.swift` (`extension VocabularyInPromptTests`).
@Suite struct VocabularyInPromptTests {
    static let vocabulary = PromptVocabulary(terms: ["Orbit", "Kopt"], attendees: ["Anna Kowalska"])

    private func withVocabulary(_ v: PromptVocabulary?, budget: ContextBudget? = nil) -> Corrector {
        Corrector(client: chatClient(ChatStub { capitalizing($0.user) }), assignment: assignment, budget: budget, vocabulary: v)
    }

    @Test func correctorSystemIncludesVocabularyLines() {
        let s = withVocabulary(Self.vocabulary).system(language: .polish)
        #expect(s.contains("Known names and terms") && s.contains("Orbit; Kopt"))
        #expect(s.contains("Meeting attendees") && s.contains("Anna Kowalska"))
        // Po zdaniu o języku, przed „Extra instructions".
        let a = Corrector(client: chatClient(ChatStub { $0.user }), assignment: RoleAssignment(providerID: testProvider.id, model: "m", prompt: "Be brief."),
                          vocabulary: Self.vocabulary).system(language: .polish)
        let language = a.range(of: "The transcript language is Polish.")!.upperBound
        #expect(language < a.range(of: "Known names and terms")!.lowerBound)
        #expect(a.range(of: "Meeting attendees")!.upperBound < a.range(of: "Extra instructions from the user")!.lowerBound)
    }

    @Test func correctorSystemUnchangedWithoutVocabulary() {
        let plain = corrector(ChatStub { $0.user }).system(language: .polish)
        #expect(withVocabulary(nil).system(language: .polish) == plain)
        #expect(withVocabulary(PromptVocabulary()).system(language: .polish) == plain) // pusty słownik też nic nie dopisuje
    }

    @Test func batchLimitAccountsForVocabulary() {
        let big = DictionaryPrompt.make(Self.dictionary(150), link: nil, maxChars: DictionaryPrompt.maxChars(budget: ContextBudget(tokens: 4_096)))
        let small = ContextBudget(tokens: 4_096)
        let plain = withVocabulary(nil, budget: small), with = withVocabulary(big, budget: small)
        func expected(_ c: Corrector) -> Int {
            min(ContextBudget.correctionBatchCap, small.pairedInputChars(fixedChars: c.system(language: .polish).count, replyFactor: ContextBudget.correctionReplyFactor))
        }
        #expect(plain.batchLimit(language: .polish) == expected(plain))
        #expect(with.batchLimit(language: .polish) == expected(with))
        #expect(with.batchLimit(language: .polish) < plain.batchLimit(language: .polish))
        let huge = ContextBudget(tokens: 16_384)
        #expect(withVocabulary(nil, budget: huge).batchLimit(language: .polish) == 4_000)
        #expect(withVocabulary(big, budget: huge).batchLimit(language: .polish) == 4_000)
    }

    @Test func capturedCorrectorRequestListsExactlyThePrunedTerms() async throws {
        let budget = ContextBudget(tokens: 4_096)
        let v = DictionaryPrompt.make(Self.dictionary(150), link: nil, maxChars: DictionaryPrompt.maxChars(budget: budget))
        #expect(v.omittedTerms > 0 && v.terms.count + v.omittedTerms == 150)
        let stub = ChatStub { capitalizing($0.user) }
        let c = Corrector(client: chatClient(stub), assignment: assignment, budget: budget, vocabulary: v)
        _ = await c.correct(transcript([utt("no to jest test")]), language: .polish)
        let system = try #require(stub.calls.first?.system)
        let marker = "spell them exactly like this when they appear): "
        let line = try #require(system.components(separatedBy: "\n").first { $0.hasPrefix("Known names and terms") })
        let listed = String(line[line.range(of: marker)!.upperBound...].dropLast()).components(separatedBy: "; ") // bez końcowej kropki
        #expect(listed == v.terms)
        let missing = Self.dictionary(150).terms.map(\.text).filter { !system.contains($0) }
        #expect(missing.count == v.omittedTerms)
    }

    @Test func utteranceOverTheVocabularyLimitIsKeptAndNeverSent() async {
        // F5: wypowiedź mieści się w partii bez słownika, ale nie ze słownikiem — nie idzie do modelu, zostaje oryginalna.
        let budget = ContextBudget(tokens: 4_096)
        let v = DictionaryPrompt.make(Self.dictionary(150), link: nil, maxChars: DictionaryPrompt.maxChars(budget: budget))
        let stub = ChatStub { capitalizing($0.user) }
        let c = Corrector(client: chatClient(stub), assignment: assignment, budget: budget, vocabulary: v)
        let plainLimit = withVocabulary(nil, budget: budget).batchLimit(language: .polish), limit = c.batchLimit(language: .polish)
        let long = String(repeating: "x", count: limit) // sama partia `[1] …` miałaby limit + 4 znaki
        #expect("[1] \(long)\n".count > limit && "[1] \(long)\n".count <= plainLimit)
        let r = await c.correct(transcript([utt("no to jest test"), utt(long, at: 5), utt("tak dokładnie tak", at: 10)]), language: .polish)
        #expect(!stub.calls.isEmpty && stub.calls.allSatisfy { !$0.user.contains(long) })
        for call in stub.calls {
            #expect(call.user.count <= limit)
            let tokens = Double(call.system.count + call.user.count) / ContextBudget.charsPerToken + Double(call.maxTokens ?? 0)
            #expect(tokens + Double(ContextBudget.marginTokens) <= 4_096 + 1)
        }
        #expect(r.transcript.utterances.map(\.text) == ["No to jest test.", long, "Tak dokładnie tak."])
        #expect(r.rejectedLines == 1 && r.failedBatches == 0)
        // Same za długie wypowiedzi: jawny błąd bez wysyłki (jak za mały kontekst), nie cichy brak korekty.
        let only = ChatStub { capitalizing($0.user) }
        let alone = await Corrector(client: chatClient(only), assignment: assignment, budget: budget, vocabulary: v)
            .correct(transcript([utt(long)]), language: .polish)
        #expect(only.calls.isEmpty && alone.failedCompletely && alone.transcript.utterances[0].text == long)
        // API (bez budżetu): bez zmian — ta sama wypowiedź idzie do modelu.
        let api = ChatStub { capitalizing($0.user) }
        _ = await Corrector(client: chatClient(api), assignment: assignment, vocabulary: v).correct(transcript([utt(long)]), language: .polish)
        #expect(api.calls.count == 1)
    }

    /// `n` Termów „Termin001 …" (bez znaków, które `sanitize` zmienia), wszystkie `.normal`.
    static func dictionary(_ n: Int) -> UserDictionary {
        UserDictionary(terms: (1...n).map { DictionaryTerm("Termin\(String(format: "%03d", $0))Alfa") })
    }
}
