import Foundation
import Testing
import YascribeProviders
@testable import YascribeTranscription

@Test func mistralPlanValidationAndSilence() throws {
    #expect(MistralDiarization.plan(trackSeconds: 1799).count == 1)
    #expect(MistralDiarization.plan(trackSeconds: 1800).count == 1)
    #expect(MistralDiarization.plan(trackSeconds: 5700) == [0..<1800, 1800..<3600, 3600..<5400, 5400..<5700])
    try MistralDiarization.validate(part: 0..<500, response: .init(segments: [], totalTokens: 64999))
    #expect(throws: MistralDiarizationError.cutShort) { try MistralDiarization.validate(part: 0..<500, response: .init(segments: [], totalTokens: 65000)) }
    for s in [MistralDiarizationResponse.Segment(start: -1, end: 1, speakerID: "a"), .init(start: 1, end: 1, speakerID: "a"), .init(start: 1, end: 506, speakerID: "a"), .init(start: 0, end: 1, speakerID: "")] {
        #expect(throws: MistralDiarizationError.invalidAnswer) { try MistralDiarization.validate(part: 0..<500, response: .init(segments: [s], totalTokens: 1)) }
    }
}

@Test func mistralReferencesAndThreePartMerge() {
    let segments: [MistralDiarization.Segment] = [("a",0,12), ("b",12,15), ("b",15,23), ("short",23,30)]
    let refs = MistralDiarization.references(from: segments, samples: [Int16](repeating: 0, count: 300), rate: 10)
    #expect(Set(refs.keys) == ["a", "b"] && refs["a"]?.count == 284 && refs["b"]?.count == 204)
    func response(_ name: String) -> MistralDiarizationResponse { .init(segments: [.init(start: 0, end: 4, speakerID: name)], totalTokens: 1) }
    let parts: [(range: Range<Double>, response: MistralDiarizationResponse, references: Set<String>)] = [(0..<10, response("a"), []), (10..<20, response("a"), []), (20..<30, response("p2-a"), ["p2-a"])]
    let merged = MistralDiarization.merge(parts: parts)
    #expect(merged.map(\.speaker) == ["a", "p2-a", "p2-a"] && merged.map(\.start) == [0, 10, 20])
}

import YascribeRecording
import YascribeSessionFormat

private actor MistralStub: MistralDiarizationService {
    var calls = 0
    func diarize(wav: Data, model: String, language: LanguageCode?, references: [String: Data]) async throws -> MistralDiarizationResponse {
        calls += 1
        return .init(segments: [], totalTokens: 10)
    }
}

@Test func mistralReadsFrameRangesAndCancelsBetweenParts() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try CAFWriter(url: url, sampleRate: 16_000, channels: 1)
    let samples = (0..<32_000).map { Int16($0 % 1000) }
    try writer.append(samples); try writer.close()
    #expect(try CAFReader.info(url: url).frames == 32_000)
    #expect(try CAFReader.read(url: url, frames: 10..<20).samples == Array(samples[10..<20]))
    #expect(throws: CAFReadError.self) { try CAFReader.read(url: url, frames: 31_999..<32_001) }
    let client = MistralStub()
    let task = Task {
        try await MistralDiarization.run(track: url, client: client, language: nil, partSeconds: 1) { _, _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await client.calls == 1)
}
