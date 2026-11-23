import Foundation
import YascribeProviders
import YascribeSessionFormat
import YascribeTranscription

/// Odczyt archiwum spotkań wspólny dla aplikacji i serwera MCP (TASK-31): katalog sesji, czas, mówcy,
/// wybór wersji transkryptu i linie transkryptu. Czyste funkcje — aplikacja woła je zamiast własnych kopii,
/// więc MCP widzi dokładnie to samo, co UI.
public enum MeetingArchive {
    /// Katalog spotkań: `recordingsPath` z ustawień albo domyślny `sessions` w katalogu danych.
    public static func sessionsDirectory(paths: YascribePaths, settings: GlobalSettings) -> URL {
        settings.recordingsPath.map { URL(fileURLWithPath: $0) } ?? paths.sessions
    }

    /// Spotkanie to katalog z dziennikiem nagrania; inne wpisy (np. `.DS_Store`) są pomijane.
    public static func isSession(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: SessionDirectory(url: url).journalURL.path)
    }

    /// Najdłuższy tor: gdy dźwięk systemowy nic nie nagrał (0 klatek), czas liczy się z mikrofonu, nie „0 min".
    public static func duration(_ summary: SessionSummary?) -> Double? {
        summary?.tracks.compactMap { t in t.frames.flatMap { f in t.sampleRate > 0 ? Double(f) / t.sampleRate : nil } }.max()
    }

    /// Znaczniki `[[SN]]` notatki → bieżące nazwy mówców.
    /// shortcut: numeracja z surowego transkryptu, także gdy notatka powstała z poprawionego; zmienić, jeśli „Speaker N" w notatce
    /// rozjedzie się z transkryptem.
    /// Inne wykrycie mówców niż przy generowaniu (skrót odcinków): te same klucze mogą znaczyć inne osoby, więc bez numeracji
    /// — znaczniki zostają samym „Speaker N" z notatki.
    public static func speakerMarkers(summary: NoteSummary?, speakers: SpeakerDiarization?,
                                      rawTranscript: Transcript?) -> SpeakerMarkers {
        let current = speakers.map(\.segmentsDigest)
        let sameDetection = current != nil && summary?.speakersDigest == current
        return SpeakerMarkers(keys: summary?.speakers, names: speakers?.names ?? [:],
                              numbers: sameDetection ? rawTranscript.map { SpeakerLabels.numbers(for: $0.withSpeakerLabels(speakers)) } ?? [:] : [:])
    }

    /// Wersja przed Replacement: poprawiona, gdy jest i użytkownik jej nie wyłączył; ręczne poprawki (`edits.json`,
    /// TASK-109) w obu wersjach. Korekta z inną liczbą wypowiedzi niż surowy (Retry Failed Parts po korekcie): indeksy
    /// nie pasują, więc bez poprawek. Ukrycia (TASK-119) idą za mówcą i początkiem, więc obowiązują zawsze; domyślnie ukryte
    /// wypowiedzi są wycięte — tylko widok transkryptu (indeksy ▶/✎, „Show deleted”) prosi o `includeHidden`.
    public static func source(raw: Transcript?, corrected: CorrectedTranscript?, edits: TranscriptEdits?,
                              useCorrected: Bool, includeHidden: Bool = false) -> Transcript? {
        guard var base = useCorrected ? (corrected?.transcript ?? raw) : raw else { return nil }
        guard let edits else { return base }
        if base.utterances.count == raw?.utterances.count { base = edits.apply(to: base) }
        base = edits.markingHidden(base)
        return includeHidden ? base : base.withoutHidden()
    }

    /// Podstawa odcisków Overview (TASK-119): surowy i poprawiony bez ukrytych wypowiedzi. Bez ukryć = te same transkrypty co
    /// dotąd (stare odciski zostają ważne); ukrycie albo przywrócenie zmienia odcisk, więc Overview z ukrytym tekstem nie jest aktualne.
    public static func overviewBasis(raw: Transcript?, corrected: Transcript?, edits: TranscriptEdits?) -> (raw: Transcript?, corrected: Transcript?) {
        guard let edits else { return (raw, corrected) }
        return (raw.map { edits.markingHidden($0).withoutHidden() }, corrected.map { edits.markingHidden($0).withoutHidden() })
    }

    /// Transkrypt do wyświetlenia: `source`, potem Replacement i etykiety mówców.
    public static func displayTranscript(raw: Transcript?, corrected: CorrectedTranscript?, edits: TranscriptEdits?,
                                         useCorrected: Bool, rules: ReplacementRules,
                                         speakers: SpeakerDiarization?, includeHidden: Bool = false) -> Transcript? {
        source(raw: raw, corrected: corrected, edits: edits, useCorrected: useCorrected, includeHidden: includeHidden)
            .map { Replacement.apply($0, rules: rules).withSpeakerLabels(speakers) }
    }

    /// `[H:MM:SS]` — ten sam zapis w transkrypcie, kopii i eksporcie MCP.
    public static func time(_ s: Double) -> String {
        let i = Int(max(0, s))
        return String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60)
    }

    /// Linia transkryptu: wypowiedź (z indeksem w `utterances` — klucz poprawek i odtwarzania) albo linia wyciszenia toru.
    public enum Line: Equatable, Sendable {
        case utterance(Int, Utterance)
        case mute(MuteNote)
    }

    /// Wypowiedzi z liniami wyciszenia („Microphone muted 0:05–0:12", macos.md §11.5) w kolejności czasu.
    public static func lines(_ t: Transcript, summary: SessionSummary?) -> [Line] {
        var mutes = MuteNote.of(summary: summary)[...]
        var out: [Line] = []
        for (i, u) in t.utterances.enumerated() {
            while let m = mutes.first, m.start <= u.start { out.append(.mute(m)); mutes = mutes.dropFirst() }
            out.append(.utterance(i, u))
        }
        return out + mutes.map(Line.mute)
    }

    /// Jedna linia „Copy": `[H:MM:SS] Name: text`.
    public static func copyLine(_ u: Utterance) -> String {
        "[\(time(u.start))] \(u.speakerName): \(u.text)"
    }

    /// Cały transkrypt jak z przycisku „Copy" w UI — te same linie, także linie wyciszenia.
    public static func copyLines(_ t: Transcript, summary: SessionSummary?) -> [String] {
        lines(t, summary: summary).map { line in
            switch line {
            case .utterance(_, let u): copyLine(u)
            case .mute(let m): "[\(time(m.start))] \(m.line)"
            }
        }
    }
}

public extension Utterance {
    /// Nazwa mówcy w transkrypcie i kopii; bez diaryzacji „Me" / „Them".
    var speakerName: String { speaker == .me ? "Me" : speakerLabel ?? "Them" }
}
