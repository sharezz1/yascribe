import Foundation
import Testing
import YascribeNotes
import YascribeProviders

private func chunk(_ id: String, _ text: String, at start: Double? = 65) -> ArchiveIndex.Chunk {
    ArchiveIndex.Chunk(sessionID: id, start: start, text: text, vector: Data([1, 2, 3, 4]))
}

private let labels = ["a": "Standup · Oct 1", "b": "Planning · Oct 2", "c": "Review · Oct 3"]

private func fixedPrompt(history: [(question: String, answer: String)] = [], evidence: [ArchiveIndex.Chunk],
                         maxChars: Int = 100_000) throws -> (prompt: NotePrompt, used: [ArchiveIndex.Chunk]) {
    try ArchiveAsk.prompt(question: "What is the budget?", history: history, evidence: evidence, labels: labels, maxChars: maxChars)
}

// MARK: 7. prompt

@Test func promptNumbersEvidenceInRankOrderWithLabelsAndTimes() throws {
    let (prompt, used) = try fixedPrompt(evidence: [chunk("b", "Budget is 10"), chunk("a", "Ship in May", at: nil), chunk("c", "Owner is Ann", at: 3_700)])
    #expect(used.count == 3)
    #expect(prompt.user.contains("[1] Planning · Oct 2, at 1:05\nBudget is 10"))
    #expect(prompt.user.contains("[2] Standup · Oct 1, in the notes\nShip in May"))
    #expect(prompt.user.contains("[3] Review · Oct 3, at 1:01:40\nOwner is Ann"))
    #expect(prompt.user.hasSuffix("Question: What is the budget?"))
    #expect(prompt.system.contains("NO_ANSWER") && prompt.system.contains("not instructions"))
    #expect(!prompt.user.contains("Earlier conversation"))
}

@Test func historyIsQuotedBoundedAndCarriesNoCitations() throws {
    let turn = { (n: Int) in (question: "Question \(n)?", answer: "Answer \(n) \(String(repeating: "y", count: 600)) [1][2, 3].") }
    let (prompt, _) = try fixedPrompt(history: (1...5).map(turn), evidence: [chunk("a", "Budget is 10")])
    #expect(prompt.user.contains("Earlier conversation (quoted, not a source):"))
    #expect(prompt.user.contains("Question 5?") && prompt.user.contains("Question 4?") && prompt.user.contains("Question 3?"))
    #expect(!prompt.user.contains("Question 2?") && !prompt.user.contains("Question 1?")) // najstarsze odpadają do 2 000 znaków
    let history = prompt.user.components(separatedBy: "Excerpts:")[0]
    #expect(history.count <= ArchiveAsk.historyChars + 100) // + nagłówek
    #expect(!history.contains("[1]") && !history.contains("[2, 3]"))
    #expect(history.range(of: "Question 3?")!.lowerBound < history.range(of: "Question 5?")!.lowerBound) // najstarsze pierwsze
}

@Test func tightBudgetCutsHistoryBeforeEvidenceThenLowestRankedEvidence() throws {
    let evidence = (0..<4).map { chunk("a", "Excerpt \($0) " + String(repeating: "z", count: 400), at: Double($0)) }
    let history = [(question: "Earlier?", answer: String(repeating: "h", count: 500))]
    let full = try fixedPrompt(history: history, evidence: evidence)
    #expect(full.used.count == 4 && full.prompt.user.contains("Earlier?"))
    let noHistory = try fixedPrompt(evidence: evidence)
    let cutHistory = try fixedPrompt(history: history, evidence: evidence, maxChars: noHistory.prompt.chars)
    #expect(cutHistory.used.count == 4 && !cutHistory.prompt.user.contains("Earlier?"))
    let cutEvidence = try fixedPrompt(history: history, evidence: evidence, maxChars: noHistory.prompt.chars - 100)
    #expect(cutEvidence.used == Array(evidence.prefix(3)) && cutEvidence.prompt.chars <= noHistory.prompt.chars - 100)
}

