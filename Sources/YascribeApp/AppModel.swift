import AppKit
import AVFoundation
import Foundation
import YascribeDictation
import YascribeLocalASR
import YascribeMeetings
import YascribeNotes
import YascribeProviders
import YascribeRecording
import YascribeSessionFormat
import YascribeTranscription
import YascribeUpdates
import Observation

enum Section: String, CaseIterable, Identifiable {
    case meetings = "Meetings", tasks = "Tasks", dictation = "Dictation", dictionary = "Dictionary"
    case presets = "Presets", templates = "Templates", settings = "Settings"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meetings: String(localized: "Meetings")
        case .tasks: String(localized: "Tasks")
        case .dictation: String(localized: "Dictation")
        case .dictionary: String(localized: "Dictionary")
        case .presets: String(localized: "Presets")
        case .templates: String(localized: "Templates")
        case .settings: String(localized: "Settings")
        }
    }
    var symbol: String {
        switch self {
        case .meetings: "waveform"
        case .tasks: "checklist"
        case .dictation: "keyboard"
        case .dictionary: "book"
        case .presets: "slider.horizontal.3"
        case .templates: "doc.text"
        case .settings: "gearshape"
        }
    }
}

struct SessionNotes: Equatable { var myNotes = ""; var meta = NoteMeta(); var summary: NoteSummary?; var problems: [String] = [] }

/// Jedna sesja na osi czasu strony głównej.
struct SessionItem: Identifiable, Equatable {
    var id: String { url.lastPathComponent }
    var url: URL
    var summary: SessionSummary?
    var startedAt: Date
    var transcript: Transcript?
    var progress: Double?
    /// Bieżący przebieg (`RunSelection`, R23): z niego transkrypt, korekta, wyszukiwanie i notatka; „Retry Failed Parts" wznawia ten.
    var runID: String?
    /// Migawka bieżącego przebiegu — język korekty i etykiet (I2); `nil` dla przebiegów bez `run.json` i `input.json`.
    var runSnapshot: RunSnapshot?
    /// Najnowsza próba — do wznowienia po przerwie albo restarcie (ChatGPT #17); bywa inna niż `runID` po „Transcribe again…".
    var latestAttemptID: String?
    /// Najnowsza próba, która nie została bieżącym przebiegiem (trwa, padła, z lukami albo pusta) — baner na karcie Transcript.
    var attemptNotPromoted: RunSelection.Attempt?
    var speakers: SpeakerDiarization?
    var corrected: CorrectedTranscript?
    var notes = SessionNotes()
    /// Retencja usunęła audio po tylu dniach (`<sesja>/audio-deleted.json`); `nil` = audio nie było kasowane.
    /// Widok spotkania: „Audio deleted after N days”, bez odtwarzania i ponownej transkrypcji.
    var audioDeletedAfterDays: Int?

    /// Ręczny > auto > tytuł z notatki > „Untitled meeting".
    var title: String { NoteTitle.display(meta: notes.meta, noteTitle: notes.summary?.title) }
    var displayTitle: String { NoteTitle.sourceTitle(meta: notes.meta, noteTitle: notes.summary?.title) ?? String(localized: "Untitled meeting") }

    /// Znaczniki `[[SN]]` notatki → bieżące nazwy mówców.
    /// shortcut: numeracja z surowego transkryptu, także gdy notatka powstała z poprawionego; zmienić, jeśli „Speaker N” w notatce
    /// rozjedzie się z transkryptem.
    /// Inne wykrycie mówców niż przy generowaniu (skrót odcinków): te same klucze mogą znaczyć inne osoby, więc bez numeracji
    /// — znaczniki zostają samym „Speaker N” z notatki.
    var speakerMarkers: SpeakerMarkers {
        let current = speakers.map(\.segmentsDigest)
        let sameDetection = current != nil && notes.summary?.speakersDigest == current
        return SpeakerMarkers(keys: notes.summary?.speakers, names: speakers?.names ?? [:],
                              numbers: sameDetection ? transcript.map { SpeakerLabels.numbers(for: $0.withSpeakerLabels(speakers)) } ?? [:] : [:])
    }

    /// Treść notatki z nazwami mówców zamiast znaczników — do schowka i archiwum.
    var notesText: String? { notes.summary.map { speakerMarkers.resolved($0.markdown) } }

    /// Transkrypt do wyświetlenia i streszczenia: poprawiony, gdy jest i użytkownik go nie wyłączył.
    func transcript(corrected useCorrected: Bool) -> Transcript? {
        useCorrected ? (corrected?.transcript ?? transcript) : transcript
    }

    /// Najdłuższy tor: gdy dźwięk systemowy nic nie nagrał (0 klatek), czas liczy się z mikrofonu, nie „0 min".
    var duration: Double? {
        summary?.tracks.compactMap { t in t.frames.flatMap { f in t.sampleRate > 0 ? Double(f) / t.sampleRate : nil } }.max()
    }
}

/// Klucz listy modeli: dostawca + modalność wyjścia (`filter == ""` = lista domyślna).
struct ModelListKey: Hashable { var provider: UUID; var filter: String }

/// Filtr listy spotkań (TASK-26): wszystkie, bez folderu, albo jeden folder.
enum MeetingFilter: Equatable {
    case all
    case unfiled
    case folder(String)

    var folderID: String? { if case .folder(let id) = self { return id }; return nil }
}

@MainActor
@Observable
final class AppModel {
    let paths = YascribePaths.fromEnvironment()
    /// `var` tylko dla testów (atrapa liczy dostępy; TASK-86 R5) — aplikacja zawsze używa pęku kluczy.
    var secrets: any SecretStore = KeychainSecretStore()

    var section: Section = .meetings
    var scrollToDictationSettings = false
    var providers = ProvidersFile()
    var presets = PresetsFile()
    var settings = GlobalSettings() {
        // Zmiana embeddingu czyści indeks archiwum, zmiana modelu odpowiedzi anuluje trwające pytanie (także poza Settings → Save).
        didSet { archive.settingsDidChange(old: oldValue, new: settings) }
    }
    var probeCache = ProbeCache()
    /// Własne polecenia korekty i podsumowania (TASK-96, `prompts.json`). Zapis przez `savePrompts`.
    var prompts = PromptOverrides()
    /// Tabela id modelu -> nazwa z listy dostawcy; zapełnia się przy pobraniu listy modeli.
    var modelNames = ModelNameCache()
    /// Słownik użytkownika (F21): Termy do poleceń, Aliasy do Replacement. Zapis przez `saveDictionary()`.
    var dictionary = UserDictionary() {
        didSet {
            replacementRules = ReplacementRules(dictionary)
            replaced = [:]
            refreshSuggestions()
        }
    }
    /// Sugestie Aliasów (TASK-112) z różnicy surowy → poprawiony transkrypt; liczone w tle przez `refreshSuggestions`.
    var aliasSuggestions: [AliasSuggestion] = []
    /// Odrzucone sugestie (`dictionary-dismissed.json`); zapis przez `dismissSuggestion`.
    private(set) var dismissedSuggestions = Set<String>()
    @ObservationIgnored private var suggestionsGeneration = 0
    /// Reguły skompilowane raz na wersję słownika. Obserwowane: zmiana słownika odświeża otwarte widoki transkryptu.
    private(set) var replacementRules = ReplacementRules(UserDictionary())
    /// Wynik Replacement (klucz: sesja i wariant transkryptu) razem ze źródłem, z którego powstał. Bez obserwacji, bo
    /// zapisywany w trakcie liczenia widoku.
    @ObservationIgnored private var replaced: [ReplacedKey: (source: Transcript, speakers: SpeakerDiarization?, result: Transcript)] = [:]
    private struct ReplacedKey: Hashable { var id: String; var corrected: Bool }
    var sessions: [SessionItem] = []
    var selectedSessionID: String?
    var activePresetID: UUID?
    var lastError: String?
    /// Kalendarz Apple (T7); prośba o dostęp dopiero z przełącznika w Settings.
    let calendarSource: any CalendarSource = EventKitCalendar()
    var showSetup = false
    /// Spotkanie czekające na potwierdzenie usunięcia (przycisk „⋯” i menu Meeting) — dialog jest w `MeetingDetailView`.
    var pendingDelete: String?
    /// Foldery spotkań (TASK-26): `folders.json`; brak pliku = brak folderów, stare sesje są „No folder".
    var folders = FoldersFile()
    /// Filtr listy spotkań; sesje w nieistniejącym folderze liczą się jako „No folder".
    var meetingFilter: MeetingFilter = .all
    /// Sesje z trwającym przebiegiem — drugi przebieg tej samej sesji płaciłby za te same okna (check S15 #2).
    private(set) var transcribing: Set<String> {
        get { notes.transcribing }
        set { notes.transcribing = newValue }
    }
    /// Wykrywanie mówców w toku (TASK-22 R05): bilet na sesję = sesja zajęta, wiersz „Detecting speakers…” i bramka zapisu.
    private(set) var speakerTickets: [String: SpeakerDetectionTicket] = [:]
    @ObservationIgnored private var speakerTasks: [String: Task<SpeakerDiarization, any Error>] = [:]
    @ObservationIgnored private var speakerGeneration = 0
    @ObservationIgnored var diarizationHTTP: any HTTPClient = URLSessionHTTPClient()
    @ObservationIgnored var speakerWorkOverride: (@Sendable () async throws -> SpeakerDiarization)?

