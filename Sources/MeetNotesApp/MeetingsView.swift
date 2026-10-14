import MeetNotesProviders
import SwiftUI

/// Strona główna, wariant B (spec fazy 1, §1.2): oś nagrań po dniach. Szyna
/// „Coming up" i wyróżnione najbliższe spotkanie przychodzą z kalendarzem.
final class MeetingsViewState: ObservableObject {
    @Published var query = ""
}

struct MeetingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = MeetingsViewState()
    private var query: String { state.query }

    private var days: [(Date, [SessionItem])] {
        let cal = Calendar.current
        let filtered = model.sessions.filter { s in
            s.url != model.recording.directory
                && (query.isEmpty || s.transcript?.utterances.contains { $0.text.localizedCaseInsensitiveContains(query) } == true)
        }
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List(selection: $model.selectedSessionID) {
                if model.recording.isRecording {
                    RecordingRow(elapsed: model.recording.elapsed, preset: model.recording.presetLabel)
                }
                ForEach(days, id: \.0) { day, items in
                    SwiftUI.Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(items) { item in SessionRow(item: item).tag(item.id) }
                    }
                }
            }
            .overlay {
                if model.sessions.isEmpty && !model.recording.isRecording {
                    ContentUnavailableView {
                        Label("Record your first meeting", systemImage: "waveform")
                    } description: {
                        Text("System audio and your microphone are recorded to separate files.")
                    } actions: {
                        Button("Record Meeting") { model.startRecording() }
                    }
                }
            }
            .searchable(text: $state.query, prompt: "Search transcripts")
            .navigationDestination(item: $model.selectedSessionID) { id in
                if let item = model.sessions.first(where: { $0.id == id }) { MeetingDetailView(item: item) }
            }
            .toolbar {
                ToolbarItemGroup {
                    PresetMenu()
                    Button {
                        model.recording.isRecording ? model.recording.stop() : model.startRecording()
                    } label: {
                        Label(model.recording.isRecording ? "Stop" : "Record", systemImage: model.recording.isRecording ? "stop.circle" : "record.circle")
                    }
                    .help(model.recording.isRecording ? "Stop recording" : "Record a meeting")
                }
            }
            .navigationTitle("Meetings")
        }
    }
}

/// 🔴 Preset — z językiem — widoczny przed startem (W§2, §6).
struct PresetMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.presets.presets) { p in
                Button(p.name + " · " + p.languageLabel) { model.activePresetID = p.id }
            }
            Divider()
            Button("Edit Presets…") { model.section = .presets }
        } label: {
            Label(model.activePreset.map { "\($0.name) · \($0.languageLabel)" } ?? "No preset",
                  systemImage: "slider.horizontal.3")
        }
        .help("Preset used for the next recording: language and models")
    }
}

struct RecordingRow: View {
    let elapsed: TimeInterval
    let preset: String
    var body: some View {
        HStack {
            Image(systemName: "record.circle").foregroundStyle(.red).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("Recording").font(.headline)
                Text("\(RecordingPanelView.clock(elapsed)) · \(preset)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

struct SessionRow: View {
    let item: SessionItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.startedAt.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                Text(item.duration.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) } ?? "—")
                    .foregroundStyle(.secondary)
                if let bad = item.summary?.tracks.filter({ $0.failure != nil || $0.permissionDenied != nil }), !bad.isEmpty {
                    // ChatGPT #16: brak „Oni" albo „Ja" widoczny na liście, nie tylko w dzienniku.
                    Label("Problem: " + Set(bad.map { $0.id == "system" ? "system audio" : "microphone" }).sorted().joined(separator: ", "),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .help(bad.map { "\($0.id): \($0.failure ?? $0.permissionDenied ?? "")" }.joined(separator: "\n"))
                }
            }
            Spacer()
            status
        }
    }

    @ViewBuilder private var status: some View {
        if let p = item.progress, p < 1 {
            ProgressView(value: p) { Text("Transcribing \(Int(p * 100))%") }.frame(width: 140)
        } else if item.summary?.crashed == true {
            Label("Recovered", systemImage: "bandage").foregroundStyle(.orange).help("The app stopped during this recording; the audio was kept")
        } else if let t = item.transcript, !t.failedChunks.isEmpty {
            Label("Partial — \(t.failedChunks.count) gaps", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        } else if item.transcript == nil && item.runID != nil {
            Label("Interrupted", systemImage: "pause.circle").foregroundStyle(.orange)
        } else if let t = item.transcript {
            if t.languageFlagCount > 0 {
                Label("\(t.languageFlagCount) language flags", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                Label("Transcript ready", systemImage: "checkmark.circle")
            }
        } else {
            Text("Not transcribed").foregroundStyle(.secondary)
        }
    }
}
