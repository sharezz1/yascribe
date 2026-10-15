import MeetNotesNotes
import MeetNotesProviders
import SwiftUI

/// Strona główna, wariant B bez kalendarza (spec 1.5 §5.1): karta „Record a meeting" i oś spotkań po dniach.
/// Miejsce po „Coming up" zajmuje karta; kalendarz wróci w fazie 3. Wygląd: macos.md §11.5, makieta b-home.png.
final class MeetingsViewState: ObservableObject {
    @Published var query = ""
}

struct MeetingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = MeetingsViewState()

    private var days: [(Date, [SessionItem])] {
        let cal = Calendar.current
        let filtered = model.sessions.filter { s in
            SessionSearch.matches(state.query, title: s.title, myNotes: s.notes.myNotes, summary: s.notes.summary?.markdown,
                                  transcript: s.transcript(corrected: true))
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        PageTitle("Meetings")
                        Spacer(minLength: 12)
                        SearchCapsule(text: $state.query)
                    }
                    .padding(.bottom, 18)
                    RecordCard().padding(.bottom, 26)
                    if model.sessions.isEmpty {
                        ContentUnavailableView {
                            Label("No meetings yet", systemImage: "waveform")
                        } description: {
                            Text("System audio and your microphone are recorded to separate files.")
                        }
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.0) { n, group in
                            Text(Self.dayTitle(group.0))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.mnText2)
                                .padding(.leading, 4).padding(.bottom, 2).padding(.top, n == 0 ? 0 : 20)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(group.1.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { RowDivider(inset: 4) }
                                SessionRow(item: item)
                            }
                        }
                    }
                }
                .contentColumn(580)
            }
            .contentBackground()
            .navigationDestination(item: $model.selectedSessionID) { id in
                // `.id`: bez niego SwiftUI zostawia ten sam widok przy zmianie wyboru (Record, „Open Note") i tekst z jednej
                // sesji trafiłby do drugiej (Review Focus #9).
                if let item = model.sessions.first(where: { $0.id == id }) { MeetingDetailView(item: item).id(item.id) }
            }
            .navigationTitle("Meetings")
        }
    }
}

/// Wyszukiwarka-kapsuła obok tytułu. Zamiast `.searchable`: ten ląduje w pasku okna, a makieta ma go w linii z tytułem.
struct SearchCapsule: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.mnText2).accessibilityHidden(true)
            TextField("Search meetings", text: $text).textFieldStyle(.plain)
                .accessibilityLabel("Search titles, notes and transcripts")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.mnText2) }
                    .buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 210, height: 28)
        .background(.mnField, in: Capsule())
        .overlay(Capsule().strokeBorder(.mnLine, lineWidth: 0.5))
        .help("Search titles, notes and transcripts")
    }
}

/// 🔴 Preset — z językiem i modelem ASR — widoczny przed startem (W§2, §6; BACKLOG D3 „preset nieczytelny").
struct RecordCard: View {
    @Environment(AppModel.self) private var model

    @ViewBuilder private func detail(_ p: Preset) -> some View {
        HStack(spacing: 4) {
            if p.isAutoLanguage {
                // Auto = ryzyko zmyślonej angielszczyzny (W§2): ostrzeżenie to ikona + słowo, nie sam kolor.
                Label("Auto language", systemImage: "exclamationmark.triangle").foregroundStyle(.mnWarn)
                Text("· " + (p.asr?.model ?? "no speech-to-text model"))
            } else {
                Text("\(p.languageLabel) · \(p.asr?.model ?? "no speech-to-text model")")
            }
        }
        .font(.callout).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.middle)
    }

    var body: some View {
        let recording = model.recording.isRecording
        Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recording ? "Recording in progress" : "Record a meeting")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.mnText)
                    if recording {
                        Text("\(RecordingPanelView.clock(model.recording.elapsed)) · \(model.recording.presetLabel)")
                            .font(.callout).monospacedDigit().foregroundStyle(.mnText2)
                    } else {
                        HStack(spacing: 8) {
                            PresetMenu()
                            if let p = model.activePreset { detail(p) } else {
                                Text("Create a preset to start").font(.callout).foregroundStyle(.mnText2)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Button {
                    recording ? model.recording.stop() : model.startRecording()
                } label: {
                    HStack(spacing: 6) {
                        if recording {
                            Image(systemName: "stop.fill").font(.system(size: 10)).foregroundStyle(.mnRecDot)
                        } else {
                            Circle().fill(.mnRecDot).frame(width: 8, height: 8)
                        }
                        Text(recording ? "Stop" : "Record")
                    }
                }
                .buttonStyle(PillButtonStyle(kind: .primary, large: true))
                .help(recording ? "Stop recording" : "Record a meeting")
            }
            .padding(.vertical, 14).padding(.leading, 16).padding(.trailing, 14)
        }
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
        .help("Preset used for the next recording: language and models")
    }
}

/// Stan z ostrzeżeniem (`warn` + ikona + słowo); `StateLabel` nie ma wariantu „warn".
struct SessionRow: View {
    @Environment(AppModel.self) private var model
    @StateObject private var hover = HoverState()
    let item: SessionItem

    private var status: SessionStatus {
        SessionStatus.of(isRecording: SessionStatus.isRecording(item.url, recordingDirectory: model.recording.directory),
                         progress: item.progress, correcting: model.notes.isCorrecting(item.id), titling: model.notes.isTitling(item.id),
                         crashed: item.summary?.crashed == true, transcript: item.transcript, hasRun: item.runID != nil,
                         hasNotes: item.notes.summary != nil, correctionFailed: model.notes.correctionFailureMessage(item.id) != nil)
    }

    /// „14:02 · 42 min · Polish". Język z presetu zamrożonego przy starcie (`presetFor`); preset Auto → „Auto".
    private var meta: String {
        var parts = [item.startedAt.formatted(date: .omitted, time: .shortened)]
        if let d = item.duration { parts.append(Duration.seconds(d).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) }
        if let p = model.presetFor(sessionURL: item.url) {
            if p.isAutoLanguage {
                parts.append("Auto")
            } else if let l = p.language {
                parts.append(Locale(identifier: "en").localizedString(forLanguageCode: l.rawValue) ?? l.rawValue.uppercased())
            }
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
                        if let bad = item.summary?.tracks.filter({ $0.failure != nil || $0.permissionDenied != nil }), !bad.isEmpty {
                            // ChatGPT #16: brak „Oni" albo „Ja" widoczny na liście, nie tylko w dzienniku.
                            Label("Problem: " + Set(bad.map { $0.id == "system" ? "system audio" : "microphone" }).sorted().joined(separator: ", "),
                                  systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11)).foregroundStyle(.mnWarn)
                                .help(bad.map { "\($0.id): \($0.failure ?? $0.permissionDenied ?? "")" }.joined(separator: "\n"))
                        }
                    }
                    Spacer(minLength: 8)
                    statusView
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if status == .correctionFailed {
                Button("Retry") { model.notes.retryCorrection(item) }
                    .buttonStyle(.pillSmall).disabled(!model.notes.canRetryCorrection(item))
                    .help("Run the correction again")
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 4)
        .background(hover.hovering ? Color.mnSelection : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hover.hovering = $0 }
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
