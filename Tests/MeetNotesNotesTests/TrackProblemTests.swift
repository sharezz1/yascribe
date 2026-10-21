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

@Test func journaledSoundAfterSilenceIsInformationWithoutATranscript() throws {
    // 1.5b: `track.audible` rozstrzyga od razu — bez czekania na transkrypt (decyzja (b) z F15-T13 część B).
    var t = silentStart()
    t.audibleFrame = 64 * 48_000
    let p = try #require(TrackProblem.of(tracks: [t], transcript: nil).first)
    #expect(!p.isWarning)
    #expect(p.line == "System audio was silent for the first minute; recording continued.")
    #expect(p.detail.contains("1:04"))
}

@Test func mutePeriodsBecomeTranscriptLinesOnTheSessionAxis() throws {
    let ns = Timebase(numer: 1, denom: 1)
    let sum = try SessionSummary.rebuild(from: [
        .sessionStarted(hostTime: 0, timebase: ns, wallClock: Date(timeIntervalSince1970: 0)),
        .trackOpened("system", hostTime: 0, sampleRate: 48_000, channels: 2, deviceUID: "spk"),
        .trackOpened("mic_raw", hostTime: 0, sampleRate: 16_000, channels: 1, deviceUID: "mic"),
        .trackFirstSample("system", hostTime: 1_000_000_000),
        .trackFirstSample("mic_raw", hostTime: 1_000_000_000),
        .trackMute("system", muted: true, frameIndex: 480_000, hostTime: 11_000_000_000), // do końca (awaria)
        .trackMute("mic_raw", muted: true, frameIndex: 80_000, hostTime: 6_000_000_000),
        .trackMute("mic_raw", muted: false, frameIndex: 192_000, hostTime: 13_000_000_000),
    ])
    #expect(MuteNote.of(summary: sum).map(\.line) == ["Microphone muted 0:05–0:12", "System audio muted from 0:10 to the end"])
    #expect(MuteNote.of(summary: sum).map(\.start) == [5, 10])
    #expect(MuteNote.of(summary: nil).isEmpty)
}

@Test func mutesBeforeTheSessionAxisStartAreSkippedOrClippedToZero() throws {
    // Odbiór 2026-10-19: dźwięk systemowy ruszył 28 s po mikrofonie, a dwa wyciszenia wypadły przed zerem osi
    // („Microphone muted 0:00–0:00”, czas „0:00:-13”).
    let ns = Timebase(numer: 1, denom: 1)
    let sum = try SessionSummary.rebuild(from: [
        .sessionStarted(hostTime: 0, timebase: ns, wallClock: Date(timeIntervalSince1970: 0)),
        .trackOpened("system", hostTime: 0, sampleRate: 48_000, channels: 2, deviceUID: "spk"),
        .trackOpened("mic_raw", hostTime: 0, sampleRate: 16_000, channels: 1, deviceUID: "mic"),
        .trackFirstSample("mic_raw", hostTime: 1_000_000_000),
        .trackFirstSample("system", hostTime: 29_000_000_000), // oś: 0 = 28 s toru mikrofonu
        .trackMute("mic_raw", muted: true, frameIndex: 16_000 * 15, hostTime: 16_000_000_000),
        .trackMute("mic_raw", muted: false, frameIndex: 16_000 * 17, hostTime: 18_000_000_000),
        .trackMute("mic_raw", muted: true, frameIndex: 16_000 * 20, hostTime: 21_000_000_000),
        .trackMute("mic_raw", muted: false, frameIndex: 16_000 * 40, hostTime: 41_000_000_000),
    ])
    let notes = MuteNote.of(summary: sum)
    #expect(notes.map(\.line) == ["Microphone muted 0:00–0:12"])
    #expect(notes.map(\.start) == [0])
}

@Test func systemTrackThatNeverStartedWhileTheMicRecordedIsInformation() throws {
    // Dyktowanie do mikrofonu: nic nie grało w głośnikach, tor systemowy `stalled30s` z 0 klatek, mikrofon nagrał 2,7 min.
    let system = SessionSummary.Track(id: "system", sampleRate: 48_000, channels: 2, frames: 0, failure: "stalled30s")
    let mic = SessionSummary.Track(id: "mic_raw", sampleRate: 16_000, channels: 1, frames: 2_130_432)
    let p = try #require(TrackProblem.of(tracks: [system, mic], transcript: nil).first)
    #expect(!p.isWarning && p.line == "System audio captured nothing.")
    // Bez dźwięku na innym torze — nadal ostrzeżenie; stall po nagraniu klatek — też; odmowa uprawnienia — też.
    #expect(try #require(TrackProblem.of(tracks: [system], transcript: nil).first).isWarning)
    var late = system; late.frames = 480_000
    #expect(try #require(TrackProblem.of(tracks: [late, mic], transcript: nil).first).isWarning)
    var denied = system; denied.permissionDenied = "audioCapture"
    #expect(try #require(TrackProblem.of(tracks: [denied, mic], transcript: nil).first).isWarning)
}
