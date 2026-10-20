import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes
@testable import MeetNotesTranscription

// MARK: pomoce

private let now = Date(timeIntervalSince1970: 5_000)
private let budget = ContextBudget(tokens: 4_096)
private let noteLimit = ContextBudget(tokens: 4_096).promptChars(replyTokens: ContextBudget.noteReplyTokens) // 4300

/// Dokładnie `n` znaków z pełnych słów rozdzielonych spacją (bez końcowej spacji).
private func words(_ n: Int) -> String {
    let s = String(String(repeating: "word ", count: n / 5 + 1).prefix(n))
    return s.hasSuffix(" ") ? String(s.dropLast()) + "w" : s
}

/// `count` wypowiedzi po `chars` znaków, na przemian Them/Me, co 10 s.
private func bigTranscript(count: Int, chars: Int) -> Transcript {
    transcript((0..<count).map { utt(words(chars), $0 % 2 == 0 ? .them : .me, at: Double($0) * 10) })
}

private func isMap(_ c: ChatStub.Call) -> Bool { c.system.contains("You condense part") }
private func isReduce(_ c: ChatStub.Call) -> Bool { c.system.contains("condensed version of the full recording") }

/// Mapa „po ludzku": każda linia wejścia → ta sama etykieta `[m:ss] Me|Them:` i krótka treść.
private func condense(_ user: String) -> String {
    user.components(separatedBy: "\n").map { line in
        guard let r = line.range(of: ": ") else { return line }
        return String(line[..<r.upperBound]) + "short"
    }.joined(separator: "\n")
}

/// Najgorszy przypadek: model zużywa całe `max_tokens` (× 2,4 znaku), w liniach po ~100 znaków.
private func worstCaseReply(_ maxTokens: Int?) -> String {
    let total = Int(Double(maxTokens ?? 0) * ContextBudget.charsPerToken)
    var lines: [String] = []
    var used = 0
    while used < total {
        let n = min(100, total - used)
        lines.append(words(n))
        used += n + 1
    }
    return lines.joined(separator: "\n")
}

private func summaryFiles(_ session: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: NotesStore(session: session).directory.path)) ?? [])
        .filter { $0.hasPrefix("summary") }
}

private func run(_ stub: ChatStub, session: URL, transcript t: Transcript, context: String = "", budget: ContextBudget? = budget,
                 client: OpenAICompatibleClient? = nil, generator g: NoteGenerator? = nil) async throws -> NoteSummary {
    let gen = g ?? NoteGenerator(client: client ?? localChatClient(stub), model: "local-model")
    return try await gen.generate(session: session, template: .standard, transcript: t, context: context,
                                  notesLanguage: .polish, budget: budget, now: now)
}

private func failure(_ stub: ChatStub, session: URL, transcript t: Transcript, context: String = "", budget: ContextBudget? = budget,
                     generator g: NoteGenerator? = nil) async -> String? {
    do { _ = try await run(stub, session: session, transcript: t, context: context, budget: budget, generator: g); return nil }
    catch NoteGenerationError.failed(let m) { return m }
    catch { return "unexpected: \(error)" }
}

// MARK: TranscriptSplitter

@Test func splitsAtLineBoundariesNeverMidLine() throws {
    let lines = (0..<6).map { "[0:0\($0)] Them: \(words(100))" }
    let parts = try TranscriptSplitter.parts(lines, maxChars: 350)
    #expect(parts.map(\.count) == [3, 3])                         // 3 × 113 + 2 × `\n` = 341 ≤ 350, czwarta już nie
    #expect(parts.flatMap { $0 } == lines)                        // kolejność i treść nietknięte
    for p in parts { #expect(p.joined(separator: "\n").count <= 350) }
    #expect(try TranscriptSplitter.parts([], maxChars: 350).isEmpty)
}

@Test func oversizedLineIsSplitAtWordBoundaryKeepingThePrefix() throws {
    let prefix = "[1:05] Me: "
    let parts = try TranscriptSplitter.parts([prefix + words(1_000)], maxChars: 300)
    let pieces = parts.flatMap { $0 }
    #expect(pieces.count >= 4)
    for piece in pieces {
        #expect(piece.hasPrefix(prefix) && piece.count <= 300 && !piece.hasSuffix(" "))
        // Granica słowa: każdy kawałek składa się z całych słów „word" (poza ostatnim, który kończy się jak oryginał).
        #expect(piece.dropFirst(prefix.count).hasPrefix("word"))
    }
    // Po zdjęciu prefiksów i sklejeniu wraca ten sam tekst.
    let rebuilt = pieces.map { String($0.dropFirst(prefix.count)) }.joined(separator: " ")
    #expect(rebuilt == words(1_000))
    // Mówca „Them" też zachowuje prefiks.
    let them = try TranscriptSplitter.parts(["[12:34] Them: " + words(600)], maxChars: 200).flatMap { $0 }
    #expect(them.count >= 3 && them.allSatisfy { $0.hasPrefix("[12:34] Them: ") })
}

@Test func unsplittableLineIsAnExplicitError() {
    let line = "[0:01] Them: " + String(repeating: "x", count: 500) // jedno słowo dłuższe niż limit
    #expect(throws: NoteGenerationError.failed("A single line is longer than the Context window. Raise it in Settings.")) {
        _ = try TranscriptSplitter.parts([line], maxChars: 200)
    }
}

