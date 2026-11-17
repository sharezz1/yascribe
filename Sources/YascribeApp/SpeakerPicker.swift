import SwiftUI
import YascribeMeetings

struct SpeakerPickerOptions {
    static func make(attendees: [CalendarLink.Attendee], known: [String], query: String, currentName: String?) -> (attendees: [String], known: [String], typed: String?, canClear: Bool) {
        let meeting = attendees.compactMap { attendee -> String? in
            let value = (attendee.name ?? attendee.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let recent = known.filter { name in !meeting.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches: (String) -> Bool = { trimmed.isEmpty || $0.localizedCaseInsensitiveContains(trimmed) }
        let typed = !trimmed.isEmpty && !(meeting + recent).contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ? trimmed : nil
        return (meeting.filter(matches), recent.filter(matches), typed, currentName != nil)
    }
}

struct SpeakerPicker: View {
    let attendees: [CalendarLink.Attendee]
    let known: [String]
    let currentName: String?
    let number: Int
    let select: (String?) -> Void
    @StateObject private var state = SpeakerPickerState()

    private var options: (attendees: [String], known: [String], typed: String?, canClear: Bool) {
        SpeakerPickerOptions.make(attendees: attendees, known: known, query: state.query, currentName: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who is this?").font(.headline)
            TextField("Type a name", text: $state.query)
                .onSubmit { if let name = options.typed { select(name) } }
            if let name = options.typed { Button("Use \(name)") { select(name) }.buttonStyle(.plain) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !options.attendees.isEmpty { section("In this meeting", names: options.attendees) }
                    if !options.known.isEmpty { section("Recent", names: options.known) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 240)
            if options.canClear { Divider(); Button("Use Speaker \(number)") { select(nil) }.buttonStyle(.plain) }
        }
        .padding(14).frame(width: 250, alignment: .leading)
    }

    private func section(_ title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.mnText2)
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Button(name) { select(name) }.buttonStyle(.plain)
            }
        }
    }
}

private final class SpeakerPickerState: ObservableObject { @Published var query = "" }
