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
    /// Imię z profilu głosu (TASK-117): podobieństwo 0…1; „Not X” odrzuca profil dla tego mówcy.
    var recognized: Double? = nil
    /// TASK-126: inni mówcy spotkania („To ta sama osoba co…”) i grupy złączone w tego mówcę („Rozdziel”).
    var others: [(key: String, label: String)] = []
    var merged: [(key: String, seconds: Double, auto: Bool)] = []
    var merge: (String) -> Void = { _ in }
    var split: (String) -> Void = { _ in }
    let select: (String?) -> Void
    @StateObject private var state = SpeakerPickerState()

    private var options: (attendees: [String], known: [String], typed: String?, canClear: Bool) {
        SpeakerPickerOptions.make(attendees: attendees, known: known, query: state.query, currentName: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who is this?").font(.headline)
            if let recognized, let currentName {
                Label(VoiceProfilesText.recognized(similarity: recognized), systemImage: "waveform")
                    .font(.caption).foregroundStyle(.mnText2)
                Button(String(localized: "Not \(currentName)")) { select(nil) }.buttonStyle(.plain)
            }
            TextField("Type a name", text: $state.query)
                .onSubmit { if let name = options.typed { select(name) } }
            if let name = options.typed { Button("Use \(name)") { select(name) }.buttonStyle(.plain) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !options.attendees.isEmpty { section(String(localized: "In this meeting"), names: options.attendees) }
                    if !options.known.isEmpty { section(String(localized: "Recent"), names: options.known) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 240)
            if !others.isEmpty {
                Divider()
                Menu(String(localized: "Same person as…")) {
                    ForEach(Array(others.enumerated()), id: \.offset) { _, other in Button(other.label) { merge(other.key) } }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if !merged.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Merged into this speaker").font(.caption).foregroundStyle(.mnText2)
                    ForEach(Array(merged.enumerated()), id: \.offset) { _, group in
                        HStack {
                            Text(SpeakerMergeText.group(seconds: group.seconds, auto: group.auto)).font(.caption)
                            Spacer()
                            Button("Split") { split(group.key) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if options.canClear, recognized == nil { Divider(); Button("Use Speaker \(number)") { select(nil) }.buttonStyle(.plain) }
        }
        .padding(14).frame(width: 250, alignment: .leading)
        .foregroundStyle(Color.mnText) // nie dziedziczy koloru mówcy z etykiety
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

enum SpeakerMergeText {
    static func group(seconds: Double, auto: Bool) -> String {
        let n = Int(seconds.rounded())
        return auto ? String(localized: "\(n) s of speech, merged automatically") : String(localized: "\(n) s of speech")
    }
}