// MARK: ścieżka jednoprzebiegowa

@Test func shortTranscriptTakesTheSinglePromptPath() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "# T\nbody" }
    _ = try await run(stub, session: session, transcript: transcript([utt("Prognoza na sobotę.")]))
    #expect(stub.calls.count == 1 && !isMap(stub.calls[0]) && !isReduce(stub.calls[0]))
}

@Test func apiProviderNeverSplits() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "# T\nbody" }
    // Bez budżetu (API) nawet bardzo długi transkrypt idzie jednym wywołaniem — ścieżka dzisiejsza.
    _ = try await run(stub, session: session, transcript: bigTranscript(count: 20, chars: 2_500), budget: nil, client: chatClient(stub))
    #expect(stub.calls.count == 1 && !isMap(stub.calls[0]) && !isReduce(stub.calls[0]))
}

@Test func singlePassBoundaryCountsNotesAndContext() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let t = transcript([utt(words(1_000), .them, at: 3)])
    let base = try #require(NotePromptBuilder.build(template: .standard, transcript: t, myNotes: "", context: "", notesLanguage: .polish))
    #expect(base.chars < noteLimit)                      // sam transkrypt mieści się…
    let notes = words(noteLimit - base.chars + 200)      // …ale z My notes już nie
    let stub = ChatStub { c in isMap(c) ? condense(c.user) : "# T\nbody" }
    _ = try NotesStore(session: session).writeMyNotes(notes)
    _ = try await run(stub, session: session, transcript: t)
    #expect(stub.calls.count == 2 && isMap(stub.calls[0]) && isReduce(stub.calls[1]))
    #expect(stub.calls[1].user.contains(notes))
}

// MARK: map-reduce

@Test func longTranscriptMapsEachPartThenReducesOnce() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { c in isMap(c) ? condense(c.user) : "# Weekly\n\n## Topic\n- ok" }
    let s = try await run(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500))
    #expect(stub.calls.count == 4)
    #expect(stub.calls.prefix(3).allSatisfy(isMap) && isReduce(stub.calls[3]))
    #expect(stub.calls[0].system.contains("part 1 of 3") && stub.calls[2].system.contains("part 3 of 3"))
    #expect(s.title == "Weekly")
    #expect(try NotesStore(session: session).readSummary() == s)
}

@Test func mapCallsSendHalfThePartAsMaxTokens() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { c in isMap(c) ? condense(c.user) : "# T\nbody" }
    _ = try await run(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500))
    let maps = stub.calls.filter(isMap)
    #expect(!maps.isEmpty)
    for m in maps {
        #expect(m.maxTokens == ContextBudget.maxTokens(inputChars: m.user.count, replyFactor: ContextBudget.mapReplyFactor))
        #expect(m.temperature == 0.2 && m.timeout == 330)         // ChatLimits.for(lokalny, .mapPart)
        // Cała mapa (system + user) i odpowiedź (połowa wejścia) mieszczą się w kontekście z marginesem.
        let inTokens = Double(m.system.count + m.user.count) / ContextBudget.charsPerToken
        #expect(inTokens + Double(m.maxTokens ?? 0) + Double(ContextBudget.marginTokens) <= Double(budget.tokens) + 1)
        #expect(m.user.count <= ContextBudget.mapPartCap)
    }
}

@Test func reduceInputKeepsSpeakerAndClock() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let t = bigTranscript(count: 6, chars: 2_500)
    let stub = ChatStub { c in isMap(c) ? condense(c.user) : "# T\nbody" }
    _ = try await run(stub, session: session, transcript: t)
    // Wejście części mapy to dokładnie linie `[m:ss] Me|Them: …` z renderera transkryptu.
    let rendered = NotePromptBuilder.transcriptLines(t)
    #expect(stub.calls.filter(isMap).flatMap { $0.user.components(separatedBy: "\n") } == rendered)
    // A reduce dostaje skondensowane linie z tym samym zegarem i mówcą.
    let reduceLines = stub.calls.last!.user.components(separatedBy: "\n").filter { $0.hasPrefix("[") }
    #expect(reduceLines == ["[0:00] Them: short", "[0:10] Me: short", "[0:20] Them: short", "[0:30] Me: short",
                            "[0:40] Them: short", "[0:50] Me: short"])
}

@Test func userNotesAndContextAppearOnlyInReduce() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    _ = try NotesStore(session: session).writeMyNotes("SECRET-MY-NOTE")
    let stub = ChatStub { c in isMap(c) ? condense(c.user) : "# T\nbody" }
    _ = try await run(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500), context: "SECRET-CONTEXT")
    for m in stub.calls.filter(isMap) {
        #expect(!m.system.contains("SECRET") && !m.user.contains("SECRET"))
    }
    let reduce = try #require(stub.calls.last)
    #expect(isReduce(reduce) && reduce.user.contains("SECRET-MY-NOTE") && reduce.user.contains("SECRET-CONTEXT"))
}

