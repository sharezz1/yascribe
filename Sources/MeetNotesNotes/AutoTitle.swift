import Foundation
import MeetNotesProviders
import MeetNotesTranscription

/// Autotytuł po transkrypcji (spec 1.5 §3, decyzja 18): jedno krótkie wywołanie modelu podsumowania, tylko po tytuł.
/// Zapis do `meta.json.autoTitle` wyłącznie gdy nie ma ręcznego, wcześniejszego automatycznego ani powiązanego wydarzenia. Błąd = cicho
/// „Untitled meeting".
public enum AutoTitle {
    public static let maxLength = 80
    /// Trzy próbki po ~2000 znaków: początek, środek i koniec transkryptu (decyzja użytkownika 2026-10-14).
    public static let sampleChars = 2_000

    public static func shouldRun(meta: NoteMeta) -> Bool { meta.manualTitle == nil && meta.autoTitle == nil && meta.calendarEvent == nil }

    /// `nil`, gdy nie ma czego nazywać (pusta albo w całości wykluczona transkrypcja).
    public static func prompt(transcript: Transcript, notesLanguage: LanguageCode?) -> NotePrompt? {
        let lines = NotePromptBuilder.transcriptLines(transcript)
        guard !lines.isEmpty else { return nil }
        let text = sample(lines)
        let language = notesLanguage.map { "in \($0.englishName)" } ?? "in the language that predominates in the transcript"
        let system = "You name meetings. Reply with ONE line: a short descriptive title \(language), at most 8 words, no quotes, "
            + "no trailing period. \(NoteTitle.rule) If the transcript is too fragmented to name, reply with exactly: \(NoteTitle.untitled)"
        return NotePrompt(system: system, user: text)
    }

    /// Krótki transkrypt (do 3 × `sampleChars`) idzie w całości; dłuższy — trzy okna: początek, środek, koniec,
    /// rozdzielone linią „[…]". Wiersz należy do okna, jeśli zaczyna się w jego zakresie znaków.
    static func sample(_ lines: [String]) -> String {
        let total = lines.reduce(0) { $0 + $1.count + 1 }
        guard total > sampleChars * 3 else { return lines.joined(separator: "\n") }
        var starts: [Int] = []
        var acc = 0
        for l in lines { starts.append(acc); acc += l.count + 1 }
        let windows: [Range<Int>] = [0..<sampleChars,
                                     (total / 2 - sampleChars / 2)..<(total / 2 + sampleChars / 2),
                                     (total - sampleChars)..<total]
        let parts = windows.map { w in lines.indices.filter { w.contains(starts[$0]) }.map { lines[$0] }.joined(separator: "\n") }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n[…]\n")
    }

    /// Pierwsza niepusta linia odpowiedzi, bez `#`, cudzysłowów, gwiazdek i kropki; do 80 znaków.
    public static func clean(_ reply: String) -> String? {
        guard let first = reply.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }
        var t = first
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "*\"“”'. ").union(.whitespaces))
        t = NoteTitle.stripLabel(t)
        if t.isEmpty || t == NoteTitle.untitled { return nil }
        return String(t.prefix(maxLength))
    }

    /// Zwraca zapisany tytuł albo `nil` (nie trzeba / nie ma czego nazywać / model zawiódł / przebieg przestał być bieżący).
    /// `stillCurrent`: sprawdzane tuż przed zapisem — w czasie wywołania modelu nowszy przebieg mógł zostać bieżącym (R23).
    public static func generate(client: OpenAICompatibleClient, model: String, transcript: Transcript,
                                notesLanguage: LanguageCode?, store: NotesStore,
                                timeout: Double = 60, chatTimeout: Double = 120, maxTokens: Int? = nil,
                                stillCurrent: @Sendable () -> Bool = { true },
                                onProblem: @Sendable (String) -> Void = { _ in }) async -> String? {
        guard shouldRun(meta: store.readMeta()), let p = prompt(transcript: transcript, notesLanguage: notesLanguage),
              let reply = try? await withDeadline(timeout, {
                  try await client.chat(model: model, system: p.system, user: p.user, timeout: chatTimeout, maxTokens: maxTokens)
              }),
              let title = clean(reply), stillCurrent() else { return nil }
        var stored = false
        do {
            // Ponowne sprawdzenie pod zapisem: w międzyczasie użytkownik mógł wpisać własny tytuł.
            if let problem = try store.updateMeta({ m in
                if m.manualTitle == nil && m.autoTitle == nil && m.calendarEvent == nil { m.autoTitle = title; stored = true }
            }) { onProblem(problem) }
        } catch {
            onProblem("Couldn't save the meeting title: \(error)")
        }
        return stored ? title : nil
    }
}
