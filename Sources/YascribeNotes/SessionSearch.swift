import Foundation
import YascribeTranscription

/// Wyszukiwarka listy spotkań (spec 1.5 §3, decyzja 21): tytuł, My notes, notatka i transkrypt.
/// Transkrypt jako `@autoclosure` (F21): odczyt przechodzi przez Replacement, więc liczymy go dopiero wtedy, gdy zapytanie
/// nie jest puste, a tytuł, My notes i notatka nie pasują.
public enum SessionSearch {
    public static func matches(_ query: String, title: String, myNotes: String, summary: String?,
                               transcript: @autoclosure () -> Transcript?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(q) || myNotes.localizedCaseInsensitiveContains(q) { return true }
        if summary?.localizedCaseInsensitiveContains(q) == true { return true }
        return transcript()?.utterances.contains { $0.text.localizedCaseInsensitiveContains(q) } == true
    }
}
