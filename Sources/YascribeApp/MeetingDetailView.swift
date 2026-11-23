import AVFoundation
import YascribeNotes
import YascribeProviders
import YascribeRecording
import YascribeTranscription
import SwiftUI

/// Odtwarzanie: odsłuch = ścieżka systemowa bit w bit (spec rdzenia §5); mikrofon osobno.
/// TASK-109: segment gra od startu do końca; `playing` = indeks grającej wypowiedzi w `utterances`.
@MainActor final class PlaybackState: ObservableObject {
    var player: AVAudioPlayer?
    var track: String?
    @Published private(set) var playing: Int?
    private var stopTask: Task<Void, Never>?

    /// Nowe odtworzenie anuluje stop poprzedniego; wszystko na MainActor, więc anulowane zadanie nie zdąży zatrzymać następnego.
    /// `seconds == nil` = gra do pauzy (menu Meeting).
    func started(index: Int?, seconds: Double?) {
        stopTask?.cancel()
        playing = index
        guard let seconds else { stopTask = nil; return }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.player?.pause()
            self.playing = nil
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.pause()
        playing = nil
    }
}

/// Widok spotkania (spec 1.5 §5.2): tytuł, chipy i zakładki My notes / Transcript / Summary.
/// Podczas nagrania tylko My notes — reszta powstaje po spotkaniu.
struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    let presentsModelsSheet: Bool
    let bottomInset: CGFloat
    @StateObject private var playback = PlaybackState()
    @StateObject private var state: MeetingViewState
    @StateObject private var speakerMenu = SpeakerMenuState()

    init(item: SessionItem, state: MeetingViewState = MeetingViewState(), presentsModelsSheet: Bool = true, bottomInset: CGFloat = 0) {
        self.item = item
        self.presentsModelsSheet = presentsModelsSheet
        self.bottomInset = bottomInset
        _state = StateObject(wrappedValue: state)
    }

    private var isRecording: Bool { SessionStatus.isRecording(item.url, recordingDirectory: model.recording.directory) }

    /// Nagłówek i karty zostają na miejscu; przewija się tylko treść wybranej karty.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !isRecording {
                    ViewThatFits(in: .horizontal) {
                        tabRow(compact: false)
                        tabRow(compact: true)
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .top)

            ScrollPage(640, showsIndicators: false) {
                if isRecording {
                    VStack(alignment: .leading, spacing: 8) {
                        MyNotesTab(state: state, item: item)
                        Text("Transcript and notes arrive after the meeting.").font(.callout).foregroundStyle(.mnText2)
                    }
                } else {
                    switch state.tab ?? defaultTab {
                    case .myNotes: MyNotesTab(state: state, item: item)
                    case .transcript: TranscriptTab(state: state, item: item, playing: playback.playing) { play($0, $1) }
                    case .summary: SummaryTab(state: state, item: item)
                    }
                }
            }
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
        }
        .dismissibleSheet(isPresented: Binding(get: { presentsModelsSheet && state.modelsSheet },
                                               set: { state.modelsSheet = $0 }), onDismiss: { state.modelsSheet = false }) {
            Self.modelsSheet(for: item, state: state)
        }
        .background(Color.mnCard)
        // Uwaga 7 pkt 5: przycisk ▶II zniknął z paska (nie wynika z §11.5); odtwarzanie jest w menu Meeting.
        .focusedSceneValue(\.playRecording, isRecording || item.audioDeletedAfterDays != nil ? nil : { togglePlayback() })
        .navigationTitle(item.displayTitle)
        .onAppear {
            if isRecording, state.tab == nil { state.tab = .myNotes }
            if !state.loadedMyNotes { state.myNotes = item.notes.myNotes; state.loadedMyNotes = true }
        }
        .confirmationDialog("Move “\(item.displayTitle)” to the Trash?", isPresented: Binding(
            get: { model.pendingDelete == item.id }, set: { if !$0 { model.pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { model.deleteSession(item.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The meeting folder, with its recordings and notes, goes to the Trash. You can put it back from there.")
        }

    }

    /// Notatki są → Summary; jest transkrypt → Transcript; inaczej My notes.
    private var defaultTab: MeetingTab { Self.defaultTab(for: item) }

    private func tabRow(compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MeetingTabBar(selection: Binding(get: { state.tab ?? defaultTab }, set: { state.tab = $0 }))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            if (state.tab ?? defaultTab) == .summary, item.notes.summary != nil {
                SummaryActions(state: state, item: item, compact: compact)
                    .fixedSize().padding(.bottom, 9)
            } else if (state.tab ?? defaultTab) == .transcript {
                TranscriptActions(state: state, item: item, compact: compact)
                    .fixedSize().padding(.bottom, 9)
            }
        }
        // Stała wysokość rzędu: przyciski Transcript/Summary (wyrównane do linii bazowej) dawały 37,5 pkt zamiast 37,
        // więc nagłówek skakał o 0,5 pkt przy zmianie karty.
        .frame(height: 38, alignment: .top)
    }

    static func defaultTab(for item: SessionItem) -> MeetingTab {
        .summary
    }

    @ViewBuilder static func modelsSheet(for item: SessionItem, state: MeetingViewState) -> some View {
        switch state.tab ?? defaultTab(for: item) {
        case .transcript: TranscriptModelsSheet(item: item) { state.modelsSheet = false }
        case .summary: SummaryModelsSheet(item: item, state: state) { state.modelsSheet = false }
        case .myNotes: EmptyView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { model.selectedSessionID = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.pillSmall)
                    .help("Back to Meetings")
                    .accessibilityLabel("Back to Meetings")
                TextField("Untitled meeting", text: titleField)
                    .textFieldStyle(.plain)
                    .documentTitle()
                    .fixedSize(horizontal: false, vertical: true)
                    .onSubmit {
                        if let edit = state.titleEdit, NoteTitle.isEdit(edit, meta: item.notes.meta, noteTitle: item.notes.summary?.title) {
                            model.notes.setManualTitle(edit, for: item)
                        }
                        state.titleEdit = nil
                    }
                    .disabled(model.recordingsMove != nil)
                Menu {
                    if (state.tab ?? defaultTab) == .transcript {
                        Button("Transcript options…") { state.modelsSheet = true }
                        DetectSpeakersMenu(support: model.speakerModel, state: speakerMenu, item: item)
                    }
                    Button("Copy notes") { model.copyNotes(item) }.disabled(item.notes.summary == nil)
                    Button("Show in Finder") { model.showInFinder(item) }
                    Divider()
                    Button("Delete meeting…", role: .destructive) { model.pendingDelete = item.id }.disabled(!model.canDelete(item))
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .fixedSize()
                .help("More").accessibilityLabel("More")
                .modifier(SpeakerMenuDialogs(support: model.speakerModel, state: speakerMenu, item: item))
            }
            HStack(spacing: 12) {
                MetaLine([
                    item.startedAt.formatted(date: .abbreviated, time: .shortened),
                    item.duration.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) } ?? "",
                    model.presetFor(sessionURL: item.url).map { String(localized: "Preset \($0.name)") } ?? "",
                    item.audioDeletedAfterDays.map { String(format: NSLocalizedString("Audio deleted after %lld days", comment: ""), locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"), Int64($0)) } ?? "",
                ])
                if model.notes.isTitling(item.id) { StateLabel(.progress(nil), String(localized: "Naming the meeting…")) }
                ForEach(item.trackProblems, id: \.trackID) { problemButton($0) }
            }
            HStack(spacing: 12) {
                EventPickerChip(item: item)
                FolderChip(item: item)
                EventAttendeesLine(link: item.notes.meta.calendarEvent)
            }
            // R3: na czas przenoszenia folderu nagrań spotkanie jest tylko do odczytu.
            if model.recordingsMove != nil { StateLabel(.progress(nil), String(localized: "Moving recordings…")) }
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
        if playback.player?.isPlaying == true {
            playback.stop()
        } else if playback.player != nil || load("system"), playback.player?.play() == true {
            playback.started(index: nil, seconds: nil)
        }
    }

    /// ChatGPT #8: „Me" nie ma w pliku odsłuchu (to tap systemowy) — gramy tor mikrofonu,
    /// przeliczając czas sesji na czas tej ścieżki. TASK-109: gra tylko ten segment; klik grającego = pauza.
    private func play(_ index: Int, _ u: Utterance) {
        if playback.playing == index, playback.player?.isPlaying == true { playback.stop(); return }
        let aecOK = item.summary?.tracks.first { $0.id == "mic_aec" }.map { $0.failure == nil && $0.channels > 0 } ?? false
        let track = u.speaker == .them ? "system" : (aecOK ? "mic_aec" : "mic_raw")
        let offset = item.summary?.tracks.first { $0.id == track }?.offsetSeconds ?? 0
        guard playback.track == track || load(track), let player = playback.player else { return }
        let window = Self.segmentWindow(start: u.start, end: u.end, offset: offset, fileDuration: player.duration)
        guard window.to > window.from else { return }
        player.currentTime = window.from
        guard player.play() else { return }
        playback.started(index: index, seconds: window.to - window.from)
    }

    /// Okno segmentu na osi pliku toru: oba końce przesunięte o offset toru, przycięte do [0, długość pliku];
    /// 0,5 s tylko dla segmentu bez długości (`end <= start`).
    /// shortcut: stały offset toru, bez dryfu kotwic zegara z `Merger`; poprawić, jeśli koniec segmentu słyszalnie się rozjedzie.
    static func segmentWindow(start: Double, end: Double, offset: Double, fileDuration: Double) -> (from: Double, to: Double) {
        let from = min(max(0, start - offset), fileDuration)
        let to = max(from, min((end > start ? end : start + 0.5) - offset, fileDuration)) // segment cały przed startem toru = puste okno
        return (from, to)
    }

    /// Nieudane wczytanie nie zostaje zapamiętane jako wczytana ścieżka (check S15 #4).
    /// Audio usunięte przez retencję to stan („Recording deleted” w wierszu), nie błąd.
    private func load(_ track: String) -> Bool {
        guard item.audioDeletedAfterDays == nil else { return false }
        do {
            playback.player = try AVAudioPlayer(contentsOf: item.url.appendingPathComponent("\(track).caf"))
            playback.track = track
            return true
        } catch {
            playback.stop()
            playback.player = nil
            playback.track = nil
            let ns = error as NSError
            let why = ns.domain == NSOSStatusErrorDomain ? OSStatusText.describe(ns.code) : error.localizedDescription
            model.lastError = String(localized: "Couldn't open the \(track) recording: \(why)")
            return false
        }
    }

    /// Start < 0 = mowa przed osią sesji (mikrofon ruszył wcześniej niż tap systemowy) — pokazujemy 0:00:00.
    static func time(_ s: Double) -> String { MeetingArchive.time(s) }
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
/// TASK-109: na hover ▶/⏸ (gra ten segment) i ołówek (ręczna poprawka tekstu w edytorze pod spodem).
struct UtteranceRow: View {
    let utterance: Utterance
    let isAuto: Bool
    var item: SessionItem? = nil
    var speakerNumber: Int? = nil
    var isPlaying = false
    var isEdited = false
    /// Szkic poprawki, gdy ten wiersz jest edytowany.
    var draft: Binding<String>? = nil
    /// `nil` = edycja niedostępna (brak przebiegu, przenoszenie nagrań).
    var onStartEdit: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onCancel: () -> Void = {}
    let onJump: () -> Void
    /// TASK-119: ukrywanie. `nil` = akcja niedostępna (brak przebiegu, przenoszenie nagrań).
    var isSelected = false
    var deleteCount = 1
    var onDelete: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    /// ⌘-klik (`command`) albo ⇧-klik (`shift`) na wierszu.
    var onSelect: ((_ command: Bool, _ shift: Bool) -> Void)? = nil
    @Environment(AppModel.self) private var model
    @StateObject private var picker = RowPresentation()
    @FocusState private var editorFocused: Bool

    /// Audio usunięte przez retencję: odtwarzanie wyłączone z wyjaśnieniem zamiast błędu.
    private var deletedHelp: String? { item?.audioDeletedAfterDays.map { "Recording deleted after \($0) days" } }

    static func speakerNumbers(_ transcript: Transcript) -> [String: Int] { SpeakerLabels.numbers(for: transcript) }

    /// Kolor „Speaker N” — ten sam w transkrypcie i w notatce. Bez .mnAccent: ten kolor ma „Me”.
    static func color(number: Int) -> Color {
        let colors: [Color] = [Color(nsColor: .systemOrange), Color(nsColor: .systemBlue), Color(nsColor: .systemPurple), Color(nsColor: .systemBrown),
                               Color(nsColor: .systemPink), Color(nsColor: .systemTeal), .mnRec, Color(nsColor: .systemIndigo)]
        return colors[((number - 1) % colors.count + colors.count) % colors.count] // numer z linku bywa dowolny
    }

    private var speakerColor: Color {
        utterance.speaker == .me ? .mnAccent : speakerNumber.map(Self.color(number:)) ?? .mnText
    }

    private var displaySpeakerName: String {
        if utterance.speaker == .me { return String(localized: "Me") }
        if let key = utterance.speakerKey, let name = item?.speakers?.names?[key] { return name }
        if let number = speakerNumber { return String(localized: "Speaker \(number)") }
        return String(localized: "Them")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Button(MeetingDetailView.time(utterance.start), action: onJump)
                .buttonStyle(.plain)
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(.mnText2)
                .frame(width: 72, alignment: .leading)
                .disabled(deletedHelp != nil)
                .help(deletedHelp ?? String(localized: "Play segment"))
                .accessibilityLabel("Play segment from \(MeetingDetailView.time(utterance.start))")
            Group {
                if utterance.speaker == .them, let key = utterance.speakerKey, let item, let number = speakerNumber {
                    Button(displaySpeakerName) { picker.isPresented = true }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Speaker \(number), rename")
                        .popover(isPresented: $picker.isPresented) {
                            SpeakerPicker(attendees: item.notes.meta.calendarEvent?.attendees ?? [],
                                          known: KnownPeople.load(root: model.paths.root).names,
                                          currentName: item.speakers?.names?[key], number: number) { name in
                                model.renameSpeaker(item: item, key: key, name: name)
                                picker.isPresented = false
                            }
                        }
                } else {
                    Text(displaySpeakerName)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(speakerColor)
            .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if let draft {
                    editor(draft)
                } else {
                    Text(utterance.text).font(.system(size: 13)).lineSpacing(4)
                        .strikethrough(utterance.hidden == true, color: .mnText2)
                        .foregroundStyle(utterance.excludedFromNotes ? Color.mnText2 : Color.mnText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let lang = utterance.languageMismatch {
                    // P11: widoczne, nie ukryte — i wyłączone z notatek.
                    WarnLabel(isAuto ? String(localized: "Unexpected alphabet (\(lang.rawValue.uppercased())) — likely misrecognized, excluded from notes")
                                     : String(localized: "Looks like \(lang.rawValue.uppercased()), not the preset's language — excluded from notes"))
                }
                if let onRestore {
                    HStack(spacing: 8) {
                        StateLabel(.neutral, String(localized: "Deleted — not in notes, search or copy"))
                        Button(String(localized: "Restore"), action: onRestore).buttonStyle(.pillSmall)
                    }
                }
                if utterance.echoOfThem == true {
                    StateLabel(.neutral, String(localized: "Echo of the other side — excluded from notes"))
                }
                if utterance.approximateTiming {
                    StateLabel(.neutral, String(localized: "Approximate timing"))
                }
                if isEdited, draft == nil {
                    StateLabel(.neutral, String(localized: "Edited"))
                }
            }
            actions
        }
        .padding(.vertical, 11)
        .background(isSelected ? Color.mnAccent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onHover { picker.hovering = $0 }
        // TASK-119: ⌘/⇧-klik zaznacza; zwykły klik dalej zaznacza tekst.
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded { onSelect?(true, false) })
        .simultaneousGesture(TapGesture().modifiers(.shift).onEnded { onSelect?(false, true) })
        .contextMenu {
            if let onDelete { Button(deleteTitle, action: onDelete) }
            if let onRestore { Button(String(localized: "Restore"), action: onRestore) }
        }
        // Ikony są tylko na hover — VoiceOver i klawiatura dostają te same akcje nazwane na wierszu.
        .accessibilityAction(named: isPlaying ? "Pause" : "Play segment") { if deletedHelp == nil { onJump() } }
        .accessibilityActions {
            if let onStartEdit { Button("Edit transcript", action: onStartEdit) }
            if let onDelete { Button(deleteTitle, action: onDelete) }
            if let onRestore { Button(String(localized: "Restore"), action: onRestore) }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var deleteTitle: String {
        deleteCount > 1 ? String.localizedStringWithFormat(NSLocalizedString("Delete %lld segments", comment: ""), Int64(deleteCount))
            : String(localized: "Delete segment")
    }

    /// Stała szerokość: pojawienie się ikon na hover nie przesuwa tekstu.
    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onJump) { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                .disabled(deletedHelp != nil)
                .help(deletedHelp ?? (isPlaying ? String(localized: "Pause") : String(localized: "Play segment")))
                .accessibilityLabel(isPlaying ? "Pause" : "Play segment")
            if let onStartEdit, draft == nil {
                Button(action: onStartEdit) { Image(systemName: "pencil") }
                    .help("Edit transcript")
                    .accessibilityLabel("Edit transcript")
            }
            if let onDelete, draft == nil {
                Button(action: onDelete) { Image(systemName: "trash") }
                    .help(deleteTitle)
                    .accessibilityLabel(deleteTitle)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12)).foregroundStyle(.mnText2)
        .frame(width: 64, alignment: .trailing)
        .opacity(picker.hovering || isPlaying ? 1 : 0)
        .allowsHitTesting(picker.hovering || isPlaying)
    }

    /// Esc = Cancel, ⌘↩ = Save; zwykły Return to nowa linia. Jeden edytor naraz (`MeetingViewState.segmentDraft`).
    private func editor(_ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: text)
                .font(.system(size: 13)).lineSpacing(4)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(.horizontal, 4).padding(.vertical, 6)
                .frame(minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.mnCard))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mnLine2, lineWidth: 1))
                .accessibilityLabel("Segment text")
                .onAppear { editorFocused = true }
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel).buttonStyle(.pillSmall).keyboardShortcut(.cancelAction)
                Button("Save") { onSave?() }.buttonStyle(.pillSmallPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(onSave == nil || text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("⌘↩ saves").font(.callout).foregroundStyle(.mnText2)
            }
        }
    }
}

private final class RowPresentation: ObservableObject {
    @Published var isPresented = false
    @Published var hovering = false
}
