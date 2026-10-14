import Foundation

/// Czy katalog sesji to ten, który właśnie nagrywamy. Porównanie po nazwie katalogu: URL z `contentsOfDirectory`
/// bywa zapisany z ukośnikiem na końcu, a URL zbudowany przez `appendingPathComponent` — bez.
public enum SessionStatus {
    public static func isRecording(_ session: URL, recordingDirectory: URL?) -> Bool {
        guard let recordingDirectory else { return false }
        return session.lastPathComponent == recordingDirectory.lastPathComponent
    }
}
