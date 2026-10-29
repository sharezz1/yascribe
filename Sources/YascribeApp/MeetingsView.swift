import AppKit
import YascribeMeetings
import YascribeNotes
import YascribeProviders
import SwiftUI

/// Strona główna, wariant B z „Coming up” (macos.md §11.5, decyzja 2026-10-19; makiety b-cuB2.png, b-cuB2none.png):
/// nagłówek z Record ad hoc, karta najbliższego spotkania z Apple Calendar, linia reszty dnia i oś spotkań po dniach.
final class MeetingsViewState: ObservableObject {
    @Published var overviewID: String?
    /// Migawki: kalendarz i chwila na sztywno zamiast EventKit i zegara.
    var preview: (connected: Bool, events: [CalendarEventInfo], now: Date)?
}

struct MeetingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: MeetingsViewState

    init(state: MeetingsViewState = MeetingsViewState()) { _state = StateObject(wrappedValue: state) }

    private var days: [(Date, [SessionItem])] {
        let cal = Calendar.current
        let filtered = model.sessions.filter { model.matchesFilter($0) }
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
               ScrollPage(600) {
                VStack(alignment: .leading, spacing: 0) {
                    // Co minutę: „in 8 min” i wejście spotkania w okno 60 min. Kalendarz czyta tylko `ComingUpHeader`.
                    TimelineView(.everyMinute) { ctx in
                        ComingUpHeader(state: state, now: state.preview?.now ?? ctx.date)
                    }
                    FolderMenu()
                        .padding(.bottom, 14)
                    if model.sessions.isEmpty {
                        ContentUnavailableView {
                            Label("No meetings yet", systemImage: "waveform")
                        } description: {
                            Text("System audio and your microphone are recorded to separate files.")
                        }
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.0) { n, group in
                            HStack(spacing: 12) {
                                Text(Self.dayTitle(group.0))
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.mnText)
                                    .accessibilityAddTraits(.isHeader)
                                Rectangle().fill(.mnLine).frame(height: 1).accessibilityHidden(true)
                            }
                            .padding(.horizontal, 4).padding(.bottom, 10).padding(.top, n == 0 ? 8 : 28)
                            ForEach(Array(group.1.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { RowDivider(inset: 4) }
                                SessionRow(item: item, onPreview: { state.overviewID = item.id })
                            }
                        }
                    }
                }
            }
               .frame(maxWidth: .infinity)
                   ScrollView {
                       OverviewPanel(item: model.sessions.first { $0.id == state.overviewID })
                           .padding(24)
                   }
                   .frame(width: 280)
                   .frame(maxHeight: .infinity, alignment: .top)
                   .overlay(alignment: .leading) {
                       Rectangle().fill(.mnLine2).frame(width: 0.5)
                   }
            }
            .frame(minWidth: 720)
            .background(Color.mnCard)
            .navigationDestination(item: $model.selectedSessionID) { id in
                // `.id`: bez niego SwiftUI zostawia ten sam widok przy zmianie wyboru (Record, „Open Note") i tekst z jednej
                // sesji trafiłby do drugiej (Review Focus #9).
                if let item = model.sessions.first(where: { $0.id == id }) { MeetingDetailView(item: item).id(item.id) }
            }
            .navigationTitle("Meetings")
        }
    }
}

