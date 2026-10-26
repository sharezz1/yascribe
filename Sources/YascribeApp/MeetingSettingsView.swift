import YascribeMeetings
import YascribeProviders
import ServiceManagement
import SwiftUI

// Settings: Integrations i Meeting detection (faza 1.6, T7). Zapis od razu, jak w `RecordingsSection` (bez Save/Cancel).

extension AppModel {
    /// Wołane tylko z przełącznika w Settings. Odmowa → instrukcja w `lastError`; TCC zmienia wyłącznie użytkownik.
    func connectAppleCalendar() async {
        if await calendarSource.requestAccess() {
            updateMeetings { $0.appleCalendarEnabled = true }
        } else {
            lastError = "Allow calendar access in System Settings → Privacy & Security → Calendars."
        }
    }

    /// Wołane tylko z przełącznika w Settings (rejestracja zmienia pozycje logowania w systemie).
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            updateMeetings { $0.launchAtLogin = on }
        } catch {
            lastError = "Couldn't \(on ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
    }

    func updateMeetings(_ change: (inout MeetingSettings) -> Void) {
        let old = settings.meetings ?? MeetingSettings()
        var m = old
        change(&m)
        guard m != old else { return }  // `load()` pól tekstowych odpala onChange — bez zapisu, gdy nic się nie zmieniło
        settings.meetings = m
        save()
    }
}

/// Stan lokalny sekcji: lista kalendarzy i autoryzacja (odświeżane z `CalendarSource`) oraz pola „Advanced" jako tekst.
final class MeetingSettingsState: ObservableObject {
    @Published var authorization: CalendarAuthorization = .notDetermined
    @Published var calendars: [CalendarInfo] = []
    @Published var advancedOpen = false
    @Published var startText = ""
    @Published var releaseText = ""
    @Published var silenceText = ""
    @Published var ignoredText = ""

    func refresh(_ source: any CalendarSource) {
        authorization = source.authorization()
        calendars = source.calendars()
    }

    func load(_ m: MeetingSettings?) {
        func fmt(_ v: Double?) -> String { v.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "" }
        startText = fmt(m?.startSeconds); releaseText = fmt(m?.releaseSeconds); silenceText = fmt(m?.silenceSeconds)
        ignoredText = (m?.ignoredApps ?? []).joined(separator: ", ")
    }
}

