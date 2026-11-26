import AVFoundation
import YascribeNotes
import YascribeProviders
import YascribeRecording
import YascribeTranscription
import SwiftUI

/// Pozycja odtwarzania (oś sesji, sekundy) osobno od `PlaybackState`: tyka ~20 razy na sekundę i odświeża tylko pasek, nie listę wierszy.
@MainActor final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
    /// Wartość suwaka w trakcie przeciągania; `nil` poza nim.
    @Published var scrub: Double?
}

/// Odtwarzanie: odsłuch = ścieżka systemowa bit w bit (spec rdzenia §5); mikrofon osobno.
/// TASK-131: segment gra od startu i dalej przez kolejne (łańcuch) aż do pauzy; `current` = wiersz w `utterances`, który gra albo był ostatni.
@MainActor final class PlaybackState: ObservableObject {
    struct Segment { let entry: TranscriptPlaylist.Entry; let fileFrom: Double; let fileTo: Double; let sessionFrom: Double }

    var player: AVAudioPlayer?
    var track: String?
    let clock = PlaybackClock()
    @Published private(set) var current: Int?
    @Published private(set) var isPlaying = false
    /// Wiersz z ikoną „pauza”: tylko grający.
    var playing: Int? { isPlaying ? current : nil }
    private(set) var segment: Segment?
    /// Koniec okna segmentu (albo pliku przy odsłuchu całości): widok wybiera następny segment albo kończy.
    var onSegmentEnd: (() -> Void)?
    private var ticker: Task<Void, Never>?

    /// Nowy segment zastępuje poprzedni; ticker stary kończy się sam (zadanie anulowane, a wszystko jest na MainActor).
    func began(_ entry: TranscriptPlaylist.Entry, fileFrom: Double, fileTo: Double, sessionFrom: Double) {
        segment = Segment(entry: entry, fileFrom: fileFrom, fileTo: fileTo, sessionFrom: sessionFrom)
        current = entry.row
        isPlaying = true
        clock.position = sessionFrom
        startTicker()
    }

    /// Menu Meeting bez transkryptu: gra cały tor od bieżącego miejsca do pauzy.
    func beganWholeTrack() {
        segment = nil
        current = nil
        isPlaying = true
        startTicker()
    }

    func pause() {
        ticker?.cancel()
        ticker = nil
        player?.pause()
        isPlaying = false
    }

    /// Koniec łańcucha: zaznaczenie znika, pasek stoi na `position`.
    func finish(position: Double? = nil) {
        pause()
        segment = nil
        current = nil
        if let position { clock.position = position }
    }

    /// Tylko do migawek.
    func previewPlaying(row: Int, position: Double) {
        current = row
        isPlaying = true
        clock.position = position
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard let player else { return }
        guard let s = segment else {
            clock.position = player.currentTime
            if !player.isPlaying { finish() }
            return
        }
        if player.currentTime >= s.fileTo - 0.03 || !player.isPlaying {
            onSegmentEnd?()
        } else {
            clock.position = s.sessionFrom + (player.currentTime - s.fileFrom)
        }
    }
}

