import MeetNotesMeetings
import MeetNotesNotes
import SwiftUI

/// Stan okna „Select calendar event" (spec §4.7): otwarcie wczytuje listę z kalendarza.
final class EventPickerState: ObservableObject {
    @Published var open = false
    @Published var ready = false
    @Published var rows: [Ranked] = []
}

/// Chip w nagłówku notatki: tytuł powiązanego wydarzenia albo „Link event"; klik otwiera okno wyboru.
struct EventPickerChip: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    @StateObject private var state = EventPickerState()

    var body: some View {
        let linked = item.notes.meta.calendarEvent
        Button {
            state.ready = model.calendarReady
            state.rows = model.pickableEvents(for: item)
            state.open = true
        } label: {
            Label(linked?.title ?? "Link event", systemImage: "calendar")
                .font(.callout).foregroundStyle(.mnText2).lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("Select calendar event")
        .accessibilityLabel(linked.map { "Calendar event: \($0.title). Change" } ?? "Link a calendar event")
        .popover(isPresented: $state.open, arrowEdge: .bottom) {
            EventPickerContent(state: state, item: item,
                               onPick: { model.link($0, to: item); state.open = false },
                               onUnlink: { model.unlink(item); state.open = false },
                               onSettings: { model.section = .settings; state.open = false })
        }
    }
}

struct EventPickerContent: View {
    @ObservedObject var state: EventPickerState
    let item: SessionItem
    let onPick: (CalendarEventInfo) -> Void
    let onUnlink: () -> Void
    let onSettings: () -> Void

    private var linked: CalendarLink? { item.notes.meta.calendarEvent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select calendar event").font(.system(size: 13, weight: .semibold))
            Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.mnText2)
                .padding(.top, 2).padding(.bottom, 10)
            Divider()
            if !state.ready {
                row("Connect Apple Calendar in Settings", icon: "calendar.badge.plus", action: onSettings)
            } else if state.rows.isEmpty {
                Text("No events found that day").font(.callout).foregroundStyle(.mnText2).padding(.vertical, 10)
            } else {
                ScrollView { VStack(alignment: .leading, spacing: 0) { ForEach(state.rows, id: \.event.id) { eventRow($0) } } }
                    .frame(maxHeight: 280)
            }
            if linked != nil { Divider(); row("Unlink", icon: "xmark", action: onUnlink) }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private func isLinked(_ e: CalendarEventInfo) -> Bool { linked.map { $0.title == e.title && $0.start == e.start } ?? false }

    private func eventRow(_ r: Ranked) -> some View {
        Button { onPick(r.event) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).frame(width: 14)
                    .opacity(isLinked(r.event) ? 1 : 0).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.event.title).font(.system(size: 13)).foregroundStyle(.mnText).lineLimit(2)
                    Text("\(r.event.start.formatted(date: .omitted, time: .shortened)) – \(r.event.end.formatted(date: .omitted, time: .shortened))")
                        .font(.callout).monospacedDigit().foregroundStyle(.mnText2)
                    if r.overlapsRecording { Label("During the recording", systemImage: "waveform").font(.callout).foregroundStyle(.mnAccent) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(r.event.title), \(r.event.start.formatted(date: .omitted, time: .shortened))\(r.overlapsRecording ? ", during the recording" : "")\(isLinked(r.event) ? ", linked" : "")")
    }

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 13)).foregroundStyle(.mnText)
                .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Uczestnicy z migawki powiązanego wydarzenia (tylko wyświetlanie): „With Anna, Ben +2".
struct EventAttendeesLine: View {
    let link: CalendarLink?
    var body: some View {
        let names = (link?.attendees ?? []).compactMap { $0.name ?? $0.email }
        if !names.isEmpty {
            Text("With " + names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : ""))
                .font(.callout).foregroundStyle(.mnText2).lineLimit(1)
        }
    }
}
