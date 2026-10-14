import MeetNotesNotes
import MeetNotesProviders
import SwiftUI

/// Strona główna, wariant B bez kalendarza (spec 1.5 §5.1): karta „Record a meeting" i oś spotkań po dniach.
/// Miejsce po „Coming up" zajmuje karta; kalendarz wróci w fazie 3.
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

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                RecordCard().padding([.horizontal, .top], 16).padding(.bottom, 8)
                List(selection: $model.selectedSessionID) {
                    ForEach(days, id: \.0) { day, items in
                        SwiftUI.Section(day.formatted(date: .complete, time: .omitted)) {
                            ForEach(items) { item in SessionRow(item: item).tag(item.id) }
                        }
                    }
                }
                .overlay {
                    if model.sessions.isEmpty {
                        ContentUnavailableView {
                            Label("No meetings yet", systemImage: "waveform")
                        } description: {
                            Text("System audio and your microphone are recorded to separate files.")
                        }
                    }
                }
            }
            .searchable(text: $state.query, prompt: "Search titles, notes and transcripts")
            .navigationDestination(item: $model.selectedSessionID) { id in
                // `.id`: bez niego SwiftUI zostawia ten sam widok przy zmianie wyboru (Record, „Open Note") i tekst z jednej
                // sesji trafiłby do drugiej (Review Focus #9).
                if let item = model.sessions.first(where: { $0.id == id }) { MeetingDetailView(item: item).id(item.id) }
            }
            .navigationTitle("Meetings")
        }
    }
}

/// 🔴 Preset — z językiem i modelem ASR — widoczny przed startem (W§2, §6; BACKLOG D3 „preset nieczytelny").
struct RecordCard: View {
    @Environment(AppModel.self) private var model

    private func detail(_ p: Preset) -> String {
        "\(p.name) · \(p.languageLabel) · \(p.asr?.model ?? "no speech-to-text model")"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.recording.isRecording ? "Recording in progress" : "Record a meeting").font(.headline)
                if model.recording.isRecording {
                    Text("\(RecordingPanelView.clock(model.recording.elapsed)) · \(model.recording.presetLabel)")
                        .monospacedDigit().foregroundStyle(.secondary)
                } else if let p = model.activePreset {
                    Text(detail(p)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Create a preset to start").foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.recording.isRecording { PresetMenu() }
            Button {
                model.recording.isRecording ? model.recording.stop() : model.startRecording()
            } label: {
                Label(model.recording.isRecording ? "Stop" : "Record", systemImage: model.recording.isRecording ? "stop.circle" : "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .help(model.recording.isRecording ? "Stop recording" : "Record a meeting")
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Preset z nazwą widoczną w etykiecie (nie samą ikoną).
struct PresetMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.presets.presets) { p in
                Button(AppModel.label(p)) { model.activePresetID = p.id }
            }
            Divider()
            Button("Edit Presets…") { model.section = .presets }
        } label: {
            Text(model.activePreset.map { AppModel.label($0) } ?? "No preset")
        }
        .fixedSize()
        .help("Preset used for the next recording: language and models")
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem

    private var status: SessionStatus {
        SessionStatus.of(isRecording: SessionStatus.isRecording(item.url, recordingDirectory: model.recording.directory),
                         progress: item.progress, correcting: model.notes.isCorrecting(item.id), titling: model.notes.isTitling(item.id),
                         crashed: item.summary?.crashed == true, transcript: item.transcript, hasRun: item.runID != nil,
                         hasNotes: item.notes.summary != nil)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                HStack(spacing: 8) {
                    Text(item.startedAt.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                    if let d = item.duration {
                        Text(Duration.seconds(d).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    }
                }
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
            statusView
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .recording:
            Label("Recording · \(RecordingPanelView.clock(model.recording.elapsed))", systemImage: "record.circle")
                .monospacedDigit().foregroundStyle(.red)
        case .transcribing(let p):
            ProgressView(value: p) { Text("Transcribing \(Int(p * 100))%") }.frame(width: 140)
        case .correcting:
            Label("Improving transcript…", systemImage: "wand.and.stars").foregroundStyle(.secondary)
        case .titling:
            Label("Naming…", systemImage: "sparkles").foregroundStyle(.secondary)
        case .recovered:
            Label("Recovered", systemImage: "bandage").foregroundStyle(.orange).help("The app stopped during this recording; the audio was kept")
        case .partial(let gaps):
            Label("Partial — \(gaps) gaps", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        case .interrupted:
            Label("Interrupted", systemImage: "pause.circle").foregroundStyle(.orange)
        case .notesReady:
            Label("Notes ready", systemImage: "doc.text")
        case .flagged(let n):
            Label("\(n) language flags", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .transcriptReady:
            Label("Transcript ready", systemImage: "checkmark.circle")
        case .notTranscribed:
            Text("Not transcribed").foregroundStyle(.secondary)
        }
    }
}
