import Foundation
import Testing
@testable import YascribeTranscription

private func d(_ segments: [(String, Double, Double)], timed: Bool = true) -> SpeakerDiarization {
    SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                       audioFingerprint: nil, createdAt: nil, segments: segments.map {
        // Czas sesji przesunięty o 100 s: wynik ma być w czasie TORU.
        .init(speaker: $0.0, start: $0.1 + 100, end: $0.2 + 100, trackStart: timed ? $0.1 : nil, trackEnd: timed ? $0.2 : nil)
    })
}

@Test func overlapExcluded() {
    let s = VoiceSpans.speech(d([("A", 0, 30), ("B", 25, 35)]))
    #expect(s["A"]?.seconds == 25 && s["A"]?.spans == [0...25])
    #expect(s["B"]?.seconds == 5 && s["B"]?.spans == [30...35])
}

@Test func piecesUnderOneSecondDropped() {
    let s = VoiceSpans.speech(d([("A", 0, 0.9), ("A", 10, 12)]))
    #expect(abs((s["A"]?.seconds ?? 0) - 2.9) < 0.0001 && s["A"]?.spans == [10...12])
}

@Test func capAt120LongestFirst() {
    let s = VoiceSpans.speech(d([("A", 0, 10), ("A", 20, 120), ("A", 200, 230)]))
    #expect(s["A"]?.seconds == 140)
    #expect(s["A"]?.spans == [20...120, 200...220])
}

@Test func missingTrackTimesSkipped() {
    #expect(VoiceSpans.speech(d([("A", 0, 30)], timed: false)).isEmpty)
}