struct OverviewPanel: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let item {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.system(size: 16, weight: .medium))
                    Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12)).foregroundStyle(.mnText2)
                }
                RowDivider(inset: 0)
            }
            Text("Overview").textCase(.uppercase)
                .font(.system(size: 11, weight: .medium)).tracking(0.8)
                .foregroundStyle(.mnText2).accessibilityAddTraits(.isHeader)
            if let item {
                if let text = Overview.cached(item.notes.meta, runID: item.runID, transcript: item.transcript, correctedTranscript: item.corrected?.transcript) {
                    Text(text).font(.system(size: 13)).lineSpacing(5).foregroundStyle(.mnText)
                } else {
                    Text("No overview yet.").font(.system(size: 13)).foregroundStyle(.mnText2)
                    if model.notes.isTitling(item.id) {
                        Text("Generating…").font(.system(size: 12))
                    } else {
                        if model.notes.overviewFailure.contains(item.id) { Text("Couldn't generate overview. Try again.").font(.system(size: 12)) }
                        Button("Generate overview") { model.notes.generateOverview(item) }
                            .disabled(item.runID == nil || item.transcript == nil || model.notes.summaryChoice(for: item) == nil)
                    }
                }
            } else {
                Text("Point to or focus a meeting to see its overview.").font(.system(size: 13)).foregroundStyle(.mnText2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Góra strony: tytuł, preset i „● Record” ad hoc; pod nimi karta najbliższego spotkania albo jedna linia.
/// Jeden primary na ekranie (§11.4): Record na karcie, a bez karty (albo w trakcie nagrania: Stop) ten w nagłówku.
struct ComingUpHeader: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingsViewState
    let now: Date

    private func recordButton(recording: Bool, primary: Bool) -> some View {
        Button {
            recording ? model.recording.stop() : model.startRecording()
        } label: {
            HStack(spacing: 6) {
                if recording {
                    Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(.mnRecDot)
                } else {
                    Circle().fill(.mnRecDot).frame(width: 7, height: 7)
                }
                Text(recording ? "Stop" : "Record")
            }
        }
        .buttonStyle(PillButtonStyle(kind: primary ? .primary : .secondary))
        .help(recording ? "Stop recording" : "Record now, without a calendar event")
    }

    var body: some View {
        @Bindable var model = model
        // ponytail: EventKit pytany przy każdym przeliczeniu (co minutę, przy zmianie Settings lub nagrania); cache, gdyby było wolno.
        let connected = state.preview?.connected ?? model.calendarReady
        let up = ComingUp.of(state.preview?.events ?? model.todaysEvents(now: now), now: now)
        let recording = model.recording.isRecording
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PageTitle("Meetings").fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
                PresetMenu()
                recordButton(recording: recording, primary: recording || up.next == nil)
            }
            .padding(.bottom, model.activePreset?.isAutoLanguage == true ? 6 : 18)
            // Auto = ryzyko zmyślonej angielszczyzny (W§2): ostrzeżenie widoczne przed startem, ikona + słowo.
            if model.activePreset?.isAutoLanguage == true {
                WarnLabel("Auto language: the preset has no fixed language").font(.system(size: 11)).padding(.bottom, 14)
            }
            if let next = up.next {
                NextMeetingCard(event: next, now: now, recording: recording).padding(.bottom, 8)
                if !up.later.isEmpty {
                    Text(Self.laterLine(up.later)).font(.system(size: 11)).foregroundStyle(.mnText2).monospacedDigit()
                        .lineLimit(1).truncationMode(.tail).padding(.horizontal, 4)
                }
                Color.clear.frame(height: 22)
            } else {
                HStack(spacing: 12) {
                    Text(!connected ? "See your meetings here and start recording from them."
                         : up.later.isEmpty ? "No more meetings today." : Self.laterLine(up.later))
                        .foregroundStyle(.mnText2).monospacedDigit().lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    if connected {
                        LinkButton("Open Calendar") {
                            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                                NSWorkspace.shared.openApplication(at: app, configuration: .init())
                            }
                        }
                    } else {
                        LinkButton("Connect Apple Calendar…") { model.section = .settings }
                            .help("Settings → Integrations")
                    }
                }
                .font(.system(size: 13))
                .padding(.vertical, 12).padding(.horizontal, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
                .padding(.bottom, 14)
            }
        }
    }

    /// „Later today: 11:30 Forecast review · 14:00 Dentist (in person) · …”
    static func laterLine(_ events: [CalendarEventInfo]) -> String {
        "Later today: " + events.map {
            $0.start.formatted(date: .omitted, time: .shortened) + " " + $0.title + (ComingUp.appName($0) == nil ? " (in person)" : "")
        }.joined(separator: " · ")
    }
}

/// Odnośnik tekstowy (podkreślenie `text3`, jak `.link` w ekrany-b.html).
struct LinkButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.mnText).underline(color: .mnText3)
        }
        .buttonStyle(.plain)
    }
}

/// Karta najbliższego spotkania: „Next · in 8 min · Teams”, tytuł New York 20, godziny i uczestnicy; Record z tytułem
/// i powiązaniem z wydarzeniem (`calendarEvent`, spec 1.6 §4.7).
struct NextMeetingCard: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEventInfo
    let now: Date
    let recording: Bool

    private var details: String {
        var parts = [event.start.formatted(date: .omitted, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)]
        let n = event.attendees.count
        if n > 0 { parts.append(n == 1 ? "1 attendee" : "\(n) attendees") }
        parts.append("notes titled and linked to this event")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let app = ComingUp.appName(event)
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(ComingUp.timing(event, now: now) + " ·")
                    if let app {
                        Image(systemName: "video").font(.system(size: 9)).accessibilityHidden(true)
                        Text(app)
                    } else {
                        Text("In person")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.mnText2)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.system(size: 20, design: .serif)).foregroundStyle(.mnText).lineLimit(1).truncationMode(.tail)
                        Text(details).font(.system(size: 11)).monospacedDigit().foregroundStyle(.mnText2).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    Button {
                        model.startRecording(event: event)
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(.mnRecDot).frame(width: 8, height: 8)
                            Text("Record")
                        }
                    }
                    .buttonStyle(PillButtonStyle(kind: recording ? .secondary : .primary, large: true))
                    .disabled(recording)
                    .help(recording ? "A recording is already in progress" : "Record “\(event.title)”: the note gets its title and is linked to this event")
                }
            }
            .padding(16)
        }
    }
}

