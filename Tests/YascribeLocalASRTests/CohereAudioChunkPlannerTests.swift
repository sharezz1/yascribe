// Źródło: altic-dev/FluidAudio@386f7195670b77f2954c7ee143ec63fcb50b6c3b, Tests/FluidAudioTests/ASR/Cohere/CohereAudioChunkPlannerTests.swift
// Licencja: Apache-2.0 (LICENSES/Apache-2.0.txt).
// Zmodyfikowano w Yascribe: test z Tests/FluidAudioTests/ASR/Cohere, migracja XCTest do swift-testing.

import Testing
@testable import YascribeLocalASR

@Suite struct CohereAudioChunkPlannerTests {
    @Test func testShortAudioUsesSingleChunk() {
        let samples = Array(repeating: Float(0.1), count: 20 * 16_000)

        let chunks = CohereAudioChunkPlanner.makeChunks(
            audioSamples: samples,
            sampleRate: 16_000,
            maxAudioSamples: 480_000
        )

        #expect(chunks == [.init(startSample: 0, endSample: samples.count)])
    }

    @Test func testLongAudioSplitsAtQuietBoundaryNearChunkEnd() {
        var samples = Array(repeating: Float(0.8), count: 34 * 16_000)
        let quietStart = 27 * 16_000
        let quietEnd = quietStart + 1_600
        for index in quietStart..<quietEnd {
            samples[index] = 0.001
        }

        let chunks = CohereAudioChunkPlanner.makeChunks(
            audioSamples: samples,
            sampleRate: 16_000,
            maxAudioSamples: 480_000
        )

        #expect(chunks.count == 2)
        #expect(chunks[0].endSample == quietStart)
        #expect(chunks[1].startSample == quietStart)
        #expect(chunks[1].endSample == samples.count)
    }

    @Test func testQuietestSplitPointFallsBackToMiddleForShortSearchRange() {
        let samples = Array(repeating: Float(0.3), count: 1_000)

        let split = CohereAudioChunkPlanner.findQuietestSplitPoint(
            samples,
            startSample: 100,
            endSample: 900,
            minEnergyWindowSamples: 1_600
        )

        #expect(split == 500)
    }

    @Test func testJoinChunkTextsAvoidsDuplicateSpacing() {
        let joined = CohereAudioChunkPlanner.joinChunkTexts([
            "Hello world",
            "this is fine",
            ".",
        ])

        #expect(joined == "Hello world this is fine.")
    }

    @Test func testJoinChunkTextsSkipsSpaceForCJKBoundaries() {
        let joined = CohereAudioChunkPlanner.joinChunkTexts([
            "你好",
            "世界",
        ])

        #expect(joined == "你好世界")
    }
}
