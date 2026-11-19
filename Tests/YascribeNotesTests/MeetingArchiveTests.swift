import Foundation
import Testing
import YascribeLocalASR
import YascribeProviders
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeNotes

private func archiveSummary(mutes: Bool = false) throws -> SessionSummary {
    var events: [JournalEvent] = [
        .sessionStarted(hostTime: 0, timebase: Timebase(numer: 1, denom: 1), wallClock: Date(timeIntervalSince1970: 1_700_000_000)),
        .trackOpened("mic_raw", hostTime: 0, sampleRate: 16_000, channels: 1, deviceUID: "mic"),
        .trackFirstSample("mic_raw", hostTime: 1_000_000_000),
    ]
    if mutes {
        events.append(.trackMute("mic_raw", muted: true, frameIndex: 80_000, hostTime: 6_000_000_000))
        events.append(.trackMute("mic_raw", muted: false, frameIndex: 192_000, hostTime: 13_000_000_000))
    }
    events.append(.trackClosed("mic_raw", frames: 1_440_000, hostTime: 20_000_000_000))
    return try SessionSummary.rebuild(from: events)
}

private func archiveSpeakers(names: [String: String]? = ["voice": "Anna"]) -> SpeakerDiarization {
    var speakers = SpeakerDiarization(version: 1, modelPin: DiarizerManifest.pin, sensitivity: nil, fa: nil, fb: nil,
                                      threshold: nil, minClusterSeconds: nil, audioFingerprint: nil, createdAt: nil,
                                      segments: [.init(speaker: "voice", start: 0, end: 20)])
    speakers.names = names
    return speakers
}

@Test func archiveTimeUsesHoursMinutesSeconds() {
    #expect(MeetingArchive.time(0) == "0:00:00")
    #expect(MeetingArchive.time(3661.9) == "1:01:01")
    #expect(MeetingArchive.time(-5) == "0:00:00")
}

@Test func archiveDurationTakesTheLongestTrack() throws {
    #expect(MeetingArchive.duration(try archiveSummary()) == 90)
    #expect(MeetingArchive.duration(nil) == nil)
    // Tor bez klatek (system audio nic nie nagrało) nie ciągnie czasu do zera.
    var summary = try archiveSummary()
    summary.tracks.append(SessionSummary.Track(id: "system", sampleRate: 48_000, channels: 2, frames: 0))
    #expect(MeetingArchive.duration(summary) == 90)
}

@Test func archiveSessionsDirectoryFollowsRecordingsPath() {
    let paths = YascribePaths(root: URL(fileURLWithPath: "/tmp/data"))
    #expect(MeetingArchive.sessionsDirectory(paths: paths, settings: GlobalSettings()) == paths.sessions)
    var settings = GlobalSettings()
    settings.recordingsPath = "/tmp/nagrania"
    #expect(MeetingArchive.sessionsDirectory(paths: paths, settings: settings).path == "/tmp/nagrania")
}

@Test func archiveCopyLinesInterleavesMuteNotes() throws {
    let t = transcript([utt("hello", .me, at: 1), utt("later", .me, at: 20)])
    let withMute = MeetingArchive.copyLines(t, summary: try archiveSummary(mutes: true))
    #expect(withMute
            == ["[0:00:01] Me: hello", "[0:00:06] Microphone muted 0:06–0:13", "[0:00:20] Me: later"])
    #expect(MeetingArchive.copyLines(t, summary: nil) == ["[0:00:01] Me: hello", "[0:00:20] Me: later"])
}

@Test func archiveDisplayTranscriptPicksVersionAndLabelsSpeakers() {
    let raw = transcript([utt("raw words", .them, at: 0)])
    let corrected = CorrectedTranscript(transcript: transcript([utt("corrected words", .them, at: 0)]),
                                        model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    let speakers = archiveSpeakers()
    let rules = ReplacementRules(UserDictionary())
    let shown = MeetingArchive.displayTranscript(raw: raw, corrected: corrected, edits: nil, useCorrected: true,
                                                rules: rules, speakers: speakers)
    #expect(shown?.utterances.map(\.text) == ["corrected words"])
    #expect(shown?.utterances.first?.speakerName == "Anna")
    let original = MeetingArchive.displayTranscript(raw: raw, corrected: corrected, edits: nil, useCorrected: false,
                                                   rules: rules, speakers: nil)
    #expect(original?.utterances.map(\.text) == ["raw words"])
    #expect(original?.utterances.first?.speakerName == "Them")
    // Brak poprawionego przy `useCorrected` = surowy, jak w UI.
    #expect(MeetingArchive.displayTranscript(raw: raw, corrected: nil, edits: nil, useCorrected: true, rules: rules, speakers: nil)?
        .utterances.map(\.text) == ["raw words"])
    #expect(MeetingArchive.displayTranscript(raw: nil, corrected: nil, edits: nil, useCorrected: true, rules: rules, speakers: nil) == nil)
}

@Test func archiveSpeakerMarkersResolveOnlyWithTheSameDetection() {
    let speakers = archiveSpeakers()
    var summary = NoteSummary(title: nil, markdown: "[[S1]] mówi", templateID: "t", model: "m", context: "c",
                              generatedAt: Date(timeIntervalSince1970: 0))
    summary.speakers = ["1": "voice"]
    summary.speakersDigest = speakers.segmentsDigest
    let current = MeetingArchive.speakerMarkers(summary: summary, speakers: speakers,
                                                rawTranscript: transcript([utt("cześć", .them, at: 0)]))
    #expect(current.resolved(summary.markdown) == "Anna mówi")
    // Inne wykrycie mówców (inny skrót odcinków): ten sam klucz może znaczyć inną osobę — tylko „Speaker N".
    summary.speakersDigest = "inny"
    let stale = MeetingArchive.speakerMarkers(summary: summary, speakers: speakers,
                                              rawTranscript: transcript([utt("cześć", .them, at: 0)]))
    #expect(stale.resolved(summary.markdown) == "Speaker 1 mówi")
}

@Test func archiveSourceAppliesManualEditsInBothVersionsOnlyWhenIndicesMatch() {
    let raw = transcript([utt("surowy", .them, at: 1), utt("drugi", .me, at: 5)])
    let corrected = CorrectedTranscript(transcript: transcript([utt("poprawiony", .them, at: 1), utt("drugi", .me, at: 5)]),
                                        model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    let edits = TranscriptEdits(edits: [.init(index: 0, speaker: .them, start: 1, text: "ręcznie")])
    #expect(MeetingArchive.source(raw: raw, corrected: corrected, edits: edits, useCorrected: true)?.utterances[0].text == "ręcznie")
    #expect(MeetingArchive.source(raw: raw, corrected: corrected, edits: edits, useCorrected: false)?.utterances[0].text == "ręcznie")
    // Korekta z inną liczbą wypowiedzi: indeksy nie pasują, poprawka pominięta.
    let shorter = CorrectedTranscript(transcript: transcript([utt("poprawiony", .them, at: 1)]), model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    #expect(MeetingArchive.source(raw: raw, corrected: shorter, edits: edits, useCorrected: true)?.utterances[0].text == "poprawiony")
}