/// Przypisanie spotkania do folderu w nagłówku szczegółów (TASK-26). Pliki nagrania zostają na miejscu.
struct FolderChip: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem

    var body: some View {
        FieldMenu(label: "Folder", value: model.folderName(of: item) ?? "No folder", prefix: "Folder", width: nil) {
            MeetingFolderOptions(item: item)
        }
        .disabled(model.recordingsMove != nil)
    }
}

/// Wspólne przypisanie folderu na liście i w szczegółach spotkania.
struct MeetingFolderOptions: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem

    var body: some View {
        Picker("Folder", selection: Binding<String?>(
            get: { model.folders.folder(item.notes.meta.folderID)?.id },
            set: { model.notes.setFolder($0, for: item) }
        )) {
            Text("No folder").tag(String?.none)
            ForEach(model.folders.folders) { folder in
                Text(folder.name).tag(Optional(folder.id))
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button("New Folder…") { model.promptNewFolder(assignTo: item) }
    }
}

struct SessionFolderMenu: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem

    var body: some View {
        Menu {
            MeetingFolderOptions(item: item)
        } label: {
            Label(model.folderName(of: item) ?? (model.folders.folders.isEmpty ? "Create folder" : "Add to folder"),
                  systemImage: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.mnText2)
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 8).frame(height: 28)
                .frame(maxWidth: 140)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(.mnLine, style: StrokeStyle(lineWidth: 0.75, dash: model.folderName(of: item) == nil ? [3, 2] : [])))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .disabled(model.recordingsMove != nil)
        .accessibilityLabel("Folder for \(item.title)")
        .accessibilityValue(model.folderName(of: item) ?? "No folder")
        .help("Choose or create a folder for this meeting")
    }
}

/// Te same akcje w menu pod trzema kropkami i pod prawym przyciskiem.
struct SessionActions: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem

    var body: some View {
        Menu("Move to Folder") { MeetingFolderOptions(item: item) }
            .disabled(model.recordingsMove != nil)
        Button("Show in Finder") { model.showInFinder(item) }
        Divider()
        Button("Delete meeting…", role: .destructive) { model.requestDelete(item) }
            .disabled(!model.canDelete(item))
    }
}

/// Filtr folderów (TASK-26): All / No folder / folder, plus tworzenie, zmiana nazwy i usuwanie folderu.
/// Usunięcie folderu nie usuwa spotkań — zostają w „No folder".
struct FolderMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button("All folders") { model.meetingFilter = .all }
            Button("No folder") { model.meetingFilter = .unfiled }
            if !model.folders.folders.isEmpty {
                Divider()
                ForEach(model.folders.folders) { f in
                    Button(f.name) { model.meetingFilter = .folder(f.id) }
                }
            }
            Divider()
            Button("New Folder…") { model.promptNewFolder() }
            if !model.folders.folders.isEmpty {
                Menu("Edit Folders") {
                    ForEach(model.folders.folders) { f in
                        Menu(f.name) {
                            Button("Rename…") { model.promptRenameFolder(f.id) }
                            Button("Delete Folder…", role: .destructive) { model.confirmDeleteFolder(f.id) }
                        }
                    }
                }
            }
        } label: {
            Label(model.filterLabel, systemImage: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.mnText)
                .padding(.horizontal, 8).frame(height: 28)
                .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Folder filter")
        .accessibilityValue(model.filterLabel)
        .help("Group meetings in folders. Recordings stay on disk.")
    }
}

/// Preset z nazwą widoczną w etykiecie (nie samą ikoną). Język i model są obok, w opisie karty.
struct PresetMenu: View {
    @Environment(AppModel.self) private var model
    var width: CGFloat? = 140

    var body: some View {
        FieldMenu(label: "Preset", value: model.activePreset?.name ?? "No preset", width: width) {
            ForEach(model.presets.presets) { p in
                Button(AppModel.label(p)) { model.activePresetID = p.id }
            }
            Divider()
            Button("Edit Presets…") { model.section = .presets }
        }
        .help(model.activePreset.map { "Preset for the next recording: \($0.languageLabel) · \($0.asr?.model ?? "no speech-to-text model")" }
              ?? "Create a preset to start recording")
    }
}

