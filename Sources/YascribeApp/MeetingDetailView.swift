import AVFoundation
import YascribeNotes
import YascribeProviders
import YascribeRecording
import YascribeTranscription
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

    /// Uwaga 7 z odbioru: cały widok to jedna przewijana strona — tytuł, zakładki i treść w jednym
    /// `ScrollView` na całą szerokość detalu (pasek przy krawędzi okna), kolumna 640 w środku, bez wewnętrznych przewijań.
    /// `ScrollPage`: kolumna nie przeskakuje, gdy stały pasek przewijania pojawia się na dłuższej zakładce (błąd 5).
    var body: some View {
        ScrollPage(640) {
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
        }
        .contentBackground()
        // Uwaga 7 pkt 5: przycisk ▶II zniknął z paska (nie wynika z §11.5); odtwarzanie jest w menu Meeting.
        .focusedSceneValue(\.playRecording, isRecording ? nil : { togglePlayback() })
        .navigationTitle(item.title)
        .navigationBarBackButtonHidden(true) // własna kapsuła „Meetings” w pasku (D5)
        .onAppear {
            if !state.loadedMyNotes { state.myNotes = item.notes.myNotes; state.loadedMyNotes = true }
        }
        .confirmationDialog("Move “\(item.title)” to the Trash?", isPresented: Binding(
            get: { model.pendingDelete == item.id }, set: { if !$0 { model.pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { model.deleteSession(item.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The meeting folder, with its recordings and notes, goes to the Trash. You can put it back from there.")
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.selectedSessionID = nil } label: { Label("Meetings", systemImage: "chevron.left") }
                    .buttonStyle(.pill)
                    .help("Back to Meetings")
                    .accessibilityLabel("Back to Meetings")
            }
            ToolbarItem {
                Menu {
                    Button("Copy notes") { model.copyNotes(item) }.disabled(item.notes.summary == nil)
                    Button("Show in Finder") { model.showInFinder(item) }
                    Divider()
                    Button("Delete meeting…", role: .destructive) { model.pendingDelete = item.id }.disabled(!model.canDelete(item))
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("More").accessibilityLabel("More")
            }
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
            TextField("Untitled meeting", text: titleField)
                .textFieldStyle(.plain)
                .documentTitle()
                .onSubmit {
                    if let edit = state.titleEdit, NoteTitle.isEdit(edit, meta: item.notes.meta, noteTitle: item.notes.summary?.title) {
                        model.notes.setManualTitle(edit, for: item)
                    }
                    state.titleEdit = nil
                }
                .disabled(model.recordingsMove != nil)
            HStack(spacing: 12) {
                MetaLine([
                    item.startedAt.formatted(date: .abbreviated, time: .shortened),
                    item.duration.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) } ?? "",
                    model.presetFor(sessionURL: item.url).map { "Preset \($0.name)" } ?? "",
                    item.audioDeletedAfterDays.map { "Audio deleted after \($0) days" } ?? "",
                ])
                EventPickerChip(item: item)
                if model.notes.isTitling(item.id) { StateLabel(.progress(nil), "Naming the meeting…") }
                ForEach(item.trackProblems, id: \.trackID) { problemButton($0) }
            }
            EventAttendeesLine(link: item.notes.meta.calendarEvent)
            // R3: na czas przenoszenia folderu nagrań spotkanie jest tylko do odczytu.
            if model.recordingsMove != nil { StateLabel(.progress(nil), "Moving recordings…") }
            if !item.notes.problems.isEmpty {
                Label("\(item.notes.problems.joined(separator: ", ")) in this meeting's notes couldn't be read. They're kept aside before anything new is saved.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.mnWarn)
            }
        }
    }

    /// Błąd 4: pole pokazuje bieżący tytuł sesji (ręczny > auto > z notatki), dopóki użytkownik nie zacznie pisać —
    /// autotytuł zapisany przy otwartym widoku (nagranie otwiera spotkanie od razu) trafia do pola po przeładowaniu sesji.
    private var titleField: Binding<String> {
        Binding(get: { state.titleEdit ?? NoteTitle.fieldText(meta: item.notes.meta, noteTitle: item.notes.summary?.title) },
                set: { state.titleEdit = NoteTitle.fieldEdit($0, meta: item.notes.meta, noteTitle: item.notes.summary?.title) })
    }

    /// Poprawka 6: problem toru nagrania w linii chipów; klik = wyjaśnienie zwykłym językiem.
    private func problemButton(_ p: TrackProblem) -> some View {
        Button { state.problemPopover = p.trackID } label: {
            Label(p.name, systemImage: p.isWarning ? "exclamationmark.triangle" : "info.circle")
                .font(.callout).foregroundStyle(p.isWarning ? Color.mnWarn : Color.mnText2)
        }
        .buttonStyle(.plain)
        .help(p.line)
        .accessibilityLabel("\(p.name): \(p.line)")
        .popover(isPresented: Binding(get: { state.problemPopover == p.trackID },
                                      set: { if !$0 { state.problemPopover = nil } }), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(p.line).font(.system(size: 13, weight: .semibold))
                Text(p.detail).font(.callout).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
        }
    }

    /// Odsłuch nagrania (ścieżka systemowa) od bieżącego miejsca albo pauza.
    private func togglePlayback() {
        if playback.player?.isPlaying == true { playback.player?.pause() } else if playback.player != nil || load("system") { playback.player?.play() }
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
        if let n = item.audioDeletedAfterDays { model.lastError = "This meeting's audio was deleted after \(n) days."; return false }
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

/// Menu Meeting → „Play/Pause Recording”: akcja z otwartego widoku spotkania (`focusedSceneValue`).
/// Klucz ręcznie, bo `@Entry` to makro (CLAUDE.md).
struct PlayRecordingKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var playRecording: (() -> Void)? {
        get { self[PlayRecordingKey.self] }
        set { self[PlayRecordingKey.self] = newValue }
    }
}

/// Bez skrótu Spacja: zwykły klawisz w menu przechwyciłby spacje w tytule i w My notes.
struct PlayRecordingButton: View {
    @FocusedValue(\.playRecording) private var play
    var body: some View {
        Button("Play/Pause Recording") { play?() }.disabled(play == nil)
    }
}

/// Wiersz transkryptu (b-transcript.png): czas (cyfry stałej szerokości, klik = odtwarzanie), mówca, tekst;
/// echo, obcy język i przybliżony czas jako linie stanu pod tekstem.
struct UtteranceRow: View {
    let utterance: Utterance
    let isAuto: Bool
    let onJump: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Button(MeetingDetailView.time(utterance.start), action: onJump)
                .buttonStyle(.plain)
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(.mnText2)
                .frame(width: 72, alignment: .leading)
                .help("Play from here")
                .accessibilityLabel("Play from \(MeetingDetailView.time(utterance.start))")
            Text(utterance.speaker == .me ? "Me" : "Them")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.mnText)
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(utterance.text).font(.system(size: 13)).lineSpacing(4)
                    .foregroundStyle(utterance.excludedFromNotes ? Color.mnText2 : Color.mnText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let lang = utterance.languageMismatch {
                    // P11: widoczne, nie ukryte — i wyłączone z notatek.
                    WarnLabel(isAuto ? "Unexpected alphabet (\(lang.rawValue.uppercased())) — likely misrecognized, excluded from notes"
                                     : "Looks like \(lang.rawValue.uppercased()), not the preset's language — excluded from notes")
                }
                if utterance.echoOfThem == true {
                    StateLabel(.neutral, "Echo of the other side — excluded from notes")
                }
                if utterance.approximateTiming {
                    StateLabel(.neutral, "Approximate timing")
                }
            }
        }
        .padding(.vertical, 11)
    }
}
