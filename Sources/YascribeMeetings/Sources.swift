import Foundation

public enum CalendarAuthorization: Sendable { case notDetermined, granted, denied }

public struct CalendarInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Kalendarz tylko do odczytu. Brak dostępu → `events`/`calendars` zwracają `[]`, nic nie rzuca.
public protocol CalendarSource: Sendable {
    func authorization() -> CalendarAuthorization
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    /// `calendarIDs == nil` = wszystkie kalendarze.
    func events(from: Date, to: Date, calendarIDs: [String]?) -> [CalendarEventInfo]
    var changes: AsyncStream<Void> { get }
}

public protocol AudioProcessSource: Sendable {
    /// `nil` = odczyt Core Audio się nie udał (nie to samo co `[]`, czyli nikt nie używa mikrofonu).
    /// Monitor (T10) pomija tik, gdy `nil`, zamiast uznać to za zwolnienie mikrofonu.
    func snapshot() -> [AudioProcessSample]?
}