    let recording = RecordingController()
    /// Aktualizacje (Sparkle): bramka restartu i kontroler. Tworzone w `init` (bramka potrzebuje `self`).
    @ObservationIgnored private(set) var updateGate: RestartGate!
    @ObservationIgnored private(set) var updater: UpdateController!
    /// Użytkownik już potwierdził zakończenie z nagraniem w toku (menu paska i `applicationShouldTerminate` nie pytają dwa razy).
    @ObservationIgnored private var quitApproved = false
    /// Wykrywanie spotkań (faza 1.6); startuje `YascribeApp.init`, nie `AppModel.init` (migawki i testy go nie chcą).
    let monitor = MeetingMonitor()
    let notes = NotesModel()
    /// Indeks archiwum i „Ask anything" (TASK-21/24); podłączany w `init`.
    let archive = ArchiveModel()
    /// Lokalny ASR (F20): magazyn i faza pobierania/przygotowania — po jednym na wariant (kolejność = karty w Settings).
    let localASRModels: [LocalASRSupport]
    /// Model wykrywania mówców (TASK-22): status i pobieranie dla karty w Settings i menu ⋯ Transcript.
    let speakerModel: SpeakerModelSupport

    /// `nil` = nieznany model lokalny; pusty = v3 (jak `LocalASRVariant(model:)`).
    func localASR(_ model: String) -> LocalASRSupport? {
        LocalASRVariant(model: model).flatMap { v in localASRModels.first { $0.store.variant == v } }
    }

    /// Do uruchomień (spotkanie, wznowienie, sonda, dyktowanie): nieznany model = v3, bo tak szły przebiegi sprzed wariantów —
    /// ich migawki niosą odcisk v3 i muszą się dać wznowić. Ścisłe `localASR(_:)` zostaje dla UI (ostrzeżenie).
    func localASRForRun(_ model: String) -> LocalASRSupport { localASR(model) ?? localASR("")! }

    /// Dyktowanie: powstaje w `load()` (historia), skrót startuje `YascribeApp.init` obok `monitor`.
    @ObservationIgnored lazy var dictation = DictationController(model: self)

    /// `nil` = prawdziwy `FluidAudioEngine`; testy podają atrapę, żeby przejść przez okna bez modelu.
    @ObservationIgnored private let localASREngine: (@Sendable (ModelStore) -> any LocalASREngine)?

