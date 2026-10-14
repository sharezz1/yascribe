import Foundation
import MeetNotesTranscription

/// Wyszukiwarka listy spotkań (spec 1.5 §3, decyzja 21): tytuł, My notes, notatka i transkrypt.
public enum SessionSearch {
    public static func matches(_ query: String, title: String, myNotes: String, summary: String?, transcript: Transcript?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(q) || myNotes.localizedCaseInsensitiveContains(q) { return true }
        if summary?.localizedCaseInsensitiveContains(q) == true { return true }
        return transcript?.utterances.contains { $0.text.localizedCaseInsensitiveContains(q) } == true
    }
}
