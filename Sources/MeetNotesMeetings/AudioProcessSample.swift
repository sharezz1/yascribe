import Foundation

/// Proces z listy obiektów Core Audio (adapter w `MeetNotesApp` pomija proces MeetNotes).
public struct AudioProcessSample: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String
    public var isRunningInput: Bool

    public init(pid: Int32, bundleID: String, isRunningInput: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
    }
}