/// Widok spotkania (spec 1.5 §5.2): tytuł, chipy i zakładki My notes / Transcript / Summary.
/// Podczas nagrania tylko My notes — reszta powstaje po spotkaniu.
struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    let presentsModelsSheet: Bool
    let bottomInset: CGFloat
    @StateObject private var playback: PlaybackState
    @StateObject private var state: MeetingViewState
    @StateObject private var speakerMenu = SpeakerMenuState()

    init(item: SessionItem, state: MeetingViewState = MeetingViewState(), playback: PlaybackState = PlaybackState(), presentsModelsSheet: Bool = true, bottomInset: CGFloat = 0) {
        self.item = item
        self.presentsModelsSheet = presentsModelsSheet
        self.bottomInset = bottomInset
        _state = StateObject(wrappedValue: state)
        _playback = StateObject(wrappedValue: playback)
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
                    case .transcript: TranscriptTab(state: state, item: item, playing: playback.playing, current: playback.current) { play($0, $1) }
                    case .summary: SummaryTab(state: state, item: item)
                    }
                }
            }
            .contentMargins(.bottom, bottomInset + (playerList == nil ? 0 : Self.playerHeight), for: .scrollContent)
            // TASK-131: player przypięty u dołu (jak pasek Ask nad nim), nie przewija się z listą.
            .overlay(alignment: .bottom) {
                if let list = playerList {
                    PlayerBar(clock: playback.clock, isPlaying: playback.isPlaying, duration: list.duration,
                              onToggle: { togglePlayback(list) }, onSeek: { seek($0, list) })
                        .padding(.horizontal, 28)
                        .frame(maxWidth: 640)
                        .padding(.bottom, bottomInset + 10)
                }
            }
        }
        .dismissibleSheet(isPresented: Binding(get: { presentsModelsSheet && state.modelsSheet },
                                               set: { state.modelsSheet = $0 }), onDismiss: { state.modelsSheet = false }) {
            Self.modelsSheet(for: item, state: state)
        }
        .background(Color.mnCard)
        // Uwaga 7 pkt 5: przycisk ▶II zniknął z paska (nie wynika z §11.5); odtwarzanie jest w menu Meeting.
        .focusedSceneValue(\.playRecording, isRecording || item.audioDeletedAfterDays != nil ? nil : { togglePlayback(playlist()) })
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
                .modifier(VoiceConsentAlert())
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

    static let playerHeight: CGFloat = 54

    /// Lista dla paska: tylko w zakładce Transcript, gdy jest co grać i audio istnieje.
    private var playerList: TranscriptPlaylist? {
        guard !isRecording, (state.tab ?? defaultTab) == .transcript, item.audioDeletedAfterDays == nil else { return nil }
        let list = playlist()
        return list.entries.isEmpty ? nil : list
    }

    /// Lista odtwarzania z tego samego transkryptu co widok (z ukrytymi, więc wiersze zgadzają się z indeksami ▶).
    private func playlist() -> TranscriptPlaylist {
        model.transcript(of: item, corrected: state.useCorrected, includeHidden: true).map(TranscriptPlaylist.init) ?? .empty
    }

    /// Menu Meeting i ▶ na pasku: pauza albo gra dalej od zapamiętanej pozycji (za końcem — od początku).
    private func togglePlayback(_ list: TranscriptPlaylist) {
        if playback.isPlaying { playback.pause(); return }
        guard let first = list.start(at: playback.clock.position) ?? list.entries.first.map({ ($0, $0.start) }) else {
            // Bez transkryptu: cały tor systemowy od bieżącego miejsca.
            if playback.player != nil || load("system"), playback.player?.play() == true { playback.beganWholeTrack() }
            return
        }
        chain(list, first)
    }

    /// ▶ na wierszu: gra grający wiersz = pauza; inny startuje od jego początku i leci dalej.
    private func play(_ row: Int, _ list: TranscriptPlaylist) {
        if playback.isPlaying, playback.current == row { playback.pause(); return }
        guard let e = list.entry(row: row) else { return }
        chain(list, (e, e.start))
    }

    /// Przeciągnięcie paska: gra od `t` (w ciszy — od najbliższej następnej wypowiedzi).
    private func seek(_ t: Double, _ list: TranscriptPlaylist) {
        guard let first = list.start(at: t) else { playback.finish(position: list.duration); return }
        chain(list, first)
    }

    /// Startuje `first` i po każdym końcu okna bierze następny wpis.
    /// shortcut: lista z chwili startu — ukrycie wiersza w trakcie odtwarzania działa od następnego ▶; poprawić, gdy będzie to przeszkadzać.
    private func chain(_ list: TranscriptPlaylist, _ first: (entry: TranscriptPlaylist.Entry, from: Double)?) {
        playback.onSegmentEnd = {
            guard let cur = playback.segment?.entry else { return playback.finish() }
            chain(list, list.next(after: cur, cursor: cur.end))
        }
        var next = first
        while let (e, from) = next {
            if begin(e, from: from) { return }
            next = list.next(after: e, cursor: e.end) // segment bez dźwięku w pliku toru: dalej
        }
        playback.finish(position: list.duration)
    }

    /// ChatGPT #8: „Me" nie ma w pliku odsłuchu (to tap systemowy) — gramy tor mikrofonu,
    /// przeliczając czas sesji na czas tej ścieżki.
    private func begin(_ e: TranscriptPlaylist.Entry, from: Double) -> Bool {
        let aecOK = item.summary?.tracks.first { $0.id == "mic_aec" }.map { $0.failure == nil && $0.channels > 0 } ?? false
        let track = e.speaker == .them ? "system" : (aecOK ? "mic_aec" : "mic_raw")
        let offset = item.summary?.tracks.first { $0.id == track }?.offsetSeconds ?? 0
        guard playback.track == track || load(track), let player = playback.player else { return false }
        let window = Self.segmentWindow(start: from, end: e.end, offset: offset, fileDuration: player.duration)
        guard window.to > window.from else { return false }
        player.currentTime = window.from
        guard player.play() else { return false }
        playback.began(e, fileFrom: window.from, fileTo: window.to, sessionFrom: from)
        return true
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
            playback.finish()
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
    /// Wiersz z pozycją odtwarzania (TASK-131): delikatne podświetlenie.
    var isCurrent = false
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
                    let recognized = model.voiceRecognition(item, key: key)
                    Button { picker.isPresented = true } label: {
                        HStack(spacing: 3) {
                            Text(displaySpeakerName)
                            if recognized != nil { Image(systemName: "waveform").font(.system(size: 9)) }
                        }
                    }
                        .buttonStyle(.plain)
                        .help(recognized.map { _ in String(localized: "Recognized by voice") } ?? String(localized: "Speaker \(number), rename"))
                        .accessibilityLabel("Speaker \(number), rename")
                        .popover(isPresented: $picker.isPresented) {
                            let options = model.speakerMergeOptions(item, key: key)
                            SpeakerPicker(attendees: item.notes.meta.calendarEvent?.attendees ?? [],
                                          known: KnownPeople.load(root: model.paths.root).names,
                                          currentName: item.speakers?.names?[key], number: number, recognized: recognized,
                                          others: options.others, merged: options.merged,
                                          merge: { model.mergeSpeaker(item: item, key: key, into: $0); picker.isPresented = false },
                                          split: { model.splitSpeaker(item: item, original: $0); picker.isPresented = false }) { name in
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StateLabel(.neutral, String(localized: "Deleted — left out of copy, search and new notes")).wrapping()
                        Button(String(localized: "Restore"), action: onRestore).buttonStyle(.pillSmall).fixedSize()
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
        .background(isSelected ? Color.mnAccent.opacity(0.12) : isCurrent ? Color.mnAccent.opacity(0.06) : Color.clear)
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

/// TASK-131: ▶/⏸ i pasek postępu nad listą wypowiedzi; przeciągnięcie przewija (start po puszczeniu suwaka).
struct PlayerBar: View {
    @ObservedObject var clock: PlaybackClock
    let isPlaying: Bool
    let duration: Double
    let onToggle: () -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        let shown = min(clock.scrub ?? clock.position, duration)
        HStack(spacing: 10) {
            Button(action: onToggle) { Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(width: 16) }
                .buttonStyle(.plain)
                .help(isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
            Text(MeetingDetailView.time(shown)).monospacedDigit().frame(width: 60, alignment: .trailing)
            Slider(value: Binding(get: { shown }, set: { clock.scrub = $0 }), in: 0...max(duration, 1)) { editing in
                if !editing, let t = clock.scrub { clock.scrub = nil; clock.position = t; onSeek(t) }
            }
            .controlSize(.small)
            .accessibilityLabel("Playback position")
            Text(MeetingDetailView.time(duration)).monospacedDigit().frame(width: 60, alignment: .leading)
        }
        .font(.system(size: 12)).foregroundStyle(.mnText2)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Color.mnCard))
        .overlay(Capsule().stroke(Color.mnLine2, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}