struct MeetingSettingsSections: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: MeetingSettingsState
    /// Migawki podają gotowy stan; zwykłe użycie odświeża go z `model.calendarSource`.
    private let live: Bool

    init(state: MeetingSettingsState? = nil) {
        _state = StateObject(wrappedValue: state ?? MeetingSettingsState())
        live = state == nil
    }

    private var m: MeetingSettings { model.settings.meetings ?? MeetingSettings() }
    private static let defaults = MeetingTuning()

    var body: some View {
        SectionHeader("Integrations")
        Card {
            appleCalendar
            ForEach(["Google Calendar", "Outlook", "Slack"], id: \.self) { name in
                RowDivider()
                FormRow(label: name) {
                    HStack(spacing: 10) {
                        Toggle(name, isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
                        Text("Coming soon").foregroundStyle(.mnText2)
                    }
                }
                .disabled(true).opacity(0.55)
            }
        }
        SectionHeader("Meeting detection")
        Card {
            FormRow(label: "Detect calls") { toggle("Detect calls", Binding(get: { m.detectCallsOrDefault }, set: { v in model.updateMeetings { $0.detectCalls = v } })) }
            RowDivider()
            FormRow(label: "Start recording automatically", caption: "Starts only for calls in Teams, never for a calendar event alone.") {
                toggle("Start recording automatically", Binding(get: { m.autoStartOrDefault }, set: { v in model.updateMeetings { $0.autoStart = v } }))
            }
            RowDivider()
            FormRow(label: "Launch at login", caption: "Without it, detection starts when you open Yascribe.") {
                toggle("Launch at login", Binding(get: { m.launchAtLoginOrDefault }, set: { model.setLaunchAtLogin($0) }))
            }
            RowDivider()
            DisclosureGroup("Advanced", isExpanded: $state.advancedOpen) {
                VStack(spacing: 0) {
                    advancedRow("Start after", unit: "s", placeholder: Self.defaults.startSeconds, text: $state.startText) { v in model.updateMeetings { $0.startSeconds = v } }
                    advancedRow("Release after", unit: "s", placeholder: Self.defaults.releaseSeconds, text: $state.releaseText) { v in model.updateMeetings { $0.releaseSeconds = v } }
                    advancedRow("Silence after", unit: "s", placeholder: Self.defaults.silenceSeconds, text: $state.silenceText) { v in model.updateMeetings { $0.silenceSeconds = v } }
                    FormRow(label: "Ignored apps", caption: "Bundle IDs, comma-separated. Empty uses the defaults.") {
                        TextField(Self.defaults.ignoredApps.joined(separator: ", "), text: $state.ignoredText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: state.ignoredText) {
                                let apps = state.ignoredText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                model.updateMeetings { $0.ignoredApps = apps.isEmpty ? nil : apps }
                            }
                    }
                }
                .padding(.top, 6).padding(.leading, -16)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .task {
            guard live else { return }
            state.load(model.settings.meetings)
            state.refresh(model.calendarSource)
        }
    }

    // MARK: Apple Calendar

    private var calendarStatus: StateLabel {
        switch state.authorization {
        case .granted where m.appleCalendarOrDefault: StateLabel(.ok, "Connected")
        case .denied: StateLabel(.bad, "Access denied")
        default: StateLabel(.neutral, "Not connected")
        }
    }

    @ViewBuilder private var appleCalendar: some View {
        FormRow(label: "Apple Calendar",
                caption: state.authorization == .denied ? "Allow access in System Settings → Privacy & Security → Calendars." : nil,
                isError: state.authorization == .denied) {
            HStack(spacing: 10) {
                toggle("Connect Apple Calendar", Binding(
                    get: { m.appleCalendarOrDefault && state.authorization == .granted },
                    set: { on in
                        if on {
                            Task { await model.connectAppleCalendar(); state.refresh(model.calendarSource) }
                        } else {
                            model.updateMeetings { $0.appleCalendarEnabled = false }
                        }
                    }))
                calendarStatus
            }
        }
        if m.appleCalendarOrDefault, state.authorization == .granted {
            RowDivider()
            FormRow(label: "Calendars", caption: model.monitor.state == .calendarSelectionStale ? "Selected calendars not found — re-select below." : nil) {
                VStack(alignment: .leading, spacing: 6) {
                    if state.calendars.isEmpty { Text("No calendars found").foregroundStyle(.mnText2) }
                    ForEach(state.calendars) { c in
                        Toggle(c.title, isOn: Binding(get: { isTracked(c) }, set: { setTracked(c, $0) })).toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    /// `calendarIDs == nil` = wszystkie kalendarze.
    private func isTracked(_ c: CalendarInfo) -> Bool { m.calendarIDs?.contains(c.id) ?? true }

    private func setTracked(_ c: CalendarInfo, _ on: Bool) {
        var ids = Set(m.calendarIDs ?? state.calendars.map(\.id))
        if on { ids.insert(c.id) } else { ids.remove(c.id) }
        let all = Set(state.calendars.map(\.id))
        model.updateMeetings { $0.calendarIDs = ids == all ? nil : state.calendars.map(\.id).filter(ids.contains) }
    }

    // MARK: Pomocnicze

    private func toggle(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
    }

    /// Pusty = domyślny (`nil`); niepoprawny lub <= 0 — zostaje poprzednia wartość.
    private func advancedRow(_ label: String, unit: String, placeholder: Double, text: Binding<String>,
                             set: @escaping (Double?) -> Void) -> some View {
        FormRow(label: label) {
            HStack(spacing: 6) {
                TextField(String(Int(placeholder)), text: text).textFieldStyle(.roundedBorder).frame(width: 80)
                    .onChange(of: text.wrappedValue) {
                        let t = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty { set(nil) } else if let v = Double(t), v > 0 { set(v) }
                    }
                Text(unit).foregroundStyle(.mnText2)
            }
        }
    }
}
