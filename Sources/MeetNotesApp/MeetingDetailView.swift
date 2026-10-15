import AVFoundation
import MeetNotesNotes
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesTranscription
import SwiftUI

/// Odtwarzanie: odsłuch = ścieżka systemowa bit w bit (spec rdzenia §5); mikrofon osobno.
final class PlaybackState: ObservableObject {
    var player: AVAudioPlayer?
    var track: String?
}

/// Widok spotkania (spec 1.5 §5.2): tytuł, chipy i zakładki My notes / Transcript / Summary.
/// Podczas nagrania tylko My notes — reszta powstaje po spotkaniu.
struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    @StateObject private var playback = PlaybackState()
    @StateObject private var state: MeetingViewState

    init(item: SessionItem, state: MeetingViewState = MeetingViewState()) {
        self.item = item
        _state = StateObject(wrappedValue: state)
    }

    private var isRecording: Bool { SessionStatus.isRecording(item.url, recordingDirectory: model.recording.directory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isRecording {
                MyNotesTab(state: state, item: item).padding(.top, 16)
                Text("Transcript and notes arrive after the meeting.").font(.callout).foregroundStyle(.mnText2).padding(.top, 8)
            } else {
                MeetingTabBar(selection: Binding(get: { state.tab ?? defaultTab }, set: { state.tab = $0 }))
                    .padding(.top, 18).padding(.bottom, 16)
                switch state.tab ?? defaultTab {
                case .myNotes: MyNotesTab(state: state, item: item)
                case .transcript: TranscriptTab(state: state, item: item) { play($0) }
                case .summary: SummaryTab(state: state, item: item)
                }
            }
        }
        .contentColumn(640)
        .contentBackground()
        .navigationTitle(item.title)
        .onAppear {
            if !state.loadedMyNotes { state.myNotes = item.notes.myNotes; state.loadedMyNotes = true }
            // Pole tytułu pokazuje ten sam tytuł co lista (ręczny > auto > z notatki); „Untitled meeting" zostaje placeholderem.
            state.titleDraft = item.title == NoteTitle.untitled ? "" : item.title
        }
        .toolbar {
            Button {
                if playback.player?.isPlaying == true { playback.player?.pause() } else if playback.player != nil || load("system") { playback.player?.play() }
            } label: {
                Label("Play", systemImage: "playpause")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play or pause")
            .disabled(isRecording)
        }
    }

    /// Notatki są → Summary; jest transkrypt → Transcript; inaczej My notes.
    private var defaultTab: MeetingTab {
        if item.notes.summary != nil { return .summary }
        if item.transcript != nil { return .transcript }
        return .myNotes
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Untitled meeting", text: $state.titleDraft)
                .textFieldStyle(.plain)
                .documentTitle()
                .onSubmit { model.notes.setManualTitle(state.titleDraft, for: item) }
            HStack(spacing: 12) {
                MetaLine([
                    item.startedAt.formatted(date: .abbreviated, time: .shortened),
                    item.duration.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) } ?? "",
                    model.presetFor(sessionURL: item.url).map { "Preset \($0.name)" } ?? "",
                ])
                if model.notes.isTitling(item.id) { StateLabel(.progress(nil), "Naming the meeting…") }
            }
            if !item.notes.problems.isEmpty {
                Label("\(item.notes.problems.joined(separator: ", ")) in this meeting's notes couldn't be read. They're kept aside before anything new is saved.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.mnWarn)
            }
        }
    }

    /// ChatGPT #8: „Me" nie ma w pliku odsłuchu (to tap systemowy) — gramy tor mikrofonu,
    /// przeliczając czas sesji na czas tej ścieżki.
    private func play(_ u: Utterance) {
        let aecOK = item.summary?.tracks.first { $0.id == "mic_aec" }.map { $0.failure == nil && $0.channels > 0 } ?? false
        let track = u.speaker == .them ? "system" : (aecOK ? "mic_aec" : "mic_raw")
        let offset = item.summary?.tracks.first { $0.id == track }?.offsetSeconds ?? 0
        guard playback.track == track || load(track) else { return }
        playback.player?.currentTime = max(0, u.start - offset)
        playback.player?.play()
    }

    /// Nieudane wczytanie nie zostaje zapamiętane jako wczytana ścieżka (check S15 #4).
    private func load(_ track: String) -> Bool {
        do {
            playback.player = try AVAudioPlayer(contentsOf: item.url.appendingPathComponent("\(track).caf"))
            playback.track = track
            return true
        } catch {
            playback.player = nil
            playback.track = nil
            let ns = error as NSError
            let why = ns.domain == NSOSStatusErrorDomain ? OSStatusText.describe(ns.code) : error.localizedDescription
            model.lastError = "Couldn't open the \(track) recording: \(why)"
            return false
        }
    }

    static func time(_ s: Double) -> String {
        let i = Int(s)
        return String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60)
    }
}

struct UtteranceRow: View {
    let utterance: Utterance
    let isAuto: Bool
    let onJump: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(MeetingDetailView.time(utterance.start), action: onJump)
                .buttonStyle(.plain)
                .font(.callout).monospacedDigit().foregroundStyle(.mnText2)
                .help("Play from here")
            Text(utterance.speaker == .me ? "Me" : "Them")
                .font(.callout.weight(.semibold))
                .frame(width: 40, alignment: .leading)
                .foregroundStyle(.mnText2)
            VStack(alignment: .leading, spacing: 2) {
                Text(utterance.text).font(.system(size: 13)).foregroundStyle(.mnText).textSelection(.enabled)
                if let lang = utterance.languageMismatch {
                    // P11: widoczne, nie ukryte — i wyłączone z notatek.
                    Label(isAuto ? "Unexpected alphabet (\(lang.rawValue.uppercased())) — likely misrecognized, excluded from notes"
                                 : "Looks like \(lang.rawValue.uppercased()), not the preset's language — excluded from notes",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.mnWarn)
                }
                if utterance.echoOfThem == true {
                    Label("Echo of the other side — excluded from notes", systemImage: "speaker.wave.2")
                        .font(.callout)
                        .foregroundStyle(.mnText2)
                }
                if utterance.approximateTiming {
                    Text("Approximate timing").font(.subheadline).foregroundStyle(.mnText2)
                }
            }
        }
    }
}
