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

// TASK-119: `source` domyślnie wycina ukryte (każdy konsument poza widokiem), `includeHidden` zostawia je oznaczone.
@Test func archiveSourceDropsHiddenByDefaultInBothVersions() {
    let raw = transcript([utt("tlo", .me, at: 1), utt("drugi", .them, at: 5)])
    let corrected = CorrectedTranscript(transcript: transcript([utt("Tło.", .me, at: 1), utt("Drugi.", .them, at: 5), utt("nowy", .them, at: 7)]),
                                        model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    let edits = TranscriptEdits(hidden: [.init(speaker: .me, start: 1)])
    for useCorrected in [true, false] {
        let shown = MeetingArchive.source(raw: raw, corrected: corrected, edits: edits, useCorrected: useCorrected)
        #expect(shown?.utterances.contains { $0.speaker == .me } == false)
        let full = MeetingArchive.source(raw: raw, corrected: corrected, edits: edits, useCorrected: useCorrected, includeHidden: true)
        #expect(full?.utterances.first?.hidden == true)
        #expect(full?.utterances.count == (useCorrected ? 3 : 2))
        let display = MeetingArchive.displayTranscript(raw: raw, corrected: corrected, edits: edits, useCorrected: useCorrected,
                                                       rules: ReplacementRules(UserDictionary()), speakers: nil)
        #expect(display.map { MeetingArchive.copyLines($0, summary: nil) }?.contains { $0.lowercased().contains("tł") || $0.contains("tlo") } == false)
    }
}

@Test func noteMarkersSurviveMerge() {
    var speakers = archiveSpeakers()
    speakers.segments.append(.init(speaker: "dup", start: 20, end: 30))
    var summary = NoteSummary(title: nil, markdown: "[[S1]] i [[S2]]", templateID: "t", model: "m", context: "c",
                              generatedAt: Date(timeIntervalSince1970: 0))
    summary.speakers = ["1": "voice", "2": "dup"]
    summary.speakersDigest = speakers.segmentsDigest
    let merged = speakers.merging(["dup": "voice"], auto: false)
    #expect(merged.segmentsDigest == speakers.segmentsDigest)
    let markers = MeetingArchive.speakerMarkers(summary: summary, speakers: merged,
                                                rawTranscript: transcript([utt("cześć", .them, at: 0), utt("tak", .them, at: 25)]))
    #expect(markers.resolved(summary.markdown) == "Anna i Anna")
}

// TASK-127: wypowiedź na granicy dwóch mówców — części idą za źródłem w poprawkach, ukryciach i korekcie.
private func twoSpeakerRaw() -> Transcript {
    let words = [("alfa", 143.08, 144.5), ("beta", 144.6, 146.0), ("gamma", 146.1, 147.5), ("delta.", 147.6, 148.66),
                 ("Epsilon", 149.58, 151.0), ("zeta", 151.1, 155.0), ("eta", 155.1, 159.0), ("theta.", 159.1, 163.0)]
        .map { Word(text: $0.0, start: $0.1, end: $0.2) }
    let me = Utterance(speaker: .me, start: 100, end: 101, text: "jeden dwa", words: [], approximateTiming: true, languageMismatch: nil)
    let them = Utterance(speaker: .them, start: 143.08, end: 163, text: words.map(\.text).joined(separator: " "), words: words,
                         approximateTiming: false, languageMismatch: nil)
    return Transcript(utterances: [me, them], failedChunks: [])
}
private func twoSpeakerDiarization() -> SpeakerDiarization {
    var d = SpeakerDiarization(version: 1, modelPin: "p", sensitivity: nil, fa: nil, fb: nil, threshold: nil, minClusterSeconds: nil,
                       audioFingerprint: nil, createdAt: nil,
                       segments: [.init(speaker: "A", start: 133.28, end: 149.13), .init(speaker: "B", start: 149.80, end: 162.84)])
    d.names = ["B": "Ola"]
    return d
}
private func twoSpeakerShown(_ raw: Transcript, corrected: CorrectedTranscript? = nil, edits: TranscriptEdits?,
                             useCorrected: Bool = false, includeHidden: Bool = false) -> Transcript? {
    MeetingArchive.displayTranscript(raw: raw, corrected: corrected, edits: edits, useCorrected: useCorrected,
                                     rules: ReplacementRules(UserDictionary()), speakers: twoSpeakerDiarization(),
                                     includeHidden: includeHidden)
}

@Test func splitUtteranceShowsTwoSpeakersInArchive() {
    let shown = twoSpeakerShown(twoSpeakerRaw(), edits: nil)
    #expect(shown?.utterances.map(\.speakerName) == ["Me", "Speaker 1", "Ola"])
    #expect(shown?.utterances.map(\.text) == ["jeden dwa", "alfa beta gamma delta.", "Epsilon zeta eta theta."])
}

@Test func hidingSecondPartHidesWholeSourceUtterance() throws {
    let raw = twoSpeakerRaw()
    let second = try #require(twoSpeakerShown(raw, edits: nil)?.utterances[2])
    let key = TranscriptEdits.Hidden(second)
    #expect(key == TranscriptEdits.Hidden(speaker: .them, start: 143.08))
    let edits = TranscriptEdits().settingHidden([key], true)
    #expect(twoSpeakerShown(raw, edits: edits, includeHidden: true)?.utterances.map(\.hidden) == [nil, true, true])
    #expect(twoSpeakerShown(raw, edits: edits)?.utterances.map(\.text) == ["jeden dwa"])
}

@Test func editOfSourceAppearsInBothParts() {
    let raw = twoSpeakerRaw()
    let edits = TranscriptEdits().setting("Alfa beta gamma delta. Epsilon zeta, eta theta.", at: 1, of: raw.utterances[1],
                                          original: raw.utterances[1].text)
    let shown = twoSpeakerShown(raw, edits: edits)
    #expect(shown?.utterances.map(\.text) == ["jeden dwa", "Alfa beta gamma delta.", "Epsilon zeta, eta theta."])
    #expect(shown?.utterances.map { $0.part?.index } == [nil, 1, 1])
    #expect(shown?.utterances.map { $0.part?.text } == [nil, edits.edits[0].text, edits.edits[0].text])
}

@Test func correctedTextSplitsAtSameBoundary() {
    let raw = twoSpeakerRaw()
    var fixed = raw
    fixed.utterances[1].text = "Alfa, gamma delta. Epsilon i zeta eta theta."
    let corrected = CorrectedTranscript(transcript: fixed, model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    let shown = twoSpeakerShown(raw, corrected: corrected, edits: nil, useCorrected: true)
    #expect(shown?.utterances.map(\.text) == ["jeden dwa", "Alfa, gamma delta.", "Epsilon i zeta eta theta."])
    #expect(shown?.utterances.map(\.speakerName) == ["Me", "Speaker 1", "Ola"])
}