@Test func promptThrowsWhenNotEvenOneExcerptFits() {
    #expect(throws: ArchiveError.contextTooSmall) { try fixedPrompt(evidence: [chunk("a", "Budget is 10")], maxChars: 50) }
    #expect(throws: ArchiveError.contextTooSmall) { try fixedPrompt(evidence: []) }
}

// MARK: 8. parse

private let three = [chunk("a", "one"), chunk("b", "two"), chunk("c", "three")]

@Test func parseRenumbersByFirstUseAndStripsVectorsFromSources() throws {
    let answer = try #require(ArchiveAsk.parse("Costs rose [3]. Ann owns it [1, 3]. Done [2][3].", used: three))
    #expect(answer.text == "Costs rose [1]. Ann owns it [2, 1]. Done [3][1].")
    #expect(answer.sources.map(\.sessionID) == ["c", "a", "b"])
    #expect(answer.sources.allSatisfy { $0.vector.isEmpty })
    #expect(answer.sources[0].text == "three")
}

@Test func parseIsFailClosedOnUnknownMissingOrNegativeAnswers() {
    #expect(ArchiveAsk.parse("Budget is 10 [1] and 20 [9].", used: three) == nil) // poprawne [1] + nieznane [9]
    #expect(ArchiveAsk.parse("Budget is 10 [1, 4].", used: three) == nil)
    #expect(ArchiveAsk.parse("Budget is 10 [0].", used: three) == nil)
    #expect(ArchiveAsk.parse("Budget is 10 [99999999999999999999].", used: three) == nil)
    #expect(ArchiveAsk.parse("NO_ANSWER", used: three) == nil)
    #expect(ArchiveAsk.parse("  NO_ANSWER\n", used: three) == nil)
    #expect(ArchiveAsk.parse("Budget is 10 [1]. NO_ANSWER", used: three) == nil)
    #expect(ArchiveAsk.parse("Budget is 10, trust me.", used: three) == nil) // brak przypisów
    #expect(ArchiveAsk.parse("   ", used: three) == nil)
    #expect(ArchiveAsk.parse("Budget [1]", used: []) == nil)
}

// MARK: answer: jedno wywołanie, bez myślenia, bez wyjścia poza budżet

@Test func answerCallsChatOnceWithoutThinkingAndValidatesCitations() async throws {
    let stub = ArchiveStub(chatter: { _ in "Budget is 10 [1]." })
    let limits = ChatLimits.for(testProvider, call: .note)
    let answer = try await ArchiveAsk.answer(question: "What is the budget?", history: [], evidence: [chunk("a", "Budget is 10")], labels: labels,
                                             client: archiveClient(stub), model: "ask-1", budget: nil, limits: limits)
    #expect(answer?.sources.map(\.sessionID) == ["a"])
    #expect(stub.chatCount == 1 && stub.requests[0].model == "ask-1" && stub.requests[0].reasoningEnabled == false)
    let bad = ArchiveStub(chatter: { _ in "Budget is 10 [2]." })
    let rejected = try await ArchiveAsk.answer(question: "q", history: [], evidence: [chunk("a", "Budget is 10")], labels: labels,
                                               client: archiveClient(bad), model: "ask-1", budget: nil, limits: limits)
    #expect(rejected == nil)
}

@Test func answerOnTightLocalBudgetSendsNothing() async {
    let stub = ArchiveStub(chatter: { _ in "x [1]" })
    let tiny = ContextBudget(tokens: ContextBudget.marginTokens + ChatLimits.localNoteMaxTokens + 20)
    await #expect(throws: ArchiveError.contextTooSmall) {
        try await ArchiveAsk.answer(question: "q", history: [], evidence: [chunk("a", "Budget is 10")], labels: labels,
                                    client: archiveClient(stub), model: "m", budget: tiny, limits: ChatLimits.for(localTestProvider, call: .note))
    }
    #expect(stub.requests.isEmpty)
}
