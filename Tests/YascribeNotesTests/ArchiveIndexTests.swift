import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription

// MARK: pomoce (używa też ArchiveAskTests)

/// Syntetyczny serwer: embeddingi z „pojęć" (budget ≈ costs, owner ≈ who, release ≈ ship) i czat z ręki. Zapisuje żądania.
final class ArchiveStub: HTTPClient, @unchecked Sendable {
    struct Request: Sendable {
        let kind: String
        let model: String
        let input: String
        let system: String
        let user: String
        let reasoningEnabled: Bool?
    }
    private let lock = NSLock()
    private var log: [Request] = []
    let embedder: @Sendable (String) -> [Double]
    let chatter: @Sendable (Request) throws -> String
    let delay: Duration?
    var requests: [Request] { lock.withLock { log } }
    var embedCount: Int { requests.filter { $0.kind == "embeddings" }.count }
    var chatCount: Int { requests.filter { $0.kind == "chat" }.count }

    init(delay: Duration? = nil, embedder: @escaping @Sendable (String) -> [Double] = concept,
         chatter: @escaping @Sendable (Request) throws -> String = { _ in "NO_ANSWER" }) {
        self.delay = delay
        self.embedder = embedder
        self.chatter = chatter
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        let messages = body["messages"] as? [[String: Any]] ?? []
        let embedding = request.url!.path.hasSuffix("/embeddings")
        let call = Request(kind: embedding ? "embeddings" : "chat", model: body["model"] as? String ?? "",
                           input: body["input"] as? String ?? "", system: messages.first?["content"] as? String ?? "",
                           user: messages.last?["content"] as? String ?? "",
                           reasoningEnabled: (body["reasoning"] as? [String: Any])?["enabled"] as? Bool)
        lock.withLock { log.append(call) }
        if let delay { try await Task.sleep(for: delay) }
        let reply: [String: Any]
        do {
            reply = embedding ? ["data": [["embedding": embedder(call.input)]]] : ["choices": [["message": ["content": try chatter(call)]]]]
        } catch let e as StubHTTPError {
            return (Data(e.body.utf8), HTTPURLResponse(url: request.url!, statusCode: e.status, httpVersion: nil, headerFields: nil)!)
        }
        return (try JSONSerialization.data(withJSONObject: reply),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// Cztery osie: pieniądze, właściciel, wydanie, reszta (mały stały składnik, żeby wektor nigdy nie był zerowy).
@Sendable func concept(_ text: String) -> [Double] {
    let t = text.lowercased()
    var v = [0.0, 0.0, 0.0, 0.01]
    if t.contains("budget") || t.contains("costs") || t.contains("money") { v[0] = 1 }
    if t.contains("owner") || t.contains("who") { v[1] = 1 }
    if t.contains("release") || t.contains("ship") { v[2] = 1 }
    return v
}

func archiveClient(_ stub: ArchiveStub) -> OpenAICompatibleClient {
    OpenAICompatibleClient(provider: testProvider, key: "test-fake-key", http: stub)
}

func archiveSource(_ id: String, title: String = "Standup", notes: String = "", summary: String? = nil,
                   utterances: [Utterance] = []) -> ArchiveIndex.Source {
    ArchiveIndex.Source(sessionID: id, title: title, myNotes: notes, summary: summary,
                        transcript: utterances.isEmpty ? nil : transcript(utterances))
}

/// Indeks z danymi syntetycznymi: wektory z `concept` wybranego tekstu fragmentu.
func archiveIndex(_ sources: [ArchiveIndex.Source], space: String = "s") throws -> ArchiveIndex {
    var index = ArchiveIndex(space: space)
    for source in sources { try index.insert(source, vectors: source.pending.map { concept($0.text) }) }
    return index
}

private func words(_ n: Int) -> String { String(repeating: "x", count: n) }

// MARK: 1. fragmenty i odcisk

@Test func chunksFollowTranscriptLineFormatAndPackUpTo1200() {
    let source = archiveSource("a", utterances: [
        utt(words(500), .me, at: 5), utt(words(500), .them, at: 70), utt(words(500), .them, at: 3700),
    ])
    #expect(source.pending.count == 2)
    #expect(source.pending[0].start == 5)
    #expect(source.pending[0].text.hasPrefix("[0:05] Me: x"))
    #expect(source.pending[0].text.contains("\n[1:10] Them: x"))
    #expect(source.pending[1].start == 3700)
    #expect(source.pending[1].text.hasPrefix("[1:01:40] Them: x"))
    #expect(source.pending.allSatisfy { $0.text.count <= ArchiveIndex.chunkChars && $0.vector.isEmpty && $0.sessionID == "a" })
}

@Test func overlongLineIsSplitHardAndExcludedUtterancesAreSkipped() {
    let source = archiveSource("a", utterances: [utt(words(3_000), .them, at: 10), utt("English echo", .them, at: 20, flagged: true),
                                               utt("   ", .me, at: 30)])
    #expect(source.pending.count == 3)
    #expect(source.pending.allSatisfy { $0.text.count <= ArchiveIndex.chunkChars && $0.start == 10 })
    #expect(!source.pending.contains { $0.text.contains("English echo") })
}

@Test func myNotesAndSummaryBecomeParagraphChunksWithoutStart() {
    let source = archiveSource("a", notes: "Budget is 10\n\nOwner is Ann", summary: "# Plan\n\nShip in May")
    #expect(source.pending.count == 1) // małe akapity pakują się razem
    #expect(source.pending[0].start == nil)
    #expect(source.pending[0].text.contains("Budget is 10") && source.pending[0].text.contains("Ship in May"))
    let long = archiveSource("b", notes: (0..<30).map { _ in words(100) }.joined(separator: "\n\n"))
    #expect(long.pending.count > 1 && long.pending.allSatisfy { $0.text.count <= ArchiveIndex.chunkChars && $0.start == nil })
}

@Test func emptyMeetingHasNoChunksButHasFingerprint() {
    let source = archiveSource("a")
    #expect(source.pending.isEmpty)
    #expect(!source.fingerprint.isEmpty)
}

@Test func fingerprintChangesOnEveryInputAndIsOtherwiseStable() {
    let base = archiveSource("a", title: "T", notes: "n", summary: "s", utterances: [utt("hello", .me, at: 1)])
    #expect(base.fingerprint == archiveSource("a", title: "T", notes: "n", summary: "s", utterances: [utt("hello", .me, at: 1)]).fingerprint)
    #expect(base.fingerprint != archiveSource("a", title: "T2", notes: "n", summary: "s", utterances: [utt("hello", .me, at: 1)]).fingerprint)
    #expect(base.fingerprint != archiveSource("a", title: "T", notes: "n2", summary: "s", utterances: [utt("hello", .me, at: 1)]).fingerprint)
    #expect(base.fingerprint != archiveSource("a", title: "T", notes: "n", summary: "s2", utterances: [utt("hello", .me, at: 1)]).fingerprint)
    #expect(base.fingerprint != archiveSource("a", title: "T", notes: "n", summary: "s", utterances: [utt("hello!", .me, at: 1)]).fingerprint)
    #expect(base.fingerprint != archiveSource("a", title: "T", notes: "n", summary: "s", utterances: [utt("hello", .me, at: 2)]).fingerprint)
}

// MARK: 2. reconcile

@Test func reconcileDropsEditedAndDeletedAtOnceAndReturnsOnlyWhatIsMissing() throws {
    let a = archiveSource("a", notes: "Budget is 10"), b = archiveSource("b", notes: "Owner is Ann")
    var index = try archiveIndex([a, b])
    #expect(index.reconcile([a, b]).isEmpty)
    let editedB = archiveSource("b", notes: "Owner is Bob"), c = archiveSource("c", notes: "Ship in May")
    let pending = index.reconcile([a, editedB, c])
    #expect(pending.map(\.sessionID) == ["b", "c"])
    #expect(index.fingerprints.keys.sorted() == ["a"])
    #expect(!index.chunks.contains { $0.text.contains("Ann") })
    index.reconcile([c]) // a usunięte
    #expect(index.fingerprints.isEmpty && index.chunks.isEmpty && index.dimensions == nil)
}

// MARK: 3. przestrzeń i walidacja wektorów

@Test func spaceDiffersByProviderBaseURLAndModel() {
    let p = Provider(name: "A", baseURL: URL(string: "https://a.example.test/v1")!)
    let sameURLOtherID = Provider(name: "A", baseURL: p.baseURL)
    let otherURL = Provider(id: p.id, name: "A", baseURL: URL(string: "https://b.example.test/v1")!)
    let base = ArchiveIndex.space(provider: p, model: "m")
    #expect(base == ArchiveIndex.space(provider: p, model: "m"))
    #expect(base != ArchiveIndex.space(provider: sameURLOtherID, model: "m"))
    #expect(base != ArchiveIndex.space(provider: otherURL, model: "m"))
    #expect(base != ArchiveIndex.space(provider: p, model: "m2"))
}

@Test func insertRejectsWrongCountDimensionAndUnusableVectors() throws {
    let a = archiveSource("a", notes: "Budget is 10")
    var index = try archiveIndex([a])
    let before = index
    let b = archiveSource("b", notes: "Owner is Ann")
    #expect(throws: ArchiveError.invalidVector) { try index.insert(b, vectors: []) }
    #expect(throws: ArchiveError.dimensionMismatch) { try index.insert(b, vectors: [[1, 0, 0]]) }
    #expect(throws: ArchiveError.invalidVector) { try index.insert(b, vectors: [[.nan, 0, 0, 0]]) }
    #expect(throws: ArchiveError.invalidVector) { try index.insert(b, vectors: [[.infinity, 0, 0, 0]]) }
    #expect(throws: ArchiveError.invalidVector) { try index.insert(b, vectors: [[0, 0, 0, 0]]) }
    #expect(throws: ArchiveError.invalidVector) { try index.insert(b, vectors: [[]]) }
    #expect(index == before) // odrzucenie niczego nie zmienia
    try index.insert(b, vectors: [[3, 4, 0, 0]])
    let stored = index.chunks.first { $0.sessionID == "b" }!.vector
    #expect(stored.count == 16)
    let floats = stored.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    #expect(abs(floats[0] - 0.6) < 1e-6 && abs(floats[1] - 0.8) < 1e-6) // znormalizowany
}

// MARK: 4. zapis i odczyt

@Test func savedIndexSurvivesRestartButOtherSpaceOrDamageEmptiesIt() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("archive-index.json")
    let index = try archiveIndex([archiveSource("a", notes: "Budget is 10"), archiveSource("b", notes: "Owner is Ann")])
    try index.save(to: url)
    #expect(ArchiveIndex.load(from: url, space: "s") == index)
    #expect(ArchiveIndex.load(from: url, space: "other") == ArchiveIndex(space: "other"))
    #expect(ArchiveIndex.load(from: dir.appendingPathComponent("missing.json"), space: "s") == ArchiveIndex(space: "s"))
    try Data("not json".utf8).write(to: url)
    #expect(ArchiveIndex.load(from: url, space: "s") == ArchiveIndex(space: "s"))
}

@Test func singleBadVectorOrOrphanChunkInvalidatesTheWholeFile() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("archive-index.json")
    let good = try archiveIndex([archiveSource("a", notes: "Budget is 10"), archiveSource("b", notes: "Owner is Ann")])
    func damaged(_ change: (inout ArchiveIndex) -> Void) throws -> ArchiveIndex {
        var copy = good
        change(&copy)
        try copy.save(to: url)
        return ArchiveIndex.load(from: url, space: "s")
    }
    let empty = ArchiveIndex(space: "s")
    #expect(try damaged { $0.chunks[1].vector = $0.chunks[1].vector.prefix(8) } == empty) // zła długość
    #expect(try damaged { $0.chunks[1].vector = Data(repeating: 0xFF, count: 16) } == empty) // NaN
    #expect(try damaged { $0.chunks[1].vector = Data(count: 16) } == empty) // norma 0
    #expect(try damaged { c in c.chunks[1].vector = Data([Float(2), 0, 0, 0].flatMap { withUnsafeBytes(of: $0) { Array($0) } }) } == empty) // norma 2
    #expect(try damaged { $0.chunks.append(ArchiveIndex.Chunk(sessionID: "ghost", start: nil, text: "x", vector: $0.chunks[0].vector)) } == empty)
    #expect(try damaged { $0.dimensions = nil } == empty)
    #expect(try damaged { _ in } == good) // kontrola: nieuszkodzony wraca w całości
}

// MARK: 5. wyszukiwanie

@Test func searchFindsSemanticMatchWithoutSharedWords() throws {
    let index = try archiveIndex([archiveSource("a", notes: "The budget is tight"), archiveSource("b", notes: "Ship in May"),
                                  archiveSource("c", notes: "Who is the owner?")])
    let hits = index.search(vector: concept("costs"), terms: "costs", in: ["a", "b", "c"])
    #expect(hits.first?.sessionID == "a")
}

@Test func lexicalBoostBreaksSemanticTiesAndFoldsCaseAndDiacritics() throws {
    let index = try archiveIndex([archiveSource("a", notes: "budget alpha"), archiveSource("b", notes: "budget Zebra"),
                                  archiveSource("c", notes: "budget Café")])
    let zebra = index.search(vector: concept("budget"), terms: "the zebra", in: ["a", "b", "c"])
    #expect(zebra.map(\.sessionID) == ["b", "a", "c"]) // „b" wygrywa słowem; reszta remis → sessionID
    #expect(index.search(vector: concept("budget"), terms: "cafe", in: ["a", "b", "c"]).first?.sessionID == "c")
}

@Test func searchIsLimitedToScopeAndCapsPerMeeting() throws {
    var chunks: [ArchiveIndex.Source] = [archiveSource("many", utterances: (0..<10).map { utt("budget \(words(1_100)) \($0)", .them, at: Double($0) * 10) })]
    chunks.append(archiveSource("other", notes: "budget"))
    let index = try archiveIndex(chunks)
    #expect(index.chunks.filter { $0.sessionID == "many" }.count == 10)
    let all = index.search(vector: concept("budget"), terms: "budget", in: ["many", "other"], limit: 8, perSession: 3)
    #expect(all.filter { $0.sessionID == "many" }.count == 3 && all.count == 4)
    #expect(index.search(vector: concept("budget"), terms: "budget", in: ["other"]).map(\.sessionID) == ["other"])
    #expect(index.search(vector: concept("budget"), terms: "budget", in: []).isEmpty)
    #expect(index.search(vector: [1, 0], terms: "", in: ["many"]).isEmpty) // zły wymiar
    #expect(all == index.search(vector: concept("budget"), terms: "budget", in: ["many", "other"], limit: 8, perSession: 3))
}

// MARK: 6. embeddingi

@Test func embedCallsOncePerChunkWithConfiguredModelAndTitle() async throws {
    let stub = ArchiveStub()
    let source = archiveSource("a", title: "Planning", utterances: [utt(words(700), .me, at: 0), utt(words(700), .them, at: 10),
                                                                    utt(words(700), .me, at: 20)])
    let vectors = try await ArchiveIndex.embed(source, client: archiveClient(stub), model: "embed-1")
    #expect(source.pending.count == 3 && vectors.count == 3)
    #expect(stub.requests.map(\.model) == ["embed-1", "embed-1", "embed-1"])
    #expect(stub.requests.allSatisfy { $0.input.hasPrefix("Planning\n[") })
}

@Test func embedStopsWhenCancelled() async throws {
    let stub = ArchiveStub(delay: .milliseconds(300))
    let source = archiveSource("a", utterances: [utt(words(700), .me, at: 0), utt(words(700), .them, at: 10), utt(words(700), .me, at: 20)])
    let task = Task { try await ArchiveIndex.embed(source, client: archiveClient(stub), model: "m") }
    try await Task.sleep(for: .milliseconds(60))
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
    #expect(stub.embedCount == 1)
}

@Test func embedQueryRejectsUnusableOrWrongSizedVectors() async throws {
    let index = try archiveIndex([archiveSource("a", notes: "Budget is 10")])
    let zero = ArchiveStub(embedder: { _ in [0, 0, 0, 0] })
    await #expect(throws: ArchiveError.invalidVector) { try await index.embedQuery("q", client: archiveClient(zero), model: "m") }
    let short = ArchiveStub(embedder: { _ in [1, 0, 0] })
    await #expect(throws: ArchiveError.dimensionMismatch) { try await index.embedQuery("q", client: archiveClient(short), model: "m") }
    let fine = try await index.embedQuery("q", client: archiveClient(ArchiveStub(embedder: { _ in [3, 4, 0, 0] })), model: "m")
    #expect(fine == [0.6, 0.8, 0, 0])
}
