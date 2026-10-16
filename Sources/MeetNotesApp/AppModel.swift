import AppKit
import AVFoundation
import Foundation
import MeetNotesNotes
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
import MeetNotesTranscription
import Observation

enum Section: String, CaseIterable, Identifiable {
    case meetings = "Meetings", tasks = "Tasks", dictation = "Dictation", dictionary = "Dictionary"
    case presets = "Presets", templates = "Templates", settings = "Settings"
    var id: String { rawValue }
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
    /// Ostatni przebieg transkrypcji — do wznowienia po przerwie albo restarcie (ChatGPT #17).
    var runID: String?
    var corrected: CorrectedTranscript?
    var notes = SessionNotes()
    /// Retencja usunęła audio po tylu dniach (`<sesja>/audio-deleted.json`); `nil` = audio nie było kasowane.
    /// Widok spotkania: „Audio deleted after N days”, bez odtwarzania i ponownej transkrypcji.
    var audioDeletedAfterDays: Int?

    /// Ręczny > auto > tytuł z notatki > „Untitled meeting".
    var title: String { NoteTitle.display(meta: notes.meta, noteTitle: notes.summary?.title) }

    /// Transkrypt do wyświetlenia i streszczenia: poprawiony, gdy jest i użytkownik go nie wyłączył.
    func transcript(corrected useCorrected: Bool) -> Transcript? {
        useCorrected ? (corrected?.transcript ?? transcript) : transcript
    }

    var duration: Double? {
        guard let t = summary?.tracks.first(where: { $0.id == "system" }) ?? summary?.tracks.first,
              let f = t.frames, t.sampleRate > 0 else { return nil }
        return Double(f) / t.sampleRate
    }
}

/// Klucz listy modeli: dostawca + modalność wyjścia (`filter == ""` = lista domyślna).
struct ModelListKey: Hashable { var provider: UUID; var filter: String }

@MainActor
@Observable
final class AppModel {
    let paths = MeetNotesPaths.fromEnvironment()
    let secrets: any SecretStore = KeychainSecretStore()

    var section: Section = .meetings
    var providers = ProvidersFile()
    var presets = PresetsFile()
    var settings = GlobalSettings()
    var probeCache = ProbeCache()
    var sessions: [SessionItem] = []
    var selectedSessionID: String?
    var activePresetID: UUID?
    var lastError: String?
    var showSetup = false
    /// Spotkanie czekające na potwierdzenie usunięcia (przycisk „⋯” i menu Meeting) — dialog jest w `MeetingDetailView`.
    var pendingDelete: String?
    /// Sesje z trwającym przebiegiem — drugi przebieg tej samej sesji płaciłby za te same okna (check S15 #2).
    private(set) var transcribing: Set<String> = []

    let recording = RecordingController()
    let notes = NotesModel()

