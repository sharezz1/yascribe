import Foundation

/// „Open note” w pigułce (drugi odbiór 2026-10-16, macos.md §11.5): dokąd przejść w oknie głównym.
public struct OpenNoteDestination: Equatable, Sendable {
    public enum Section: Equatable, Sendable { case meetings }
    public enum Tab: Equatable, Sendable { case myNotes }
    public var section: Section
    /// `nil` = sama lista spotkań (nagranie już się skończyło, nie ma czego otwierać).
    public var sessionID: String?
    public var tab: Tab?

    /// Nagrywane spotkanie: Meetings → ta sesja (nazwa katalogu, jak `SessionItem.id`) → My notes.
    public static func forRecording(directory: URL?) -> OpenNoteDestination {
        guard let directory else { return OpenNoteDestination(section: .meetings, sessionID: nil, tab: nil) }
        return OpenNoteDestination(section: .meetings, sessionID: directory.lastPathComponent, tab: .myNotes)
    }
}
