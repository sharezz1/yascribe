import AVFoundation
import Foundation
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
import MeetNotesTranscription
import Observation

enum Section: String, CaseIterable, Identifiable {
    case meetings = "Meetings", tasks = "Tasks", dictation = "Dictation", dictionary = "Dictionary"
    case presets = "Presets", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .meetings: "waveform"
        case .tasks: "checklist"
        case .dictation: "keyboard"
        case .dictionary: "book"
        case .presets: "slider.horizontal.3"
        case .settings: "gearshape"
        }
    }
}

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

    var duration: Double? {
        guard let t = summary?.tracks.first(where: { $0.id == "system" }) ?? summary?.tracks.first,
              let f = t.frames, t.sampleRate > 0 else { return nil }
        return Double(f) / t.sampleRate
    }
}

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
    var models: [UUID: [ModelInfo]] = [:]
    var sessions: [SessionItem] = []
    var selectedSessionID: String?
    var activePresetID: UUID?
    var lastError: String?
    var showSetup = false

    let recording = RecordingController()

    init() {
        load()
        // ChatGPT #16: setup także wtedy, gdy dźwięk systemowy nigdy nie przeszedł testu tonem.
        showSetup = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || !UserDefaults.standard.bool(forKey: "systemAudioVerified")
    }

    var activePreset: Preset? {
        presets.presets.first { $0.id == (activePresetID ?? settings.defaultPresetID) } ?? presets.presets.first
    }

    func provider(_ id: UUID?) -> Provider? { providers.providers.first { $0.id == id } }

    func load() {
        do {
            providers = try JSONFile.load(ProvidersFile.self, from: paths.providers, default: ProvidersFile())
            presets = try JSONFile.load(PresetsFile.self, from: paths.presets, default: PresetsFile())
            settings = try JSONFile.load(GlobalSettings.self, from: paths.settings, default: GlobalSettings())
            probeCache = try JSONFile.load(ProbeCache.self, from: paths.probeCache, default: ProbeCache())
        } catch {
            lastError = "Couldn't read your settings: \(error)"
        }
        reloadSessions()
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
        let dirs = (try? fm.contentsOfDirectory(at: paths.sessions, includingPropertiesForKeys: nil)) ?? []
        sessions = dirs.compactMap { url -> SessionItem? in
            let sd = SessionDirectory(url: url)
            guard fm.fileExists(atPath: sd.journalURL.path) else { return nil }
            let summary = try? sd.summarize()
            let run = latestRun(in: url)
            return SessionItem(url: url, summary: summary, startedAt: summary?.wallClock ?? .distantPast,
                               transcript: run?.transcript, runID: run?.id)
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func latestRun(in session: URL) -> (id: String, transcript: Transcript?)? {
        let runs = session.appendingPathComponent("runs")
        guard let id = ((try? FileManager.default.contentsOfDirectory(atPath: runs.path)) ?? []).sorted().last else { return nil }
        return (id, try? JSONFile.load(Transcript?.self, from: RunDirectory(session: session, runID: id).transcript, default: nil))
    }

    // MARK: Dostawcy

    func client(for providerID: UUID) -> OpenAICompatibleClient? {
        guard let p = provider(providerID) else { return nil }
        return OpenAICompatibleClient(provider: p, key: try? secrets.get(p.id))
    }

    func addProvider(name: String, baseURL: URL, key: String) {
        let p = Provider(name: name, baseURL: baseURL)
        do {
            if !key.isEmpty { try secrets.set(p.id, key) }
            providers.providers.append(p)
            save()
        } catch {
            lastError = "Couldn't store the key in Keychain: \(error)"
        }
    }

    func removeProvider(_ id: UUID) {
        try? secrets.delete(id)
        providers.providers.removeAll { $0.id == id }
        save()
    }

    func refreshModels(_ id: UUID) async {
        guard let c = client(for: id) else { return }
        do { models[id] = try await c.listModels() } catch { lastError = "Couldn't refresh models: \(error)" }
    }

    func probe(providerID: UUID, model: String, role: Role, language: LanguageCode?) async {
        guard let c = client(for: providerID) else { return }
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
            return "Choose a language. Presets never detect it automatically."
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
        // ChatGPT #2: preset — z językiem — ustalony PRZED startem i zamrożony na całą sesję.
        guard let preset = activePreset, (try? preset.validate()) != nil else {
            lastError = "Choose a preset with a language before recording."
            section = .presets
            return
        }
        let dir = paths.sessions.appendingPathComponent(Self.sessionName(Date()))
        do {
            try recording.start(directory: dir, presetLabel: Self.label(preset)) { [weak self] _ in
                Task { @MainActor in
                    self?.reloadSessions()
                    self?.transcribe(sessionURL: dir, preset: preset)
                }
            }
            try? JSONFile.save(preset, to: dir.appendingPathComponent("preset.json"))
            recording.showPanel(model: self)
            reloadSessions()
        } catch {
            lastError = "Couldn't start recording: \(error)"
        }
    }

    static func label(_ p: Preset) -> String { "\(p.name) · \(p.language?.rawValue.uppercased() ?? "?")" }

    func transcribe(sessionURL: URL, preset: Preset) {
        guard let asr = preset.asr, let provider = provider(asr.providerID), let c = client(for: asr.providerID) else {
            lastError = "The preset's speech-to-text provider is missing."
            return
        }
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
              let input = try? JSONFile.load(RunInput?.self, from: RunDirectory(session: item.url, runID: runID).input, default: nil),
              let c = client(for: input.snapshot.providerID) else {
            lastError = "Nothing to resume for this recording."
            return
        }
        run(sessionURL: item.url, runID: runID, snapshot: input.snapshot, client: c)
    }

    private func run(sessionURL: URL, runID: String, snapshot: RunSnapshot, client c: OpenAICompatibleClient) {
        let id = sessionURL.lastPathComponent
        Task {
            do {
                _ = try await TranscriptionRunner(session: sessionURL, runID: runID, snapshot: snapshot, client: c).run { p in
                    Task { @MainActor in
                        if let i = self.sessions.firstIndex(where: { $0.id == id }) { self.sessions[i].progress = p.fraction }
                    }
                }
            } catch {
                self.lastError = "Transcription failed: \(error)"
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
