import Foundation

/// Co zmiana imienia mówcy znaczy dla profili głosów (TASK-117). Czyste: zapis plików i nauka należą do wołającego.
public enum VoiceNaming {
    public struct Outcome: Equatable, Sendable {
        public var diarization: SpeakerDiarization
        /// Dopisać próbkę tego mówcy do profilu o nowym imieniu (imię nadane albo potwierdzone przez użytkownika).
        public var learn: Bool
        /// Usunąć wcześniejszą próbkę tego mówcy (poprzednie ręczne imię było pomyłką).
        public var forgetPrevious: Bool
    }

    /// `nil` = brak takiego mówcy. Imię z dopasowania zmienione albo zdjęte = odrzucenie profilu dla tego mówcy;
    /// to samo imię = potwierdzenie (od teraz imię ręczne).
    public static func rename(_ d: SpeakerDiarization, key: String, to name: String?) -> Outcome? {
        guard var result = d.renamed(key, to: name) else { return nil }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let new = trimmed.isEmpty ? nil : trimmed
        let previous = d.names?[key]
        let same = new != nil && previous.map { $0.caseInsensitiveCompare(new!) == .orderedSame } == true
        if let match = d.voiceMatches?[key] {
            result.voiceMatches?[key] = nil
            if result.voiceMatches?.isEmpty == true { result.voiceMatches = nil }
            if !same {
                var rejected = result.voiceRejected ?? [:]
                if !(rejected[key] ?? []).contains(match.profileID) { rejected[key, default: []].append(match.profileID) }
                result.voiceRejected = rejected
            }
            return Outcome(diarization: result, learn: new != nil, forgetPrevious: false)
        }
        return Outcome(diarization: result, learn: new != nil, forgetPrevious: previous != nil && !same)
    }
}
