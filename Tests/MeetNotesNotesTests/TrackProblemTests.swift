import Foundation
import MeetNotesSessionFormat
import Testing
@testable import MeetNotesNotes
@testable import MeetNotesTranscription

/// Tor jak w dowodzie z odbioru 2026-10-16 (sesja …14-13-15Z-af52): `allZeros60s`, potem 277 s nagrania.
private func silentStart(_ id: String = "system") -> SessionSummary.Track {
    SessionSummary.Track(id: id, sampleRate: 48_000, channels: 2, frames: 13_317_120, failure: "allZeros60s")
}

@Test func silenceOnlyAtTheStartIsInformationNotAWarning() throws {
    // „Them" od 1:04 — bramka nie przepuszcza zer do ASR, więc dźwięk systemowy przyszedł później.
    let p = try #require(TrackProblem.of(tracks: [silentStart()], transcript: transcript([utt("dzień dobry", .them, at: 64)])).first)
    #expect(!p.isWarning)
    #expect(p.line == "System audio was silent for the first minute; recording continued.")
    #expect(p.detail.contains("4:37"))
}

@Test func silenceToTheEndStaysAWarning() throws {
    // Transkrypt bez „Them" (tylko „Me") = tor systemowy pusty do końca; bez transkryptu — nie wiadomo, też ostrzeżenie.
    let empty = try #require(TrackProblem.of(tracks: [silentStart()], transcript: transcript([utt("halo", .me, at: 5)])).first)
    #expect(empty.isWarning)
    let unknown = try #require(TrackProblem.of(tracks: [silentStart()], transcript: nil).first)
    #expect(unknown.isWarning)
    // Mikrofon: liczą się wypowiedzi „Me".
    let mic = try #require(TrackProblem.of(tracks: [silentStart("mic_raw")], transcript: transcript([utt("x", .them, at: 70)])).first)
    #expect(mic.isWarning && mic.name == "Microphone")
}

@Test func otherTrackFailuresAndDeniedPermissionAreWarnings() {
    let tracks = [SessionSummary.Track(id: "system", sampleRate: 48_000, channels: 2, permissionDenied: "audioCapture"),
                  SessionSummary.Track(id: "mic_raw", sampleRate: 16_000, channels: 1, failure: "stalled"),
                  SessionSummary.Track(id: "mic_aec", sampleRate: 16_000, channels: 1)]
    let p = TrackProblem.of(tracks: tracks, transcript: transcript([utt("x", .them), utt("y", .me)]))
    #expect(p.map { $0.trackID } == ["system", "mic_raw"])
    #expect(p.allSatisfy { $0.isWarning })
}