/// Stan z ostrzeżeniem (`warn` + ikona + słowo); `StateLabel` nie ma wariantu „warn".
struct SessionRow: View {
    @Environment(AppModel.self) private var model
    @StateObject private var hover = HoverState()
    @FocusState private var focused: Bool
    let item: SessionItem
    var onPreview: (() -> Void)? = nil

    private var status: SessionStatus {
        SessionStatus.of(isRecording: SessionStatus.isRecording(item.url, recordingDirectory: model.recording.directory),
                         progress: item.progress, correcting: model.notes.isCorrecting(item.id), titling: model.notes.isTitling(item.id),
                         crashed: item.summary?.crashed == true, transcript: item.transcript, hasRun: item.runID != nil,
                         hasNotes: item.notes.summary != nil, correctionFailed: model.notes.correctionFailureMessage(item.id) != nil)
    }

    /// „14:02 · 42 min · Polish". Język bieżącego przebiegu (`runLanguage`, I2), bez przebiegu z presetu zamrożonego przy starcie; Auto → „Auto".
    private var meta: String {
        var parts = [item.startedAt.formatted(date: .omitted, time: .shortened)]
        if let d = item.duration { parts.append(Duration.seconds(d).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) }
        let lang = model.runLanguage(item)
        if lang.isAuto {
            parts.append("Auto")
        } else if let l = lang.language {
            parts.append(Locale(identifier: "en").localizedString(forLanguageCode: l.rawValue) ?? l.rawValue.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.selectedSessionID = item.id } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText)
                            .lineLimit(1).truncationMode(.tail)
                        Text(meta).font(.system(size: 11)).monospacedDigit().foregroundStyle(.mnText2).lineLimit(1)
                        // ChatGPT #16: brak „Oni" albo „Ja" widoczny na liście, nie tylko w dzienniku. Poprawka 6: tylko
                        // ostrzeżenia — cisza na samym początku, po której przyszedł dźwięk, to informacja w widoku spotkania.
                        let bad = item.trackProblems.filter(\.isWarning)
                        if !bad.isEmpty {
                            Label("Problem: " + Set(bad.map { $0.name.lowercased() }).sorted().joined(separator: ", "),
                                  systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11)).foregroundStyle(.mnWarn)
                                .help(bad.map(\.line).joined(separator: "\n"))
                        }
                    }
                    Spacer(minLength: 8)
                    statusView
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focused)
            .onChange(of: focused) { _, value in if value { onPreview?() } }
            if status == .correctionFailed {
                Button("Retry") { model.notes.retryCorrection(item) }
                    .buttonStyle(.pillSmall).disabled(!model.notes.canRetryCorrection(item))
                    .help("Run the correction again")
            }
            SessionFolderMenu(item: item)
            Menu {
                SessionActions(item: item)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.mnText2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel("Actions for \(item.title)")
            .help("Meeting actions")
        }
        .padding(.vertical, 9).padding(.horizontal, 4)
        .background(hover.hovering ? Color.mnSelection : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hover.hovering = $0; if $0 { onPreview?() } }
        .contextMenu {
            SessionActions(item: item)
        }
        .help(model.deleteBlocker(item) ?? "")
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .recording:
            StateLabel(.live, "Recording \(RecordingPanelView.clock(model.recording.elapsed))")
        case .transcribing(let p):
            StateLabel(.progress(p), "Transcribing \(Int(p * 100))%")
        case .correcting:
            StateLabel(.progress(nil), "Correcting…")
        case .correctionFailed:
            StateLabel(.bad, "Correction failed").help(model.notes.correctionFailureMessage(item.id) ?? "")
        case .titling:
            StateLabel(.progress(nil), "Naming…")
        case .recovered:
            WarnLabel("Recovered").help("The app stopped during this recording; the audio was kept")
        case .partial(let gaps):
            WarnLabel("Partial — \(gaps) gaps")
        case .interrupted:
            WarnLabel("Interrupted")
        case .notesReady:
            StateLabel(.ok, "Notes ready")
        case .flagged(let n):
            WarnLabel("\(n) language flags")
        case .transcriptReady:
            StateLabel(.neutral, "Transcript ready")
        case .notTranscribed:
            StateLabel(.neutral, "Not transcribed")
        }
    }
}

extension SessionItem {
    /// Problemy torów nagrania (poprawka 6): cisza tylko na początku nagrania = informacja, nie ostrzeżenie.
    var trackProblems: [TrackProblem] { TrackProblem.of(tracks: summary?.tracks ?? [], transcript: transcript) }
}