    init() {
        load()
        // ChatGPT #16: setup także wtedy, gdy dźwięk systemowy nigdy nie przeszedł testu tonem.
        showSetup = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || !UserDefaults.standard.bool(forKey: "systemAudioVerified")
        notes.clientFor = { [weak self] in self?.client(for: $0) }
        notes.presetFor = { [weak self] in self?.presetFor(sessionURL: $0) }
        notes.report = { [weak self] in self?.lastError = $0 }
        notes.presetsInfo = { [weak self] in (self?.presets.presets ?? [], self?.settings.defaultPresetID) }
        notes.onChange = { [weak self] in self?.reloadSessions() }
        notes.isMoving = { [weak self] in self?.recordingsMove != nil }
        applyRetention()
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
                errors.append("Couldn't read \(name) (\(moved ? "moved to \(aside.lastPathComponent)" : "couldn't move it aside")): \(error)")
                return fallback
            }
        }
        providers = read(paths.providers, ProvidersFile())
        presets = read(paths.presets, PresetsFile())
        settings = read(paths.settings, GlobalSettings())
        probeCache = read(paths.probeCache, ProbeCache())
        notes.templates = read(paths.templates, TemplatesFile())
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
        var s = transcribing.union(notes.correcting).union(notes.titling)
        s.formUnion(notes.generation.filter { $0.value == .generating }.keys)
        if let d = recording.directory { s.insert(d.lastPathComponent) }
        return s
    }

    /// Powód, dla którego teraz nie wolno zmienić lokalizacji; `nil` = wolno.
    var recordingsMoveBlocked: String? {
        let busy = !transcribing.isEmpty || !notes.correcting.isEmpty || !notes.titling.isEmpty
            || notes.generation.values.contains(.generating)
        return RecordingsMove.blocked(recording: recording.isRecording, busy: busy, moving: recordingsMove != nil)
    }

    /// Przy starcie i po zmianie „Keep audio”. Nie w trybie migawek i nie w trakcie przenoszenia.
    func applyRetention() {
        guard Snapshots.directory == nil, recordingsMove == nil else { return }
        let r = AudioRetention.apply(sessions: sessionsDirectory, days: settings.audioRetentionDays, skip: busySessions)
        if !r.errors.isEmpty { lastError = "Couldn't delete old audio: " + r.errors.joined(separator: "\n") }
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
            recordingsMoveResult = (false, reason)
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
                    : (true, "Couldn't remove these from the old folder: \(leftovers.joined(separator: ", ")). The copies in the new folder are complete.")
            } catch {
                outcome = (false, "\(error)")
            }
            await MainActor.run {
                self.recordingsMove = nil
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
            lastError = "Couldn't save your settings: \(error)"
        }
    }

    func reloadSessions() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? []
        sessions = dirs.compactMap { url -> SessionItem? in
            let sd = SessionDirectory(url: url)
            guard fm.fileExists(atPath: sd.journalURL.path) else { return nil }
            let summary = try? sd.summarize()
            let run = latestRun(in: url)
            let store = NotesStore(session: url)
            var item = SessionItem(url: url, summary: summary, startedAt: summary?.wallClock ?? .distantPast,
                                   transcript: run?.transcript, runID: run?.id)
            item.corrected = Self.loadCorrected(url, run?.id)
            item.audioDeletedAfterDays = AudioDeletion.read(url)?.afterDays
            item.notes = SessionNotes(myNotes: store.readMyNotes(), meta: store.readMeta(),
                                      summary: (try? store.readSummary()) ?? nil, problems: store.problems())
            return item
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func latestRun(in session: URL) -> (id: String, transcript: Transcript?)? {
        guard let id = RunDirectory.latestRunID(in: session) else { return nil }
        // Echo oznaczamy też na starszych transkryptach (idempotentne, bez zapisu pliku).
        let t = (try? JSONFile.load(Transcript?.self, from: RunDirectory(session: session, runID: id).transcript, default: nil)) ?? nil
        return (id, t?.echoMarked())
    }

    static func loadCorrected(_ session: URL, _ runID: String?) -> CorrectedTranscript? {
        guard let runID, RunDirectory.isValid(runID: runID) else { return nil }
        guard var c = (try? JSONFile.load(CorrectedTranscript?.self, from: RunDirectory(session: session, runID: runID).corrected, default: nil)) ?? nil else { return nil }
        c.transcript = c.transcript.echoMarked() // korekta sprzed filtra echa nie niesie znacznika
        return c
    }

    // MARK: Dostawcy

    /// nil = nie da się wysłać żądania (błąd w `lastError`): brak dostawcy, błąd Keychain albo brak klucza (check S15 #5).
    func client(for providerID: UUID) -> OpenAICompatibleClient? {
        switch makeClient(for: providerID) {
        case .success(let c): return c
        case .failure(let problem):
            lastError = problem.message
            return nil
        }
    }

    struct ClientProblem: Error { let message: String }

    /// Dostawca z kluczem albo powód, dlaczego nie da się do niego wysłać żądania.
    private func providerWithKey(_ providerID: UUID) -> Result<(Provider, String?), ClientProblem> {
        guard let p = provider(providerID) else { return .failure(ClientProblem(message: "This provider no longer exists.")) }
        let key: String?
        do { key = try secrets.get(p.id) } catch {
            return .failure(ClientProblem(message: "Couldn't read the API key for \(p.name) from Keychain: \(error)"))
        }
        // ponytail: „lokalny = bez klucza" po nazwie hosta; jawna flaga w Provider, gdy zdalny dostawca obejdzie się bez klucza.
        guard key != nil || (p.api == .openAICompatible && ["localhost", "127.0.0.1", "::1"].contains(p.baseURL.host() ?? "")) else {
            return .failure(ClientProblem(message: "No API key for \(p.name). Remove the provider and add it again with a key."))
        }
        return .success((p, key))
    }

    /// Klient OpenAI-compatible (listy modeli, czat, embeddingi) albo powód — bez alertu (weryfikacja dostawcy
    /// pokazuje powód przy dostawcy). ElevenLabs tu nie pasuje: robi tylko transkrypcję (`transcriptionClient`).
    func makeClient(for providerID: UUID) -> Result<OpenAICompatibleClient, ClientProblem> {
        providerWithKey(providerID).flatMap { p, key in
            p.api == .openAICompatible ? .success(OpenAICompatibleClient(provider: p, key: key))
                : .failure(ClientProblem(message: "\(p.name) does only speech-to-text."))
        }
    }

    /// Klient transkrypcji wybrany po `Provider.api`; nil = powód w `lastError`.
    func transcriptionClient(for providerID: UUID) -> (any TranscriptionClient)? {
        switch providerWithKey(providerID) {
        case .success(let (p, key)): return p.transcriptionClient(key: key)
        case .failure(let problem):
            lastError = problem.message
            return nil
        }
    }

    /// Test połączenia (`listModels`, u ElevenLabs `GET /v1/models`): Verified albo powód (zły klucz, guardrail, adres,
    /// serwer wyłączony).
    func verifyProvider(_ id: UUID) async {
        providerChecks[id] = nil
        providerVerifying.insert(id)
        defer { providerVerifying.remove(id) }
        switch providerWithKey(id) {
        case .failure(let problem): providerChecks[id] = .failed(problem.message)
        case .success(let (p, key)): providerChecks[id] = await p.verify(key: key)
        }
    }

    /// `nil` = dodano; tekst = powód odmowy (duplikat nazwy albo błąd pęku kluczy).
    func addProvider(name: String, baseURL: URL, key: String, kind: ProviderKind? = nil) -> String? {
        if let e = providers.nameError(name) { return e }
        let p = Provider(name: name.trimmingCharacters(in: .whitespaces), baseURL: baseURL, kind: kind)
        do {
            if !key.isEmpty { try secrets.set(p.id, key) }
            providers.providers.append(p)
            save()
            Task { await verifyProvider(p.id) } // Verified albo powód przy dostawcy
            return nil
        } catch {
            return "Couldn't store the key in Keychain: \(error)"
        }
    }

    /// Poprawka klucza już zapisanego dostawcy (formularz „Save & verify" po błędzie): zapis i ponowna weryfikacja.
    /// `nil` = zapisano; tekst = błąd pęku kluczy. Pusty klucz (Ollama) tylko weryfikuje ponownie.
    func replaceKey(_ id: UUID, key: String) -> String? {
        do { if !key.isEmpty { try secrets.set(id, key) } } catch { return "Couldn't store the key in Keychain: \(error)" }
        Task { await verifyProvider(id) }
        return nil
    }

    /// „Test connection" w arkuszu PRZED zapisem: klient z kluczem z pola (w pamięci, nic nie trafia do pęku kluczy).
    /// ElevenLabs: klienta tworzy `makeClient` z zapisanego klucza, więc przed zapisem testu nie ma (`nil`) — arkusz weryfikuje po Save.
    nonisolated static func testConnection(baseURL: URL, kind: ProviderKind?, key: String) async -> ProviderCheck {
        // Klucz z pola, w pamięci — bez zapisu do pęku (Cancel nie zostawia klucza). Klient wg rodzaju API.
        await Provider(name: "test", baseURL: baseURL, kind: kind).verify(key: key.isEmpty ? nil : key)
    }

    func removeProvider(_ id: UUID) {
        try? secrets.delete(id)
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
        let k = key(provider, role)
        if self.provider(provider)?.api == .elevenLabs { // stała lista (Scribe v2 dla ASR, poza tym pusto), bez sieci
            modelLists[k] = ElevenLabsClient.models(for: role)
            return
        }
        guard force || modelLists[k] == nil, !loadingModels.contains(k), let c = client(for: provider) else { return }
        loadingModels.insert(k)
        defer { loadingModels.remove(k) }
        do { modelLists[k] = try await c.listModels(output: ModelCatalog.outputFilter(for: role)) } catch {
            lastError = "Couldn't load models: \(error)"
        }
    }

    /// Przycisk „Refresh Models" w Settings: transkrypcja, embeddingi i lista tekstowa.
    func refreshModels(_ id: UUID) async {
        for role in [Role.asr, .embedding, .summary] { await loadModels(provider: id, role: role, force: true) }
    }

    func probe(providerID: UUID, model: String, role: Role, language: LanguageCode?) async {
        guard let c = transcriptionClient(for: providerID) else { return }
        let r = await ProbeRunner(client: c).probe(model: model, role: role, language: language)
        probeCache.record(r)
        save()
    }

    // MARK: Presety

    func savePreset(_ p: Preset) -> String? {
        do {
            if let a = p.asr, probeCache.result(provider: a.providerID, model: a.model, role: .asr, language: p.language)?.shape == .chatAudio {
                return "This model returns no word timings, so it can't be used for meetings."
            }
            try presets.upsert(p)
            if settings.defaultPresetID == nil { settings.defaultPresetID = p.id }
            save()
            return nil
        } catch PresetError.missingLanguage {
            return "Choose a language, or Auto for meetings that mix languages."
        } catch PresetError.missingASR {
            return "Choose a speech-to-text model."
        } catch PresetError.missingName {
            return "Give the preset a name."
        } catch {
            return "\(error)"
        }
    }

    // MARK: Nagrywanie i transkrypcja

    func startRecording() {
        guard !recording.isRecording else {
            lastError = "A recording is already in progress."
            return
        }
        guard recordingsMove == nil else {
            lastError = "Meetings are being moved to a new folder. Record when that finishes."
            return
        }
        // ChatGPT #2: preset — z językiem — ustalony PRZED startem i zamrożony na całą sesję.
        guard let preset = activePreset, (try? preset.validate()) != nil else {
            lastError = "Choose a preset with a language before recording."
            section = .presets
            return
        }
        let dir = sessionsDirectory.appendingPathComponent(Self.sessionName(Date()))
        do {
            try recording.start(directory: dir, presetLabel: Self.label(preset)) { [weak self] _ in
                Task { @MainActor in
                    self?.reloadSessions()
                    self?.transcribe(sessionURL: dir, preset: preset)
                }
            }
            // Nagranie trwa mimo błędu zapisu — ten przebieg i tak dostaje `preset` z domknięcia.
            do { try JSONFile.save(preset, to: dir.appendingPathComponent("preset.json")) } catch {
                lastError = "Recording, but couldn't save its preset: \(error). After a restart it will use the active preset."
            }
            recording.showPanel(model: self)
            reloadSessions()
            openSession(dir.lastPathComponent) // notatki pisze się w trakcie spotkania
        } catch {
            lastError = "Couldn't start recording: \(error)"
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

    /// Sesji nagrywanej ani transkrybowanej nie usuwamy (katalog jest w użyciu); w trakcie przenoszenia żadnej (R3).
    func canDelete(_ item: SessionItem) -> Bool {
        recordingsMove == nil && !SessionStatus.isRecording(item.url, recordingDirectory: recording.directory) && !isTranscribing(item)
    }

    func copyNotes(_ item: SessionItem) {
        guard let md = item.notes.summary?.markdown else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    func showInFinder(_ item: SessionItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    /// Do Kosza, nie trwale. Wraca do listy i przeładowuje ją; błąd trafia do `lastError`.
    func deleteSession(_ id: String) {
        pendingDelete = nil
        guard let item = sessions.first(where: { $0.id == id }), canDelete(item) else { return }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            if selectedSessionID == id { selectedSessionID = nil }
        } catch {
            lastError = "Couldn't move the meeting to the Trash: \(error.localizedDescription)"
        }
        reloadSessions()
    }

    /// Zapis własnych szablonów; `nil` = zapisano, tekst = powód.
    func saveTemplates() -> String? {
        do { try JSONFile.save(notes.templates, to: paths.templates); return nil } catch { return "Couldn't save templates: \(error)" }
    }

    func isTranscribing(_ item: SessionItem) -> Bool { transcribing.contains(item.id) }

    static func label(_ p: Preset) -> String { "\(p.name) · \(p.languageLabel)" }

    func transcribe(sessionURL: URL, preset: Preset) {
        guard let asr = preset.asr, let provider = provider(asr.providerID) else {
            lastError = "The preset's speech-to-text provider is missing."
            return
        }
        guard let c = transcriptionClient(for: asr.providerID) else { return } // powód już w lastError
        let probe = probeCache.result(provider: asr.providerID, model: asr.model, role: .asr, language: preset.language)
        do {
            let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: probe)
            run(sessionURL: sessionURL, runID: Self.sessionName(Date()), snapshot: snapshot, client: c)
        } catch RunSnapshotError.chatShapeNotForMeetings {
            lastError = "This model returns no word timings, so it can't be used for meetings."
        } catch {
            lastError = "\(error)"
        }
    }

    /// ChatGPT #17: wznowienie w aplikacji, także po restarcie — ten sam runID i ta sama
    /// migawka z `input.json`, więc opłacone okna nie idą drugi raz (P5).
    func resume(_ item: SessionItem) {
        guard let runID = item.runID,
              let input = try? JSONFile.load(RunInput?.self, from: RunDirectory(session: item.url, runID: runID).input, default: nil) else {
            lastError = "Nothing to resume for this recording."
            return
        }
        guard let c = transcriptionClient(for: input.snapshot.providerID) else { return } // powód już w lastError
        run(sessionURL: item.url, runID: runID, snapshot: input.snapshot, client: c)
    }

    private func run(sessionURL: URL, runID: String, snapshot: RunSnapshot, client c: any TranscriptionClient) {
        let id = sessionURL.lastPathComponent
        guard !transcribing.contains(id) else {
            lastError = "This recording is already being transcribed."
            return
        }
        guard recordingsMove == nil else {
            lastError = "Meetings are being moved to a new folder. Transcribe when that finishes."
            return
        }
        // Bez audio przebieg utworzyłby pusty `runs/<id>/`, który przesłoniłby gotowy transkrypt (najnowszy przebieg wygrywa).
        guard !AudioRetention.audioFiles(sessionURL).isEmpty else {
            let days = AudioDeletion.read(sessionURL).map { " after \($0.afterDays) days" } ?? ""
            lastError = "This meeting's audio was deleted\(days), so it can't be transcribed again."
            return
        }
        transcribing.insert(id)
        Task {
            var finished: Transcript?
            do {
                finished = try await TranscriptionRunner(session: sessionURL, runID: runID, snapshot: snapshot, client: c).run { p in
                    Task { @MainActor in
                        if let i = self.sessions.firstIndex(where: { $0.id == id }) { self.sessions[i].progress = p.fraction }
                    }
                }
            } catch {
                self.lastError = "Transcription failed: \(error)"
            }
            self.transcribing.remove(id)
            self.reloadSessions()
            if let finished {
                await self.notes.afterTranscription(sessionURL: sessionURL, runID: runID, snapshot: snapshot, transcript: finished)
            }
            self.reloadSessions()
        }
    }

    static func sessionName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return f.string(from: d) + "-" + UUID().uuidString.prefix(4).lowercased()
    }
}