@Test func reduceInputNeverExceedsTheBudgetInTheWorstCase() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    // Model zużywa całe `max_tokens` w każdej części — suma wyjść mapy nie mieści się w jednym prompcie.
    let stub = ChatStub { c in isMap(c) ? worstCaseReply(c.maxTokens) : "# T\nbody" }
    _ = try? await run(stub, session: session, transcript: bigTranscript(count: 12, chars: 2_500))
    #expect(stub.calls.filter(isMap).count > 6)                  // był reduce hierarchiczny (druga warstwa map), nie jeden przebieg
    let reduces = stub.calls.filter(isReduce)
    #expect(reduces.allSatisfy { $0.system.count + $0.user.count <= noteLimit }) // reduce: nigdy ponad budżet
    for m in stub.calls.filter(isMap) { // a mapa na każdym poziomie mieści prompt + odpowiedź w oknie
        let tokens = Double(m.system.count + m.user.count) / ContextBudget.charsPerToken + Double(m.maxTokens ?? 0)
        #expect(tokens + Double(ContextBudget.marginTokens) <= Double(budget.tokens) + 1)
    }
}

@Test func tooLongEvenAfterHierarchyIsAnExplicitError() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { c in isMap(c) ? worstCaseReply(c.maxTokens) : "# T\nbody" }
    let message = await failure(stub, session: session, transcript: bigTranscript(count: 40, chars: 2_500))
    #expect(message == "The transcript is too long for this model's Context window. Raise it in Settings or use a model with a longer context.")
    #expect(!stub.calls.contains(where: isReduce))               // nic ponad budżet nie poszło do modelu
    #expect(summaryFiles(session).isEmpty)
}

@Test func notesAndContextAloneTooLongIsAnExplicitError() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    _ = try NotesStore(session: session).writeMyNotes(words(noteLimit + 500))
    let stub = ChatStub { _ in "# T\nbody" }
    let message = await failure(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500))
    #expect(message == "Your notes and context are too long for this model's Context window.")
    #expect(stub.calls.isEmpty)                                  // nie marnujemy wywołań map
}

@Test func tooSmallContextFailsWithoutCallingTheModel() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { _ in "# T\nbody" }
    let message = await failure(stub, session: session, transcript: transcript([utt("Prognoza na sobotę.")]),
                                budget: ContextBudget(tokens: 2_048))
    #expect(message == "local-model's Context window (2048 tokens) is too small for notes.")
    #expect(stub.calls.isEmpty)
}

// MARK: błędy części

@Test func oneFailedPartFailsTheSummary() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub { c in
        if c.system.contains("part 2 of 3") { throw StubHTTPError(status: 500, body: "boom") }
        return isMap(c) ? condense(c.user) : "# T\nbody"
    }
    let message = try #require(await failure(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500)))
    #expect(message.hasPrefix("Part 2 of 3 failed: ") && message.contains("local-model"))
    #expect(!stub.calls.contains(where: isReduce))               // reduce nie startuje po nieudanej części
    #expect(summaryFiles(session).isEmpty)                       // żadnej częściowej notatki
    #expect(try NotesStore(session: session).readSummary() == nil)
}

@Test func cutOffMapPartFailsTheSummary() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub(finishReasonFor: { $0.system.contains("part 3 of 3") ? "length" : nil }) { c in
        isMap(c) ? condense(c.user) : "# T\nbody"
    }
    let message = try #require(await failure(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500)))
    #expect(message.hasPrefix("Part 3 of 3 failed: ") && message.contains("cut off") && message.contains("Context window"))
    #expect(summaryFiles(session).isEmpty)
}

@Test func eachCallGetsItsOwnTimeout() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    // Trzy części po 0,2 s przy miękkim limicie 0,5 s NA WYWOŁANIE: razem > 0,5 s, a nic nie pada.
    let stub = ChatStub(delay: .milliseconds(200)) { c in isMap(c) ? condense(c.user) : "# T\nbody" }
    var gen = NoteGenerator(client: localChatClient(stub), model: "local-model", timeout: 600, chatTimeout: 660, maxTokens: 2_048)
    gen.mapLimits = ChatLimits(soft: 0.5, transport: 77, temperature: 0.2)
    _ = try await run(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500), generator: gen)
    #expect(stub.calls.filter(isMap).map(\.timeout) == [77, 77, 77])
    #expect(stub.calls.last!.timeout == 660 && stub.calls.last!.maxTokens == 2_048) // reduce = limity notatki
}

@Test func aSlowPartFailsWithItsNumber() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let stub = ChatStub(delay: .seconds(5)) { c in isMap(c) ? condense(c.user) : "# T\nbody" }
    var gen = NoteGenerator(client: localChatClient(stub), model: "local-model")
    gen.mapLimits = ChatLimits(soft: 0.2, transport: 77, temperature: 0.2)
    let message = try #require(await failure(stub, session: session, transcript: bigTranscript(count: 6, chars: 2_500), generator: gen))
    #expect(message.hasPrefix("Part 1 of 3 failed: ") && message.contains("didn't answer"))
    #expect(summaryFiles(session).isEmpty)
}