    init(localASRModels: [LocalASRSupport]? = nil, localASREngine: (@Sendable (ModelStore) -> any LocalASREngine)? = nil) {
        self.localASREngine = localASREngine
        speakerModel = SpeakerModelSupport(store: DiarizerModelStore(directory: DiarizerModelStore.directory(root: paths.root)))
        self.localASRModels = localASRModels ?? LocalASRVariant.allCases.map { LocalASRSupport(store: ModelStore(variant: $0)) }
        recording.model = self
        monitor.model = self
        updateGate = RestartGate(activity: self)
        updateGate.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            recording.updatePending = phase == .restartPostponed
            if phase == .restartPostponed { announceUpdatePostponed() }
        }
        // Sparkle startuje tylko w prawdziwym uruchomieniu i z prawdziwym kluczem (placeholder do T8 wywołałby błąd przy starcie).
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        updater = UpdateController(gate: updateGate, start: !LegacyMigration.isDevRun && key != nil && key != "REPLACE_WITH_PUBLIC_KEY")
        load()
        // ChatGPT #16: setup także wtedy, gdy dźwięk systemowy nigdy nie przeszedł testu tonem.
        showSetup = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || !UserDefaults.standard.bool(forKey: "systemAudioVerified")
        notes.clientFor = { [weak self] in self?.client(for: $0) }
        notes.presetFor = { [weak self] in self?.presetFor(sessionURL: $0) }
        notes.knownProviderIDs = { [weak self] in Set(self?.providers.providers.map(\.id) ?? []) }
        notes.report = { [weak self] in self?.lastError = $0 }
        notes.presetsInfo = { [weak self] in (self?.presets.presets ?? [], self?.settings.defaultPresetID) }
        notes.summaryThinking = { [weak self] in self?.settings.summaryThinkingEnabled ?? true }
        notes.dictionary = { [weak self] in self?.dictionary ?? UserDictionary() }
        notes.replacementRules = { [weak self] in self?.replacementRules ?? ReplacementRules(UserDictionary()) }
        notes.prompts = { [weak self] in self?.prompts ?? PromptOverrides() }
        notes.fillerWords = { [weak self] in
            guard let s = self?.settings, s.removeFillersEnabled else { return [] }
            return s.fillerWords ?? FillerWords.defaults
        }
        notes.onChange = { [weak self] in self?.reloadSessions() }
        notes.isMoving = { [weak self] in self?.recordingsMove != nil }
        wireArchive()
        applyRetention()
        SpeakerDiarizer.sweepStaleTemporaryFiles(now: Date()) // PCM po przerwanej diaryzacji (R06)
    }

    /// Indeks to dane pochodne: plik leży obok ustawień, a przenoszenie nagrań go nie kopiuje.
    private func wireArchive() {
        archive.indexURL = paths.root.appendingPathComponent("archive-index.json")
        archive.sources = { [weak self] in
            guard let self else { return [] }
            return sessions.map { ArchiveModel.source(for: $0, notes: notes, transcript: transcript(of: $0, corrected: true)) }
        }
        archive.sourceFor = { [weak self] id in
            guard let self, let item = sessions.first(where: { $0.id == id }) else { return nil }
            return ArchiveModel.source(for: item, notes: notes, transcript: transcript(of: item, corrected: true))
        }
        archive.labels = { [weak self] in
            guard let self else { return [:] }
            return Dictionary(sessions.map { item in
                (item.id, item.startedAt == .distantPast ? item.title : "\(item.title) · \(item.startedAt.formatted(date: .abbreviated, time: .omitted))")
            }, uniquingKeysWith: { first, _ in first })
        }
        archive.embedding = { [weak self] in self?.settings.embedding }
        archive.askModel = { [weak self] in self?.settings.askModel }
        archive.makeClient = { [weak self] id in
            self?.makeClient(for: id) ?? .failure(ClientProblem(message: "This provider is no longer available."))
        }
        archive.providerFor = { [weak self] id in self?.provider(id) }
        archive.isMoving = { [weak self] in self?.recordingsMove != nil }
        archive.report = { [weak self] in self?.lastError = $0 }
        archive.chatsURL = paths.root.appendingPathComponent("chats", isDirectory: true)
        // Zakres nowej rozmowy dziedziczy miejsce użytkownika: otwarte spotkanie, filtr folderu / bez folderu albo całe archiwum.
        archive.captureScope = { [weak self] in
            guard let self else { return .all }
            if let id = selectedSessionID, sessions.contains(where: { $0.id == id }) { return .meeting(id) }
            switch meetingFilter {
            case .all: return .all
            case .unfiled: return .unfiled
            case .folder(let id): return .folder(id)
            }
        }
        archive.resolveSavedScope = { [weak self] ref in
            guard let self else { return nil }
            return ref.resolve(sessions: sessions, folderID: { $0.notes.meta.folderID },
                               folderName: { folders.folder($0)?.name })
        }
        archive.resolveScope = { [weak self] scope in
            guard let self else { return nil }
            let label = switch meetingFilter {
            case .all: "All meetings"
            case .unfiled: "No folder"
            case .folder(let id): folders.folder(id)?.name ?? "No folder"
            }
            return ArchiveModel.resolve(scope, sessions: sessions, matches: matchesFilter,
                                        listLabel: label, selectedID: selectedSessionID)
        }
    }

    var activePreset: Preset? {
        presets.presets.first { $0.id == (activePresetID ?? settings.defaultPresetID) } ?? presets.presets.first
    }

    func provider(_ id: UUID?) -> Provider? { providers.providers.first { $0.id == id } }

    /// Każdy plik osobno (przegląd S18 §2.1): `save()` pisze wszystkie cztery, więc nieodczytany plik
    /// odkładamy na bok jako `<nazwa>.corrupt-<data>`, zanim domyślna wartość go nadpisze.
    func load() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        var errors: [String] = []
        func read<T: Decodable>(_ url: URL, _ fallback: T) -> T {
            do { return try JSONFile.load(T.self, from: url, default: fallback) } catch {
                let name = url.lastPathComponent
                let aside = url.deletingLastPathComponent().appendingPathComponent("\(name).corrupt-\(stamp)")
                // ponytail: gdy przeniesienie się nie uda, najbliższy save() nadpisze plik — blokada zapisu per plik, jeśli to się zdarzy
                let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
                let detail = String(describing: error)
                errors.append(moved
                    ? String(localized: "Couldn't read \(name) (moved to \(aside.lastPathComponent)): \(detail)")
                    : String(localized: "Couldn't read \(name) (couldn't move it aside): \(detail)"))
                return fallback
            }
        }
        providers = read(paths.providers, ProvidersFile())
        // Model Yascribe nie jest wierszem listy Providers, ale presety trzymają jego rekord — nie może go zabraknąć (F20 P3).
        if providers.ensureOnDeviceProvider() {
            do { try JSONFile.save(providers, to: paths.providers) } catch { errors.append(String(localized: "Couldn't save providers.json: \(String(describing: error))")) }
        }
        presets = read(paths.presets, PresetsFile())
        settings = read(paths.settings, GlobalSettings())
        probeCache = read(paths.probeCache, ProbeCache())
        let loadedPrompts = PromptStore.load(from: paths.prompts)
        prompts = loadedPrompts.overrides
        if let problem = loadedPrompts.problem { errors.append(problem) }
        modelNames = read(paths.modelNames, ModelNameCache())
        notes.templates = read(paths.templates, TemplatesFile())
        dismissedSuggestions = read(paths.dismissedSuggestions, Set<String>())
        dictionary = read(paths.dictionary, UserDictionary())
        folders = read(paths.folders, FoldersFile())
        dictation.loadHistory(stamp: stamp, errors: &errors)
        if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
        reloadSessions()
    }

    // MARK: Nagrania: lokalizacja i retencja audio (macos.md §11.5, Recordings)

    /// Folder ze wszystkimi spotkaniami: z ustawień albo `<dane>/sessions`.
    var sessionsDirectory: URL { settings.recordingsPath.map { URL(fileURLWithPath: $0) } ?? paths.sessions }
    /// Postęp trwającego przenoszenia (`nil` = nic się nie przenosi).
    private(set) var recordingsMove: RecordingsMove.Progress?
    /// Wynik ostatniego przenoszenia: `moved` + szczegół (powód błędu albo resztki, których nie dało się usunąć).
    private(set) var recordingsMoveResult: (moved: Bool, detail: String?)?
    /// Rozmiar folderu nagrań w bajtach (nagłówek sekcji); `nil` = jeszcze nie policzony.
    private(set) var recordingsSize: Int64?

    /// Sesje, których katalogi są w użyciu (nagrywanie, transkrypcja, korekta, tytuł, notatka).
    private var busySessions: Set<String> {
        var s = transcribing.union(notes.corrections.sessions).union(notes.titles.sessions)
        // Bilety generowania, także anulowanego: zadanie może jeszcze zapisać notatkę (TASK-25).
        s.formUnion(notes.generatingSessions)
        s.formUnion(speakerTickets.keys)
        if let d = recording.directory { s.insert(d.lastPathComponent) }
        return s
    }

    /// Przebiegi w tle na spotkaniach (transkrypcja, korekta, autotytuł, notatki, mówcy).
    var sessionWorkRunning: Bool {
        !transcribing.isEmpty || !notes.corrections.sessions.isEmpty || !notes.titles.sessions.isEmpty
            || notes.generation.values.contains(.generating) || !speakerTickets.isEmpty
    }

    /// Powód, dla którego teraz nie wolno zmienić lokalizacji; `nil` = wolno.
    var recordingsMoveBlocked: String? {
        RecordingsMove.blocked(recording: recording.isRecording, busy: sessionWorkRunning, moving: recordingsMove != nil).map(localizedProviderMessage)
    }

    /// Przy starcie i po zmianie „Keep audio”. Nie w trybie migawek i nie w trakcie przenoszenia.
    func applyRetention() {
        guard Snapshots.directory == nil, recordingsMove == nil else { return }
        let r = AudioRetention.apply(sessions: sessionsDirectory, days: settings.audioRetentionDays, skip: busySessions,
                                     speakersPins: SpeakerDiarization.knownPins(localPin: DiarizerManifest.pin))
        if !r.errors.isEmpty { lastError = String(localized: "Couldn't delete old audio: \(r.errors.joined(separator: "\n"))") }
        if !r.purged.isEmpty { reloadSessions(); refreshRecordingsSize() }
    }

    /// Skrócenie „Keep audio”, które coś by skasowało, czeka na potwierdzenie (decyzja R1): liczba spotkań i rozmiar
    /// audio z `AudioRetention.plan` — tej samej reguły, której używa `applyRetention`. Dialog w `RecordingsSection`.
    var pendingKeepAudio: (days: Int, meetings: Int, bytes: Int64)?

    /// Wybór w „Keep audio”: gdy nic by nie zniknęło — od razu, inaczej pytanie. `days == nil` = Forever.
    func requestKeepAudio(days: Int?) {
        let plan = AudioRetention.plan(sessions: sessionsDirectory, days: days, skip: busySessions)
        guard let days, !plan.sessions.isEmpty else { setKeepAudio(days: days); return }
        pendingKeepAudio = (days, plan.sessions.count, plan.bytes)
    }

    /// `days == nil` = Forever.
    func setKeepAudio(days: Int?) {
        pendingKeepAudio = nil
        settings.keepAudioForever = days == nil ? true : nil
        settings.keepAudioDays = days
        save()
        applyRetention()
    }

    func refreshRecordingsSize() {
        let dir = sessionsDirectory
        Task.detached {
            let size = RecordingsMove.size(of: dir)
            await MainActor.run { self.recordingsSize = size }
        }
    }

    /// Kopia → weryfikacja → przełączenie i zapis ustawień → usunięcie starych. Przy błędzie nic nie jest usuwane.
    func changeRecordingsLocation(to new: URL) {
        recordingsMoveResult = nil
        let old = sessionsDirectory
        if let reason = recordingsMoveBlocked ?? RecordingsMove.destinationRefusal(from: old, to: new) {
            recordingsMoveResult = (false, localizedProviderMessage(reason))
            return
        }
        notes.flushPendingSaves() // autozapis My notes przed kopią, nie w trakcie (R3)
        recordingsMove = RecordingsMove.Progress(phase: .copying, done: 0, total: 0)
        let isDefault = new.standardizedFileURL.path == paths.sessions.standardizedFileURL.path
        Task.detached {
            let outcome: (Bool, String?)
            do {
                let leftovers = try await RecordingsMove.run(from: old, to: new, progress: { p in
                    Task { @MainActor in if self.recordingsMove != nil { self.recordingsMove = p } }
                }, commit: {
                    try await MainActor.run {
                        let previous = self.settings
                        self.settings.recordingsPath = isDefault ? nil : new.path
                        do { try JSONFile.save(self.settings, to: self.paths.settings) } catch {
                            self.settings = previous
                            throw error
                        }
                    }
                })
                outcome = leftovers.isEmpty
                    ? (true, nil)
                    : (true, String(localized: "Couldn't remove these from the old folder: \(leftovers.joined(separator: ", ")). The copies in the new folder are complete."))
            } catch {
                outcome = (false, "\(error)")
            }
            await MainActor.run {
                self.recordingsMove = nil
                self.updateGate.activityDidChange()
                self.recordingsMoveResult = outcome
                self.reloadSessions()
                self.refreshRecordingsSize()
            }
        }
    }

    func save() {
        do {
            try JSONFile.save(providers, to: paths.providers)
            try JSONFile.save(presets, to: paths.presets)
            try JSONFile.save(settings, to: paths.settings)
            try JSONFile.save(probeCache, to: paths.probeCache)
        } catch {
            lastError = String(localized: "Couldn't save your settings: \(error.localizedDescription)")
        }
    }

    /// Zapis własnych poleceń: stan aktywny zmienia się dopiero po udanym zapisie pliku. `nil` = zapisano, inaczej komunikat.
    func savePrompts(_ new: PromptOverrides) -> String? {
        do {
            try PromptStore.save(new, to: paths.prompts)
            prompts = new
            return nil
        } catch {
            return String(localized: "Couldn't save your prompts: \(error.localizedDescription)")
        }
    }

    @ObservationIgnored private var speakersReloadID = UUID()

    func reloadSessions() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? []
        // Etykiety z poprzedniego odczytu zostają do końca odczytu w tle — bez tego transkrypt i prompt chwilowo tracą litery.
        let previousSpeakers = Dictionary(sessions.compactMap { item in item.runID.map { ("\(item.url.path)|\($0)", item.speakers) } },
                                          uniquingKeysWith: { a, _ in a })
        sessions = dirs.compactMap { url -> SessionItem? in
            let sd = SessionDirectory(url: url)
            guard fm.fileExists(atPath: sd.journalURL.path) else { return nil }
            let summary = try? sd.summarize()
            let run = RunSelection.of(session: url)
            let store = NotesStore(session: url)
            // Echo oznaczamy też na starszych transkryptach (idempotentne, bez zapisu pliku).
            var item = SessionItem(url: url, summary: summary, startedAt: summary?.wallClock ?? .distantPast,
                                   transcript: run.transcript?.echoMarked(), runID: run.currentID)
            item.runSnapshot = run.snapshot
            item.latestAttemptID = run.latestAttemptID
            item.attemptNotPromoted = run.notPromoted
            item.corrected = CorrectedTranscript.load(session: url, runID: run.currentID)
            item.audioDeletedAfterDays = AudioDeletion.read(url)?.afterDays
            item.speakers = run.currentID.flatMap { previousSpeakers["\(url.path)|\($0)"] ?? nil }
            item.notes = SessionNotes(myNotes: store.readMyNotes(), meta: store.readMeta(),
                                      summary: (try? store.readSummary()) ?? nil, problems: store.problems())
            return item
        }.sorted { $0.startedAt > $1.startedAt }
        // Pamięć Replacement: zostają wpisy, których źródło się nie zmieniło (ze świeżą kopią źródła, żeby następne porównanie
        // skończyło się na tożsamości buforów); reszta znika. Czyszczenie wszystkiego przy każdym `onChange` kosztowałoby
        // sekundy na następnym znaku wpisanym w wyszukiwarkę.
        let reloadID = UUID()
        speakersReloadID = reloadID
        let runs = sessions.compactMap { item in item.runID.map { (item.url, $0) } }
        Task {
            let loaded = await Task.detached {
                runs.map { url, runID in
                    (url, runID, SpeakerDiarization.load(run: RunDirectory(session: url, runID: runID),
                        acceptedPins: SpeakerDiarization.knownPins(localPin: DiarizerManifest.pin), currentAudioFingerprint: SpeakerDiarization.audioFingerprint(session: url)))
                }
            }.value
            guard speakersReloadID == reloadID else { return }
            for (url, runID, speakers) in loaded {
                if let index = sessions.firstIndex(where: { $0.url == url && $0.runID == runID }) {
                    sessions[index].speakers = speakers
                }
            }
        }
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        replaced = replaced.reduce(into: [:]) { kept, entry in
            if let fresh = byID[entry.key.id]?.transcript(corrected: entry.key.corrected), fresh == entry.value.source, byID[entry.key.id]?.speakers == entry.value.speakers {
                kept[entry.key] = (fresh, entry.value.speakers, entry.value.result)
            }
        }
        refreshSuggestions()
    }

    /// Przelicza sugestie Aliasów w tle na kopii sesji i słownika; wynik przyjmuje tylko najnowsze wywołanie.
    func refreshSuggestions() {
        suggestionsGeneration += 1
        let generation = suggestionsGeneration
        let sources = sessions.compactMap { item -> AliasSuggestions.Source? in
            guard let raw = item.transcript, let fixed = item.corrected else { return nil }
            return AliasSuggestions.Source(id: item.id, raw: raw, corrected: fixed)
        }
        let dictionary = dictionary, dismissed = dismissedSuggestions, fillers = settings.fillerWords ?? FillerWords.defaults
        guard !sources.isEmpty, !dictionary.terms.isEmpty else { aliasSuggestions = []; return }
        Task {
            let found = await Task.detached(priority: .utility) {
                // Słownik systemowy przez główny wątek (SystemSpelling), więc tylko dla grup po progu i raz na słowo.
                var common: [String: Bool] = [:]
                return AliasSuggestions.find(in: sources, dictionary: dictionary, dismissed: dismissed, fillerWords: fillers) { word in
                    if let known = common[word] { return known }
                    let known = !SystemSpelling.isMisspelled(word)
                    common[word] = known
                    return known
                }
            }.value
            guard generation == suggestionsGeneration else { return }
            aliasSuggestions = found
        }
    }

    /// Add z karty Suggestions: Alias przez ten sam `upsert` co arkusz Terma; `nil` = zapisano, tekst = powód.
    func acceptSuggestion(_ s: AliasSuggestion) -> String? {
        let proposed: UserDictionary
        do { proposed = try AliasSuggestions.accept(s, in: dictionary) } catch {
            return DictionaryEdit.presentation(of: error, draftTerm: s.term).message
        }
        return DictionaryEdit.commit(proposed, replacing: dictionary, set: { dictionary = $0 }, save: saveDictionary)
    }

    /// Ignore: sugestia nie wraca; nieudany zapis cofa zbiór (pamięć nie rozchodzi się z dyskiem).
    func dismissSuggestion(_ s: AliasSuggestion) -> String? {
        let previous = dismissedSuggestions
        dismissedSuggestions.insert(s.id)
        do { try JSONFile.save(dismissedSuggestions, to: paths.dismissedSuggestions) } catch {
            dismissedSuggestions = previous
            return "Couldn't save the dictionary: \(error)"
        }
        aliasSuggestions.removeAll { $0.id == s.id }
        return nil
    }

    /// Jedyny punkt odczytu transkryptu do wyświetlania, wyszukiwania i notatki (F21, D8): `SessionItem.transcript(corrected:)`
    /// po Replacement. Wynik zostaje w pamięci, dopóki źródło jest równe temu, z którego powstał — rewizją jest treść, bo korekta
    /// może zmienić tekst bez zmiany liczby wypowiedzi. Statusy (`!= nil`, „original/corrected") czytają surowe pola.
    func transcript(of item: SessionItem, corrected: Bool) -> Transcript? {
        let rules = replacementRules // odczyt obserwowany także przy trafieniu w pamięć: zmiana słownika odświeża widok
        guard let source = item.transcript(corrected: corrected) else { return nil }
        let key = ReplacedKey(id: item.id, corrected: corrected)
        if let hit = replaced[key], hit.source == source, hit.speakers == item.speakers { return hit.result }
        let result = Replacement.apply(source, rules: rules).withSpeakerLabels(item.speakers)
        replaced[key] = (source, item.speakers, result)
        return result
    }

    /// Język bieżącego przebiegu (I2): z jego migawki, preset sesji tylko dla przebiegów bez migawki.
    func runLanguage(_ item: SessionItem) -> RunLanguage { RunLanguage.of(item.runSnapshot, fallback: presetFor(sessionURL: item.url)) }

    // MARK: Dostawcy

    /// nil = nie da się wysłać żądania (błąd w `lastError`): brak dostawcy, błąd Keychain albo brak klucza (check S15 #5).
    func client(for providerID: UUID) -> OpenAICompatibleClient? {
        switch makeClient(for: providerID) {
        case .success(let c): return c
        case .failure(let problem):
            lastError = problem.displayMessage
            return nil
        }
    }

    struct ClientProblem: Error {
        let message: String
        var displayMessage: String { ArchivePresentation.message(message) }
    }

    /// Dostawca z kluczem albo powód, dlaczego nie da się do niego wysłać żądania.
    private func providerWithKey(_ providerID: UUID, diarization: Bool = false) -> Result<(Provider, String?), ClientProblem> {
        guard let p = provider(providerID) else { return .failure(ClientProblem(message: "This provider no longer exists.")) }
        var key: String?
        do { key = try p.storedKey(in: secrets) } catch {
            return .failure(ClientProblem(message: "Couldn't read the API key for \(p.name) from Keychain: \(error)"))
        }
        #if DEBUG
        if diarization, key?.isEmpty != false { key = ProcessInfo.processInfo.environment["YASCRIBE_API_KEY"].flatMap { $0.isEmpty ? nil : $0 } }
        #endif
        guard key != nil || !p.requiresKey else {
            return .failure(ClientProblem(message: "No API key for \(p.name). Remove the provider and add it again with a key."))
        }
        return .success((p, key))
    }

    /// Klient OpenAI-compatible (listy modeli, czat, embeddingi) albo powód — bez alertu (weryfikacja dostawcy
    /// pokazuje powód przy dostawcy). ElevenLabs tu nie pasuje: robi tylko transkrypcję (`transcriptionClient`).
    func makeClient(for providerID: UUID) -> Result<OpenAICompatibleClient, ClientProblem> {
        providerWithKey(providerID).flatMap { p, key in
            p.api == .openAICompatible || p.api.isAgentCLI ? .success(OpenAICompatibleClient(provider: p, key: key))
                : .failure(ClientProblem(message: "\(p.name) does only speech-to-text."))
        }
    }

    /// Klient transkrypcji wybrany po `Provider.api`; nil = powód w `lastError`.
    func transcriptionClient(for providerID: UUID, model: String) -> (any TranscriptionClient)? {
        switch providerWithKey(providerID) {
        case .success(let (p, key)):
            // `.fluidAudio` nigdy nie przechodzi przez `Provider.transcriptionClient` (tam siedzi zaślepka). Odmowa = błąd i koniec:
            // żadnego klienta, więc nic nie pójdzie do API.
            guard p.api == .fluidAudio else { return p.transcriptionClient(key: key) }
            let support = localASRForRun(model)
            switch LocalASRFactory.client(provider: p, store: support.store, engine: localASREngine?(support.store), onPhase: { phase in Task { @MainActor in support.apply(phase) } }) {
            case .success(let c):
                return LocalASRVariant(model: model) == nil ? LegacyLocalASRClient(inner: c, legacyModel: model) : c
            case .failure(let refusal):
                lastError = refusal.displayMessage
                return nil
            }
        case .failure(let problem):
            lastError = problem.displayMessage
            return nil
        }
    }

    /// Test połączenia (`listModels`, u ElevenLabs `GET /v1/models`): Verified albo powód (zły klucz, guardrail, adres,
    /// serwer wyłączony).
    func verifyProvider(_ id: UUID) async {
        providerChecks[id] = nil
        detectedContexts[id] = nil
        providerVerifying.insert(id)
        defer { providerVerifying.remove(id) }
        switch providerWithKey(id) {
        case .failure(let problem): providerChecks[id] = .failed(problem.displayMessage)
        case .success(let (p, _)) where p.api == .fluidAudio: // bez sieci: model jest w magazynie i zgadza się z manifestem
            localASRModels.forEach { $0.refresh() }
            let ready = localASRModels.filter { RunGate.check(status: $0.status) == nil }
            if ready.count == LocalASRVariant.allCases.count {
                providerChecks[id] = .verified(models: ready.count)
            } else if !ready.isEmpty {
                let variants = ready.map { $0.store.variant.displayName }.joined(separator: ", ")
                providerChecks[id] = .limited(String(localized: "\(variants) only"))
            } else {
                providerChecks[id] = RunGate.check(status: localASR("")!.status).map { .failed($0.displayMessage) } ?? .verified(models: 1)
            }
        case .success(let (p, key)):
            providerChecks[id] = await p.verify(key: key)
            // Lokalny serwer: pokaż efektywny kontekst (llama.cpp `/props`, Ollama `/api/ps`), żeby użytkownik mógł go wpisać w polu.
            if case .verified? = providerChecks[id], p.isLocal, p.api == .openAICompatible {
                detectedContexts[id] = ContextProbe.describe(await ContextProbe.effectiveContexts(client: OpenAICompatibleClient(provider: p, key: key)))
            }
        }
    }

    /// Wykryty kontekst lokalnego serwera z ostatniego „Check" (w pamięci); brak wpisu = nic wykrytego.
    var detectedContexts: [UUID: String] = [:]

    /// Pole „Context window (tokens)": `nil` = domyślne 4096. Zapis do `providers.json`.
    func setContextTokens(_ id: UUID, _ value: Int?) {
        guard let i = providers.providers.firstIndex(where: { $0.id == id }) else { return }
        providers.providers[i].contextTokens = value
        save()
    }

    /// `nil` = dodano; tekst = powód odmowy (duplikat nazwy albo błąd pęku kluczy).
    func addProvider(name: String, baseURL: URL, key: String, kind: ProviderKind? = nil, contextTokens: Int? = nil) -> String? {
        if let e = providers.nameError(name) { return e }
        let p = Provider(name: name.trimmingCharacters(in: .whitespaces), baseURL: baseURL, kind: kind, contextTokens: contextTokens)
        do {
            if !key.isEmpty { try secrets.set(p.id, key) }
            providers.providers.append(p)
            save()
            Task { await verifyProvider(p.id) } // Verified albo powód przy dostawcy
            return nil
        } catch {
            return String(localized: "Couldn't store the key in Keychain: \(error.localizedDescription)")
        }
    }

    /// Poprawka klucza już zapisanego dostawcy (formularz „Save & verify" po błędzie): zapis i ponowna weryfikacja.
    /// `nil` = zapisano; tekst = błąd pęku kluczy. Pusty klucz (Ollama) tylko weryfikuje ponownie.
    func replaceKey(_ id: UUID, key: String) -> String? {
        do { if !key.isEmpty { try secrets.set(id, key) } } catch { return String(localized: "Couldn't store the key in Keychain: \(error.localizedDescription)") }
        Task { await verifyProvider(id) }
        return nil
    }

    /// „Test connection" w arkuszu PRZED zapisem: klient z kluczem z pola (w pamięci, nic nie trafia do pęku kluczy).
    /// ElevenLabs: klienta tworzy `makeClient` z zapisanego klucza, więc przed zapisem testu nie ma (`nil`) — arkusz weryfikuje po Save.
    nonisolated static func testConnection(baseURL: URL, kind: ProviderKind?, key: String, name: String = "test") async -> ProviderCheck {
        // Klucz z pola, w pamięci — bez zapisu do pęku (Cancel nie zostawia klucza). Klient wg rodzaju API.
        // `name` trafia do komunikatów o lokalnym serwerze („Can't reach Ollama at …").
        await Provider(name: name, baseURL: baseURL, kind: kind).verify(key: key.isEmpty ? nil : key)
    }

    /// Nowa ścieżka programu agenta CLI (R10): ten sam UUID, zapis i ponowny Check.
    func setBaseURL(_ id: UUID, _ url: URL) {
        guard providers.setBaseURL(id, url) else { return }
        save()
        Task { await verifyProvider(id) }
    }

    func removeProvider(_ id: UUID) {
        if let p = provider(id) { try? p.forgetKey(in: secrets) }
        providers.providers.removeAll { $0.id == id }
        save()
    }

    var modelLists: [ModelListKey: [ModelInfo]] = [:]
    /// Wynik ostatniego testu połączenia per dostawca (w pamięci; po restarcie Not verified, dopóki nie klikniesz Verify).
    var providerChecks: [UUID: ProviderCheck] = [:]
    private(set) var providerVerifying: Set<UUID> = []
    private(set) var loadingModels: Set<ModelListKey> = []

    private func key(_ provider: UUID, _ role: Role) -> ModelListKey {
        ModelListKey(provider: provider, filter: ModelCatalog.outputFilter(for: role) ?? "")
    }

    func models(provider: UUID, role: Role) -> [ModelInfo] { modelLists[key(provider, role)] ?? [] }
    func isLoadingModels(provider: UUID, role: Role) -> Bool { loadingModels.contains(key(provider, role)) }

    /// Lista modeli dla roli: pobierana raz na dostawcę i rolę (`force` = odśwież).
    func loadModels(provider: UUID, role: Role, force: Bool = false) async {
        if let p = self.provider(provider), ![Role.asr, .correction, .summary, .embedding].contains(where: { p.supports($0) }) { return }
        let k = key(provider, role)
        if self.provider(provider)?.api == .elevenLabs { // stała lista (Scribe v2 dla ASR, poza tym pusto), bez sieci
            modelLists[k] = ElevenLabsClient.models(for: role)
            return
        }
        if self.provider(provider)?.api == .fluidAudio { // stała lista (Parakeet dla ASR), bez sieci
            modelLists[k] = LocalASRModels.models(for: role)
            return
        }
        guard force || modelLists[k] == nil, !loadingModels.contains(k), let c = client(for: provider) else { return }
        loadingModels.insert(k)
        defer { loadingModels.remove(k) }
        do {
            let list = try await c.listModels(output: ModelCatalog.outputFilter(for: role))
            modelLists[k] = list
            if modelNames.record(list) { try? JSONFile.save(modelNames, to: paths.modelNames) }
        } catch {
            lastError = String(localized: "Couldn't load models: \(error.localizedDescription)")
        }
    }

    /// Nazwa modelu do wyświetlenia (bez dostawcy).
    func modelDisplayName(_ id: String) -> String { modelNames.display(id) }

    /// Przycisk „Refresh Models" w Settings: transkrypcja, embeddingi i lista tekstowa.
    func refreshModels(_ id: UUID) async {
        for role in [Role.asr, .embedding, .summary] { await loadModels(provider: id, role: role, force: true) }
    }

    func probe(providerID: UUID, model: String, role: Role, language: LanguageCode?) async {
        // Agent CLI: sonda czatu przez `makeClient` (R4); ASR i embeddingi odrzuca `ProbeRunner` jako nie-tekstowe.
        if self.provider(providerID)?.api.isAgentCLI == true {
            switch makeClient(for: providerID) {
            case .success(let c): probeCache.record(await ProbeRunner(client: c).probe(model: model, role: role, language: language)); save()
            case .failure(let problem): lastError = problem.displayMessage
            }
            return
        }
        guard let c = transcriptionClient(for: providerID, model: model) else { return }
        let support = c is any ReleasableClient ? localASRForRun(model) : nil
        support?.beginRun()
        defer { // sonda lokalnego ASR ładuje model — nie zostawiamy go w pamięci
            Task {
                await (c as? ReleasableClient)?.release()
                support?.endRun()
            }
        }
        let r = await ProbeRunner(client: c).probe(model: model, role: role, language: language)
        probeCache.record(r)
        save()
    }

    // MARK: Presety

    func savePreset(_ p: Preset) -> String? {
        do {
            if let a = p.asr, probeCache.result(provider: a.providerID, model: a.model, role: .asr, language: p.language)?.shape == .chatAudio {
                return String(localized: "This model returns no word timings, so it can't be used for meetings.")
            }
            try presets.upsert(p)
            if settings.defaultPresetID == nil { settings.defaultPresetID = p.id }
            save()
            return nil
        } catch PresetError.missingLanguage {
            return String(localized: "Choose a language, or Auto for meetings that mix languages.")
        } catch PresetError.missingASR {
            return String(localized: "Choose a speech-to-text model.")
        } catch PresetError.missingName {
            return String(localized: "Give the preset a name.")
        } catch {
            return String(describing: error)
        }
    }

    /// Zapis słownika po zmianie w zakładce Dictionary; `nil` = zapisano, tekst = powód.
    func saveDictionary() -> String? {
        do { try JSONFile.save(dictionary, to: paths.dictionary); return nil } catch { return String(localized: "Couldn't save the dictionary: \(String(describing: error))") }
    }

    // MARK: Aktualizacje i zamykanie

    /// Sparkle czeka (restart odroczony do końca nagrania): bez komunikatu „Install and Relaunch” wygląda jak brak reakcji.
    /// Arkusz przy oknie głównym, bez blokowania (nagranie trwa); gdy okna nie ma, zostaje podpowiedź w pigułce.
    private func announceUpdatePostponed() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && !$0.isSheet }) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Update ready")
        alert.informativeText = String(localized: "Yascribe will install the update and restart as soon as you stop recording. The recording is not interrupted.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.beginSheetModal(for: window)
    }

    /// Nowe nagranie nie startuje od pierwszego kliknięcia „Install Update” do końca cyklu (także podczas odroczonego restartu).
    func canBeginRecording() -> Bool {
        guard updateGate.canStartRecording else {
            lastError = String(localized: "Update in progress.")
            return false
        }
        guard DictationGate.canStartMeeting(dictationBusy: dictation.engine.isBusy) else {
            lastError = String(localized: "Finish dictating first.")
            return false
        }
        return true
    }

    /// Zakończenie aplikacji (⌘Q, pasek menu, restart Sparkle): z nagraniem w toku pyta, najpierw zatrzymuje je, potem pozwala wyjść.
    /// ponytail: transkrypcja nie startuje przed wyjściem; wznawia się ręcznie po następnym uruchomieniu.
    enum TerminationDecision { case now, cancel, afterRecording, afterDictation }

    var canRestartForLanguage: Bool {
        let downloading = localASRModels.contains { if case .idle = $0.phase { false } else { true } }
        return Self.canRestartForLanguage(updateGate: updateGate, recordingDirectory: recording.directory,
                                          dictationBusy: dictation.engine.isBusy, dictationHasRetryAudio: dictation.engine.hasRetryAudio,
                                          backgroundWork: sessionWorkRunning || archive.isWorking || downloading)
    }

    /// `backgroundWork`: przebiegi spotkań, pytanie do archiwum, pobieranie modelu — restart by je przerwał.
    static func canRestartForLanguage(updateGate: RestartGate, recordingDirectory: URL?,
                                      dictationBusy: Bool, dictationHasRetryAudio: Bool, backgroundWork: Bool = false) -> Bool {
        updateGate.shouldTerminate() && recordingDirectory == nil && !dictationBusy
            && !dictationHasRetryAudio && !backgroundWork && updateGate.phase == .idle
    }

    /// `afterRecording`: zgoda jest, ale rejestrator jeszcze finalizuje pliki (`stop()` mógł wrócić od razu, gdy
    /// finalizacja zaczęła się wcześniej na wątku audio); wyjście dopiero po `recordingFinished()`.
    /// `afterDictation`: trwa transkrypcja dyktowania; wyjście po jej końcu (tekst trafia do celu i historii).
    func terminationDecision() -> TerminationDecision {
        // Przed `updateGate`: ta bramka widzi tylko nagranie spotkania. Dyktowanie i nagranie się wykluczają.
        switch dictation.engine.phase {
        case .listening: dictation.engine.apply(.cancel)   // bez pytania, mikrofon zwolniony
        case .processing where !isBusy: return .afterDictation   // przy przenoszeniu nagrań: zwykła odmowa niżej
        default: break
        }
        if quitApproved { return recording.isRecording ? .afterRecording : .now }
        if updateGate.shouldTerminate() { return .now }
        let alert = NSAlert()
        NSApp.activate()
        if recording.isRecording {
            alert.messageText = String(localized: "Stop recording and quit?")
            alert.informativeText = String(localized: "The recording is saved. Transcribe it the next time you open Yascribe.")
            alert.addButton(withTitle: String(localized: "Stop and Quit"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .cancel }
            quitApproved = true
            recording.stop()
            return recording.isRecording ? .afterRecording : .now
        }
        alert.messageText = String(localized: "Meetings are being moved")
        alert.informativeText = String(localized: "Quit when the move to the new folder finishes.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
        return .cancel
    }

    /// Ustawiane przez `AppDelegate`, gdy zamknięcie czeka na koniec finalizacji nagrania.
    @ObservationIgnored var onRecordingEnded: (@MainActor () -> Void)?

    /// Wołane z `RecordingController.finish` po zamknięciu plików: odblokowuje odroczony restart i oczekujące zamknięcie.
    func recordingFinished() {
        updateGate.activityDidChange()
        let waiting = onRecordingEnded
        onRecordingEnded = nil
        waiting?()
    }

    // MARK: Nagrywanie i transkrypcja

    /// Ręczny start (menu, przycisk): wywołania w ternarnych wyrażeniach typu `()` nie znoszą wyniku `Bool`.
    func startRecording() { startRecording(event: nil, background: false) }

    /// Start z oferty (detekcja w tle) — błąd tylko w `lastError`, bez przełączania sekcji. `true` = nagranie trwa.
    @discardableResult
    func startRecording(offer: Offer) -> Bool { startRecording(event: offer.event, background: true) }

    /// `event`: nagranie od razu z tytułem i powiązaniem (spec 1.6 §4.7) — z oferty albo z karty „Coming up” (§11.5).
    @discardableResult
    func startRecording(event: CalendarEventInfo?, background: Bool = false) -> Bool {
        // Jedyna droga do `recording.start`: menu, skróty, pigułka, pasek menu, Coming up i oferty przechodzą tędy.
        guard canBeginRecording() else { return false }
        guard !recording.isRecording else {
            lastError = String(localized: "A recording is already in progress.")
            return false
        }
        guard recordingsMove == nil else {
            lastError = String(localized: "Meetings are being moved to a new folder. Record when that finishes.")
            return false
        }
        // ChatGPT #2: preset — z językiem — ustalony PRZED startem i zamrożony na całą sesję.
        guard let preset = activePreset, (try? preset.validate()) != nil else {
            lastError = String(localized: "Choose a preset with a language before recording.")
            if !background { section = .presets }
            return false
        }
        let dir = sessionsDirectory.appendingPathComponent(Self.sessionName(Date()))
        do {
            try recording.start(directory: dir, presetLabel: Self.label(preset), eventTitle: event?.title) { [weak self] _ in
                Task { @MainActor in
                    self?.reloadSessions()
                    self?.transcribe(sessionURL: dir, preset: preset)
                }
            }
            // Nagranie trwa mimo błędu zapisu — ten przebieg i tak dostaje `preset` z domknięcia.
            do { try JSONFile.save(preset, to: dir.appendingPathComponent("preset.json")) } catch {
                lastError = String(localized: "Recording, but couldn't save its preset: \(String(describing: error)). After a restart it will use the active preset.")
            }
            if let event {
                do {
                    if let note = try NotesStore(session: dir).updateMeta({ $0.calendarEvent = event.link() }) { lastError = note }
                } catch { lastError = String(localized: "Recording, but couldn't link the calendar event: \(String(describing: error))") }
            }
            if recording.isRecording { recording.showPanel(model: self) }
            reloadSessions()
            openSession(dir.lastPathComponent) // notatki pisze się w trakcie spotkania
            return recording.isRecording
        } catch {
            lastError = String(localized: "Couldn't start recording: \(String(describing: error))")
            return false
        }
    }

    /// Spec §1.5: preset zamrożony przy starcie (`<sesja>/preset.json`) idzie do transkrypcji także po restarcie;
    /// sesja bez pliku (np. z CLI) dostaje aktywny.
    func presetFor(sessionURL: URL) -> Preset? {
        (try? JSONFile.load(Preset?.self, from: sessionURL.appendingPathComponent("preset.json"), default: nil)) ?? activePreset
    }

    /// Przełącza na listę spotkań i otwiera sesję (np. notatkę trwającego nagrania). Nie aktywuje aplikacji.
    func openSession(_ id: String) {
        section = .meetings
        selectedSessionID = id
    }

    /// „Open note” z pigułki. Zakładki nie trzeba ustawiać: widok nagrywanego spotkania pokazuje tylko My notes.
    func go(to d: OpenNoteDestination) {
        switch d.section { case .meetings: section = .meetings }
        selectedSessionID = d.sessionID
    }

    /// Otwarte spotkanie (widok szczegółów) — dla menu Meeting; poza Meetings nic nie jest „otwarte”.
    var openItem: SessionItem? { section == .meetings ? sessions.first { $0.id == selectedSessionID } : nil }

    /// Powód, dla którego teraz nie wolno usunąć spotkania; `nil` = wolno. Oceniany także po potwierdzeniu.
    func deleteBlocker(_ item: SessionItem) -> String? {
        DeleteMeeting.blocker(recording: SessionStatus.isRecording(item.url, recordingDirectory: recording.directory),
                             busy: busySessions.contains(item.id), moving: recordingsMove != nil)
    }

    /// Sesji nagrywanej, transkrybowanej albo przetwarzanej nie usuwamy (katalog jest w użyciu).
    func canDelete(_ item: SessionItem) -> Bool { deleteBlocker(item) == nil }

    func copyNotes(_ item: SessionItem) {
        guard let md = item.notesText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    func showInFinder(_ item: SessionItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    /// Potwierdzenie przed usunięciem z listy (menu kontekstowe wiersza); szczegóły mają własny dialog.
    func requestDelete(_ item: SessionItem) {
        if let reason = deleteBlocker(item) {
            lastError = String(localized: "Couldn't delete the meeting: \(reason)")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Move “\(item.displayTitle)” to the Trash?")
        alert.informativeText = String(localized: "The meeting folder, with its recordings and notes, goes to the Trash. You can put it back from there.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteSession(item.id)
    }

    /// Do Kosza, nie trwale. Cały katalog sesji. Bramka sprawdzana ponownie po potwierdzeniu, a najnowsze
    /// My notes zapisujemy przed przeniesieniem — gdy zapis padnie, nie usuwamy niczego (TASK-25).
    func deleteSession(_ id: String) {
        pendingDelete = nil
        guard let item = sessions.first(where: { $0.id == id }) else { return }
        if let reason = deleteBlocker(item) { lastError = String(localized: "Couldn't delete the meeting: \(reason)"); return }
        if let problem = notes.flushPendingSaves(for: id) { lastError = String(localized: "Couldn't delete the meeting: \(problem)"); return }
        // Stan mógł się zmienić w trakcie zapisu — druga ocena tuż przed przeniesieniem.
        if let reason = deleteBlocker(item) { lastError = String(localized: "Couldn't delete the meeting: \(reason)"); return }
        do {
            switch try trashDestination() {
            case .systemTrash:
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            case .directory(let trash):
                try FileManager.default.moveItem(at: item.url, to: trash.appendingPathComponent(item.url.lastPathComponent))
            }
            if selectedSessionID == id { selectedSessionID = nil }
            archive.forget(id)
        } catch {
            lastError = String(localized: "Couldn't move the meeting to the Trash: \(error.localizedDescription)")
        }
        reloadSessions()
    }

    /// Dokąd idzie usunięte spotkanie. Produkcja: systemowy Kosz. Kopia do odbioru GUI (tylko DEBUG) może wskazać
    /// testowy katalog przez `YASCRIBE_TEST_TRASH_DIR`; zła ścieżka to błąd, nie cichy powrót do Kosza użytkownika.
    private func trashDestination() throws -> MeetingTrash.Destination {
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment[MeetingTrash.testDirectoryVariable]
        #else
        let requested: String? = nil // produkcja: zmienna nie istnieje dla tej kompilacji
        #endif
        return try MeetingTrash.destination(requested: requested, dataRoot: paths.root)
    }

    // MARK: Foldery (TASK-26)

    /// Sesja widoczna przy bieżącym filtrze. `folderID` wskazujący usunięty folder = „No folder" (stare metadane czytelne).
    func matchesFilter(_ item: SessionItem) -> Bool {
        switch meetingFilter {
        case .all: return true
        case .unfiled: return folders.folder(item.notes.meta.folderID) == nil
        case .folder(let id): return item.notes.meta.folderID == id
        }
    }

    var filterLabel: String {
        switch meetingFilter {
        case .all: String(localized: "All folders")
        case .unfiled: String(localized: "No folder")
        case .folder(let id): folders.folder(id)?.name ?? String(localized: "No folder")
        }
    }

    /// Etykieta folderu sesji; `nil` = bez folderu (albo folder usunięty).
    func folderName(of item: SessionItem) -> String? { folders.folder(item.notes.meta.folderID)?.name }

    private func saveFolders() -> String? {
        do { try JSONFile.save(folders, to: paths.folders); return nil }
        catch { return String(localized: "Couldn't save the folders: \(error.localizedDescription)") }
    }

    /// `nil` = utworzono; tekst = powód odmowy (pusta, za długa, powtórzona nazwa).
    @discardableResult
    func createFolder(_ name: String) -> String? {
        let previous = folders
        do { try folders.create(name) } catch { return error.localizedDescription }
        if let problem = saveFolders() { folders = previous; return problem }
        return nil
    }

    @discardableResult
    func renameFolder(_ id: String, to name: String) -> String? {
        let previous = folders
        do { try folders.rename(id, to: name) } catch { return error.localizedDescription }
        if let problem = saveFolders() { folders = previous; return problem }
        return nil
    }

    /// Usuwa folder, spotkania zostają (tracą tylko przypisanie). `nil` = usunięto. Pamięć wraca do stanu z dysku,
    /// gdy zapis padnie (żadnego folderu „tylko w pamięci").
    @discardableResult
    func deleteFolder(_ id: String) -> String? {
        let previous = folders
        let previousFilter = meetingFilter
        guard folders.delete(id) else { return FolderError.notFound.localizedDescription }
        if let problem = saveFolders() { folders = previous; meetingFilter = previousFilter; return problem }
        if meetingFilter == .folder(id) { meetingFilter = .all }
        return nil
    }

    func promptNewFolder(assignTo item: SessionItem? = nil) {
        guard let name = Self.promptForName(title: String(localized: "New Folder"), message: String(localized: "Meetings stay where they are on disk; the folder only groups them."),
                                           confirm: String(localized: "Create")) else { return }
        if let error = createFolder(name) {
            lastError = error
        } else if let item, let folder = folders.folders.last {
            notes.setFolder(folder.id, for: item)
        }
    }

    func promptRenameFolder(_ id: String) {
        guard let current = folders.folder(id) else { return }
        guard let name = Self.promptForName(title: String(localized: "Rename Folder"), message: nil, confirm: String(localized: "Rename"), initial: current.name) else { return }
        if let error = renameFolder(id, to: name) { lastError = error }
    }

    /// Potwierdzenie: spotkania w folderze zostają, tylko przestają być przypisane.
    func confirmDeleteFolder(_ id: String) {
        guard let folder = folders.folder(id) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete the folder “\(folder.name)”?")
        alert.informativeText = String(localized: "Its meetings are kept; they just move to “No folder”.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete Folder"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let error = deleteFolder(id) { lastError = error }
    }

    /// Jedno pole tekstowe w `NSAlert`; `nil` = anulowano.
    private static func promptForName(title: String, message: String?, confirm: String, initial: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        field.placeholderString = String(localized: "Folder name")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    /// Zapis własnych szablonów; `nil` = zapisano, tekst = powód.
    func saveTemplates() -> String? {
        do { try JSONFile.save(notes.templates, to: paths.templates); return nil } catch { return String(localized: "Couldn't save templates: \(String(describing: error))") }
    }

    func isTranscribing(_ item: SessionItem) -> Bool { transcribing.contains(item.id) }

    static func label(_ p: Preset) -> String { "\(p.name) · \(presetLanguageLabel(p))" }

    static func presetLanguageLabel(_ p: Preset) -> String {
        p.isAutoLanguage ? String(localized: "Auto ⚠") : p.languageLabel
    }

    /// `true` = przebieg przyjęty i wystartował; odmowa zostawia powód w `lastError`.
    @discardableResult
    func transcribe(sessionURL: URL, preset: Preset) -> Bool {
        guard var asr = preset.asr, let provider = provider(asr.providerID) else {
            lastError = String(localized: "The preset's speech-to-text provider is missing.")
            return false
        }
        // Migawka ma nieść model, który naprawdę ruszy (nieznany = v3), a nie wpisany identyfikator.
        if provider.api == .fluidAudio { asr.model = localASRForRun(asr.model).store.variant.rawValue }
        var preset = preset
        preset.asr = asr
        guard let c = transcriptionClient(for: asr.providerID, model: asr.model) else { return false } // powód już w lastError
        let probe = probeCache.result(provider: asr.providerID, model: asr.model, role: .asr, language: preset.language)
        do {
            // Dostawca API: odcisk i tak jest `nil` — magazyn tylko wypełnia argument.
            let store = (localASR(asr.model) ?? localASR("")!).store
            let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: probe,
                                           modelFingerprint: RunGate.fingerprintForSnapshot(provider: provider, store: store))
            return run(sessionURL: sessionURL, runID: RunDirectory.nextRunID(latest: RunDirectory.latestRunID(in: sessionURL), now: Date()),
                       snapshot: snapshot, client: c)
        } catch RunSnapshotError.chatShapeNotForMeetings {
            lastError = String(localized: "This model returns no word timings, so it can't be used for meetings.")
        } catch {
            lastError = String(describing: error)
        }
        return false
    }

    /// „Transcribe again…" (D13): to samo nagranie innym modelem ASR i językiem; kopia presetu tylko na ten przebieg,
    /// zapisany `preset.json` bez zmian. Nowy przebieg (`runs/<id>`) staje się bieżącym transkryptem dopiero ukończony, niepusty
    /// i bez luk (`RunSelection`, R23); stary zostaje na dysku.
    @discardableResult
    func transcribe(sessionURL: URL, preset: Preset, asr: RoleAssignment, language: LanguageCode?) -> Bool {
        transcribe(sessionURL: sessionURL, preset: preset.withASR(asr, language: language))
    }

    /// ChatGPT #17: wznowienie w aplikacji, także po restarcie — ten sam runID i ta sama
    /// migawka z `input.json`, więc opłacone okna nie idą drugi raz (P5). `runID`: najnowsza próba („Resume Transcription")
    /// albo bieżący przebieg z lukami na ekranie („Retry Failed Parts").
    func resume(_ item: SessionItem, runID: String?) {
        // F2: wznowienie z korektą w toku dałoby drugą korektę tego samego przebiegu (blokada także poza interfejsem, jak R3).
        guard !notes.isCorrecting(item.id) else {
            lastError = String(localized: "This transcript is being corrected. Try again when that finishes.")
            return
        }
        guard let runID,
              let input = try? JSONFile.load(RunInput?.self, from: RunDirectory(session: item.url, runID: runID).input, default: nil) else {
            lastError = String(localized: "Nothing to resume for this recording.")
            return
        }
        if let p = provider(input.snapshot.providerID), p.api == .fluidAudio {
            let fingerprint = localASRForRun(input.snapshot.model).store.fingerprint()
            if LocalASRVariant(model: input.snapshot.model) == nil,
               (fingerprint == nil || input.snapshot.modelFingerprint != fingerprint) {
                lastError = String(localized: "Unknown on-device model: \(input.snapshot.model). Its saved fingerprint doesn't match Parakeet TDT v3.")
                return
            }
            if let refusal = RunGate.checkResume(snapshot: input.snapshot, provider: p, currentFingerprint: fingerprint) {
                lastError = refusal.displayMessage
                return
            }
        }
        guard let c = transcriptionClient(for: input.snapshot.providerID, model: input.snapshot.model) else { return }
        run(sessionURL: item.url, runID: runID, snapshot: input.snapshot, client: c)
    }

    @discardableResult
    private func run(sessionURL: URL, runID: String, snapshot: RunSnapshot, client c: any TranscriptionClient) -> Bool {
        let id = sessionURL.lastPathComponent
        if let refusal = TranscriptionStartGate.begin(sessionURL: sessionURL, notes: notes, moving: recordingsMove != nil) {
            lastError = refusal
            return false
        }
        let support = c is any ReleasableClient ? localASRForRun(snapshot.model) : nil
        support?.beginRun()
        Task {
            var finished: Transcript?
            do {
                finished = try await TranscriptionRunner(session: sessionURL, runID: runID, snapshot: snapshot, client: c).run { p in
                    Task { @MainActor in
                        // Pierwszy postęp: `input.json` już leży, więc baner nowej próby zna jej model.
                        if p.done == 0 { self.reloadSessions() }
                        if let i = self.sessions.firstIndex(where: { $0.id == id }) { self.sessions[i].progress = p.fraction }
                    }
                }
            } catch {
                self.lastError = String(localized: "Transcription failed: \(String(describing: error))")
            }
            // Zwolnienie modelu po przebiegu — także po błędzie (catch wyżej go połyka, więc ta linia zawsze się wykona). Notatka idzie dalej.
            await (c as? ReleasableClient)?.release()
            support?.endRun()
            self.reloadSessions()
            // Łańcuch korekta → autotytuł tylko dla przebiegu, który został bieżącym i się kwalifikuje (R23); wyjątek: pierwsza
            // transkrypcja z luką. Próba z lukami albo pusta obok wcześniejszego transkryptu nie dostaje automatycznej obróbki.
            var post = finished != nil && RunSelection.shouldPostProcess(session: sessionURL, runID: runID)
            // TASK-22 D7: etykiety mówców przed notatką (notatka czyta `speakers.json` z dysku); błąd tylko w `lastError`.
            // `transcribing` zdejmujemy dopiero po diaryzacji: do tego czasu bramki korekty, notatki i transkrypcji odmawiają (F01).
            if let finished, post, await self.detectSpeakersAfterTranscription(sessionURL: sessionURL, runID: runID,
                themUtterances: finished.utterances.filter { $0.speaker == .them }.count) {
                post = RunSelection.shouldPostProcess(session: sessionURL, runID: runID)
            }
            self.transcribing.remove(id)
            if let finished, post {
                await self.notes.afterTranscription(sessionURL: sessionURL, runID: runID, snapshot: snapshot, transcript: finished)
            }
            self.reloadSessions()
        }
        return true
    }

    func detectSpeakersAfterTranscription(sessionURL: URL, runID: String, themUtterances: Int) async -> Bool {
        guard let snapshot = runSnapshot(sessionURL: sessionURL, runID: runID),
              let provider = provider(snapshot.providerID),
              await SpeakerDetectionDecision.shouldRun(capable: SpeakerCapability.supports(api: provider.api, model: snapshot.model),
                  themUtterances: themUtterances, hasSystemTrack: { await Task.detached { Self.hasSystemTrack(sessionURL) }.value }),
              let cloud = cloudProvider(snapshot.providerID) else { return false }
        guard let ticket = reserveSpeakerTicket(sessionURL: sessionURL, runID: runID) else { return false }
        await performSpeakerDetection(ticket, sessionURL: sessionURL, cloud: cloud)
        return true
    }

    func isDetectingSpeakers(_ item: SessionItem) -> Bool { speakerTickets[item.id] != nil }

    private func runSnapshot(sessionURL: URL, runID: String) -> RunSnapshot? {
        (try? JSONFile.load(RunInput?.self, from: RunDirectory(session: sessionURL, runID: runID).input, default: nil))?.snapshot
    }

    func supportsCloudSpeakers(_ item: SessionItem) -> Bool {
        guard let snapshot = item.runSnapshot else { return false }
        if let provider = provider(snapshot.providerID) { return SpeakerCapability.supports(api: provider.api, model: snapshot.model) }
        return SpeakerCapability.supports(api: .openAICompatible, model: snapshot.model) || SpeakerCapability.supports(api: .elevenLabs, model: snapshot.model)
    }

    private func cloudProvider(_ id: UUID) -> (Provider, String)? {
        if case let .success((provider, key)) = providerWithKey(id, diarization: true), let key, !key.isEmpty { return (provider, key) }
        return nil
    }

    /// Tor `system` z klatkami i plikiem na dysku (retencja mogła skasować audio) — ten sam warunek co CLI `diarize`.
    /// Czyta dziennik — wołać poza MainActor (F04).
    nonisolated private static func hasSystemTrack(_ sessionURL: URL) -> Bool {
        let session = SessionDirectory(url: sessionURL)
        return FileManager.default.fileExists(atPath: session.trackURL("system").path)
            && (try? session.summarize())?.tracks.contains { $0.id == "system" && ($0.frames ?? 0) > 0 } == true
    }

    private struct NoCallAudio: LocalizedError {
        var errorDescription: String? { String(localized: "This meeting has no call audio, so speakers can't be detected.") }
    }

    /// Cała praca na dysku i modelu poza MainActor (F04): dziennik, diaryzacja, przeliczenie segmentów, odcisk audio.
    nonisolated private static func diarization(sessionURL: URL, runID: String, store: DiarizerModelStore, cloud: (Provider, String)?, http: any HTTPClient) async throws -> SpeakerDiarization {
        guard hasSystemTrack(sessionURL) else { throw NoCallAudio() }
        let session = SessionDirectory(url: sessionURL)
        let summary = try session.summarize()
        let segments: [(speaker: String, start: Double, end: Double)]
        let pin: String
        let sensitivity: SpeakerSensitivity?
        if let (provider, key) = cloud {
            let input = try JSONFile.load(RunInput?.self, from: RunDirectory(session: sessionURL, runID: runID).input, default: nil)
            guard let snapshot = input?.snapshot else { throw NoCallAudio() }
            let client: any DiarizationClient = provider.api == .elevenLabs
                ? ElevenLabsClient(provider: provider, key: key, http: http)
                : OpenAICompatibleClient(provider: provider, key: key, http: http)
            segments = try await CloudDiarization.run(track: session.trackURL("system"), client: client, model: snapshot.model, language: snapshot.language, limitBytes: provider.api == .elevenLabs ? nil : CloudDiarization.openRouterLimitBytes)
            pin = SpeakerCapability.pin(api: provider.api, model: snapshot.model)
            sensitivity = nil
        } else {
            segments = try await SpeakerDiarizer(store: store).run(systemTrack: session.trackURL("system"), sensitivity: .medium, progress: nil)
            pin = DiarizerManifest.pin
            sensitivity = .medium
        }
        return SpeakerDiarization.fromTrack(segments: segments, clock: SessionClock(summary: summary), modelPin: pin, sensitivity: sensitivity,
                                            audioFingerprint: SpeakerDiarization.audioFingerprint(session: sessionURL), createdAt: Date())
    }

    func detectSpeakers(sessionURL: URL, runID: String, sensitivity: SpeakerSensitivity) async {
        guard !Task.isCancelled, let ticket = reserveSpeakerTicket(sessionURL: sessionURL, runID: runID) else { return }
        await performSpeakerDetection(ticket, sessionURL: sessionURL, cloud: nil)
    }

    /// Synchronicznie, przed pierwszym `await` i przed utworzeniem `Task`: sesja od razu chroniona przed retencją i przeniesieniem (F03).
    private func reserveSpeakerTicket(sessionURL: URL, runID: String) -> SpeakerDetectionTicket? {
        guard recordingsMove == nil else {
            lastError = String(localized: "Meetings are being moved to a new folder. Detect speakers when that finishes.")
            return nil
        }
        let id = sessionURL.lastPathComponent
        speakerGeneration += 1
        let ticket = SpeakerDetectionTicket(session: id, runID: runID, generation: speakerGeneration)
        speakerTasks[id]?.cancel()
        speakerTickets[id] = ticket
        return ticket
    }

    private func performSpeakerDetection(_ ticket: SpeakerDetectionTicket, sessionURL: URL, cloud: (Provider, String)?) async {
        let id = ticket.session
        guard speakerTickets[id] == ticket else { return } // zastąpiony, zanim ruszył
        let store = speakerModel.store
        let previous = speakerTasks[id]
        if let previous { _ = await previous.result }
        guard speakerTickets[id] == ticket else { return }
        if Task.isCancelled {
            speakerTickets[id] = nil
            speakerTasks[id] = nil
            return
        }
        let http = diarizationHTTP
        let override = speakerWorkOverride
        let work = Task.detached {
            if let override { return try await override() }
            return try await Self.diarization(sessionURL: sessionURL, runID: ticket.runID, store: store, cloud: cloud, http: http)
        }
        speakerTasks[id] = work
        // Wraca po faktycznym końcu pracy, także anulowanej — dopiero wtedy bilet schodzi (F02).
        let result = await SpeakerDetectionWork.result(of: work)
        do {
            let diarization = try result.get()
            // Bez `await` między bramką a zapisem: nowszy bilet nie wejdzie pomiędzy.
            if SpeakerDetectionTicket.mayWrite(ticket, current: speakerTickets[id], cancelled: Task.isCancelled || work.isCancelled) {
                try JSONFile.save(diarization, to: RunDirectory(session: sessionURL, runID: ticket.runID).speakers, createParents: false)
            }
        } catch {
            // Anulowanie (nowsza operacja albo wywołujący) nie jest błędem dla użytkownika.
            if !Task.isCancelled, !work.isCancelled, !(error is CancellationError) {
                lastError = error is NoCallAudio ? error.localizedDescription : String(localized: "Couldn't detect speakers: \(SpeakerDetectionError.text(error))")
            }
        }
        // Tylko własny bilet: zastąpiona operacja nie zdejmuje ochrony z sesji, której używa nowsza.
        if speakerTickets[id] == ticket {
            speakerTickets[id] = nil
            speakerTasks[id] = nil
        }
        reloadSessions()
    }

    func detectSpeakersAgain(item: SessionItem) {
        guard let snapshot = item.runSnapshot, let cloud = cloudProvider(snapshot.providerID) else {
            lastError = String(localized: "Couldn't detect speakers: No API key.")
            return
        }
        startManualDetection(item: item, cloud: cloud)
    }

    func detectSpeakersOnThisMac(item: SessionItem) { startManualDetection(item: item, cloud: nil) }

    private func startManualDetection(item: SessionItem, cloud: (Provider, String)?) {
        guard let runID = item.runID else { lastError = String(localized: "Transcribe this meeting first."); return }
        guard !notes.isTranscribing(item.id) else { lastError = String(localized: "This recording is being transcribed. Try again when that finishes."); return }
        guard let ticket = reserveSpeakerTicket(sessionURL: item.url, runID: runID) else { return }
        Task { await performSpeakerDetection(ticket, sessionURL: item.url, cloud: cloud) }
    }

    func renameSpeaker(item: SessionItem, key: String, name: String?) {
        guard let runID = item.runID else { return }
        let url = RunDirectory(session: item.url, runID: runID).speakers
        do {
            guard let current = try JSONFile.load(SpeakerDiarization?.self, from: url, default: nil),
                  let renamed = current.renamed(key, to: name) else { return }
            try JSONFile.save(renamed, to: url, createParents: false)
            if let name {
                var people = KnownPeople.load(root: paths.root)
                people.use(name)
                try people.save(root: paths.root)
            }
            reloadSessions()
        } catch { lastError = String(localized: "Couldn't rename speaker: \(error.localizedDescription)") }
    }

    static func sessionName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return f.string(from: d) + "-" + UUID().uuidString.prefix(4).lowercased()
    }
}

extension AppModel: RecordingActivity {
    /// Nagrywanie albo przenoszenie nagrań: restart w tym czasie zepsułby dane.
    var isBusy: Bool { recording.isRecording || recordingsMove != nil }
}

/// Bramki startu transkrypcji, wydzielone z `AppModel.run`, bo `AppModel` nie da się zbudować w teście.
enum TranscriptionStartGate {
    /// Odmowa (powód) albo `nil` i sesja zapisana jako transkrybowana, przed pierwszym `await`.
    @MainActor static func begin(sessionURL: URL, notes: NotesModel, moving: Bool) -> String? {
        let id = sessionURL.lastPathComponent
        if let refusal = refusal(sessionURL: sessionURL, transcribing: notes.isTranscribing(id), correcting: notes.isCorrecting(id),
                                 generating: notes.state(id) == .generating, moving: moving) { return refusal }
        notes.transcribing.insert(id)
        return nil
    }

    private static func refusal(sessionURL: URL, transcribing: Bool, correcting: Bool, generating: Bool, moving: Bool) -> String? {
        if transcribing { return String(localized: "This recording is already being transcribed.") }
        if moving { return String(localized: "Meetings are being moved to a new folder. Transcribe when that finishes.") }
        // Nowy przebieg w trakcie korekty: korekta starego tekstu nadpisałaby wynik albo poszłaby druga (F2, jak w `resume`).
        if correcting { return String(localized: "This transcript is being corrected. Try again when that finishes.") }
        // Po przebiegu ruszyłaby autokorekta obok notatki (ten sam lokalny serwer), a notatka ze starego tekstu nadpisałaby nowe.
        if generating { return String(localized: "Notes are being generated for this meeting. Try again when that finishes.") }
        // Bez audio przebieg utworzyłby pusty `runs/<id>/` jako najnowszą próbę (wznowienie, retencja) bez szans na transkrypt.
        guard AudioRetention.audioFiles(sessionURL).isEmpty else { return nil }
        if let deletion = AudioDeletion.read(sessionURL) { return String(format: NSLocalizedString("This meeting's audio was deleted after %lld days, so it can't be transcribed again.", comment: ""), locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"), Int64(deletion.afterDays)) }
        return String(localized: "This meeting's audio was deleted, so it can't be transcribed again.")
    }
}

/// Stare migawki zachowują identyczne wejście runnera; tylko żądanie klienta dostaje jawne ID v3.
private struct LegacyLocalASRClient: TranscriptionClient, ReleasableClient {
    let inner: any TranscriptionClient
    let legacyModel: String
    var provider: Provider { inner.provider }

    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        try await inner.transcribe(wav: wav, model: model == legacyModel ? LocalASRModels.parakeetV3 : model, language: language, shape: shape)
    }

    func release() async { await (inner as? any ReleasableClient)?.release() }
}
