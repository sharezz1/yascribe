import AppKit
import MeetNotesLocalASR
import MeetNotesMeetings
import MeetNotesNotes
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
import MeetNotesTranscription
import SwiftUI

/// Tryb migawek (macos.md §9): `MEETNOTES_SNAPSHOT_DIR=<katalog>` renderuje ekrany do PNG i kończy proces.
/// Dowód w raporcie: „migawka" (ten plik), nie „zrzut na żywo".
enum SnapshotError: Error { case noBitmap, noPNG }

@MainActor
enum Snapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["MEETNOTES_SNAPSHOT_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    static func render<V: View>(_ name: String, size: CGSize, dark: Bool, model: AppModel,
                                @ViewBuilder _ content: () -> V) throws {
        let host = NSHostingView(rootView: content().environment(model).frame(width: size.width, height: size.height)
            // Spike T0: bez tła okna PNG ma przezroczyste tło — w ciemnym trybie jasny tekst znika na białym podglądzie.
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        // Spike T0: `.titled` + `.toolbar` w widoku dokłada ~28 pt pasa u góry; `.borderless` daje dokładny rozmiar (bez paska narzędzi).
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SnapshotError.noBitmap }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.noPNG }
        // `directory!` jest bezpieczne: `render` woła tylko `runAll`, a `runAll` startuje z `init()` dopiero po sprawdzeniu
        // `directory != nil`. Wywołanie `render` z innego miejsca wymaga guarda.
        try FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        try png.write(to: directory!.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    /// Fixture: presety i dostawca zapisane do katalogu danych, potem `load()`. Kolejne zadania dopisują sesje i stany.
    /// Sesja z dysku: rejestrator z próbek, potem transkrypt i notatki zapisane jak w aplikacji.
    static func seedSession(_ model: AppModel, name: String, transcriptJSON: String?, notes: NoteSummary?, myNotes: String = "") throws {
        let dir = model.sessionsDirectory.appendingPathComponent(name)
        let tb = Timebase(numer: 1, denom: 1)
        let src = FileSource(trackID: "system", samples: [Int16](repeating: 0, count: 16_000 * 60), sampleRate: 16_000, channels: 1,
                             startHostTime: 1_000_000_000, timebase: tb, chunkFrames: 1_600)
        try SessionRecorder(directory: dir, sources: [src], conditions: [], clock: ManualHostClock(), timebase: tb, zeroWatch: [:]).start()
        if let transcriptJSON {
            let run = dir.appendingPathComponent("runs/2026-10-14-1000")
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            try transcriptJSON.write(to: run.appendingPathComponent("transcript.json"), atomically: true, encoding: .utf8)
        }
        let store = NotesStore(session: dir)
        if !myNotes.isEmpty { try store.writeMyNotes(myNotes) }
        if let notes { try store.writeSummary(notes) }
    }

    static let sampleTranscript = """
    {"utterances":[
      {"speaker":"them","start":3,"end":9,"text":"so what we have is the forecast built without manual changes, around nine thousand on Saturday","words":[],"approximateTiming":false},
      {"speaker":"me","start":12,"end":16,"text":"and on Sunday it is almost four thousand, why more agents scheduled?","words":[],"approximateTiming":false},
      {"speaker":"them","start":20,"end":27,"text":"Piotr will check the staffing rules and send the corrected schedule by Friday","words":[],"approximateTiming":false}
    ],"failedChunks":[]}
    """

    static func seed(_ model: AppModel) throws {
        let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        var presets = PresetsFile()
        try presets.upsert(Preset(name: "Polish", language: .polish,
                                  asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2"),
                                  summary: RoleAssignment(providerID: provider.id, model: "deepseek/deepseek-v4.1-flash")))
        try JSONFile.save(ProvidersFile(providers: [provider]), to: model.paths.providers)
        try JSONFile.save(presets, to: model.paths.presets)
        let notes = NoteSummary(title: "Scheduling forecast discrepancy with Piotr", markdown: """
            The team reviewed the schedule built on the forecast and found Sunday staffed higher than Saturday despite lower volume.

            ## Forecast vs. schedule
            - Saturday: about **9 000** contacts expected, schedule built without manual changes
            - Sunday: almost **4 000**, yet more agents scheduled than on Saturday
              - Cause not yet known

            ## Next Steps
            - **Check the staffing rules** (Piotr) — the Sunday allocation looks inconsistent with the forecast.
            - **Send the corrected schedule** (Piotr) — due Friday so the team can confirm shifts.
            """, templateID: "standard", model: "deepseek/deepseek-v4.1-flash", context: "Piotr, Adrian", generatedAt: Date())
        try seedSession(model, name: "2026-10-14T10-00-00Z-aa11", transcriptJSON: sampleTranscript, notes: notes, myNotes: "ask about Sunday staffing")
        try seedSession(model, name: "2026-10-14T09-00-00Z-bb22", transcriptJSON: sampleTranscript, notes: nil)
        try seedSession(model, name: "2026-10-13T16-00-00Z-cc33", transcriptJSON: nil, notes: nil)
        model.load()
        model.showSetup = false
    }

    static func runAll(model: AppModel) {
        do {
            try seed(model)
            for dark in [false, true] {
                // Galeria komponentów §11.4 (DesignSystem.swift) — jeden rzut oka na tokeny i stany przed widokami.
                try render("components", size: CGSize(width: 640, height: 520), dark: dark, model: model) { ComponentGallery() }
                // D7: sidebar osobno (całe okno z NavigationSplitView renderuje się offscreen jako pusta plansza, T3).
                try render("sidebar", size: CGSize(width: 210, height: 500), dark: dark, model: model) {
                    SidebarList(selection: .constant(.settings)).listStyle(.sidebar)
                }
                try render("presets", size: CGSize(width: 900, height: 600), dark: dark, model: model) { PresetsView() }
                try render("meetings", size: CGSize(width: 900, height: 600), dark: dark, model: model) { MeetingsView() }
                // Pola tekstowe: PresetsView bez wyboru pokazuje tylko „Choose a preset" (wybór jest lokalny w widoku).
                let form = PresetEditorState()
                form.draft = model.presets.presets.first
                try render("preset-form", size: CGSize(width: 700, height: 600), dark: dark, model: model) { PresetForm(state: form).contentBackground() }
                // T3: preset wybrany (lista + edytor obok siebie) oraz całe okno z sidebarem — bliższe temu, co widać na żywo.
                let editing = PresetEditorState()
                editing.select(model.presets.presets.first)
                try render("presets-editing", size: CGSize(width: 900, height: 640), dark: dark, model: model) { PresetsView(state: editing) }
                // T8: lista z kartą Record i trzy stany spotkania (notatki / karta Generate / My notes bez transkryptu).
                try render("meetings-full", size: CGSize(width: 900, height: 600), dark: dark, model: model) { MeetingsView() }
                // §11.5 „Coming up” (b-cuB2.png): 9:52, standup za 8 min, reszta dnia; całodniowe i OOO odfiltrowane.
                let nine = Calendar.current.date(bySettingHour: 9, minute: 52, second: 0, of: Date())!
                func ev(_ title: String, _ h: Int, _ m: Int, _ minutes: Double, link: Bool = true, people: Int = 0, allDay: Bool = false) -> CalendarEventInfo {
                    let start = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: nine)!
                    return CalendarEventInfo(title: title, start: start, end: start + minutes * 60, isAllDay: allDay,
                                             notes: link ? "Join: https://teams.microsoft.com/meet/123" : nil,
                                             attendees: (0..<people).map { .init(name: "Person \($0)") })
                }
                let day = [ev("WFM daily standup", 10, 0, 30, people: 6), ev("Scheduling forecast review", 11, 30, 60),
                           ev("Dentist", 14, 0, 45, link: false), ev("1:1 Adrian", 16, 0, 30),
                           ev("Ada's birthday", 0, 0, 24 * 60, link: false, allDay: true), ev("Out of office", 0, 0, 72 * 60, link: false)]
                let next = MeetingsViewState(); next.preview = (true, day, nine)
                try render("meetings-next", size: CGSize(width: 900, height: 600), dark: dark, model: model) { MeetingsView(state: next) }
                // b-cuB2none.png: po ostatnim spotkaniu dnia — linia „No more meetings today”, Record w nagłówku primary.
                let none = MeetingsViewState(); none.preview = (true, day, Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: nine)!)
                try render("meetings-none", size: CGSize(width: 900, height: 600), dark: dark, model: model) { MeetingsView(state: none) }
                // Nic w 60 min, ale coś później: linia „Later today: …” zamiast „No more meetings today”.
                let gap = MeetingsViewState(); gap.preview = (true, day, Calendar.current.date(bySettingHour: 12, minute: 40, second: 0, of: nine)!)
                try render("meetings-later", size: CGSize(width: 900, height: 600), dark: dark, model: model) { MeetingsView(state: gap) }
                if let withNotes = model.sessions.first(where: { $0.id.hasSuffix("aa11") }),
                   let transcriptOnly = model.sessions.first(where: { $0.id.hasSuffix("bb22") }),
                   let empty = model.sessions.first(where: { $0.id.hasSuffix("cc33") }) {
                    let summaryTab = MeetingViewState(); summaryTab.tab = .summary
                    try render("meeting-summary", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: withNotes, state: summaryTab) }
                    // UX po T13: notatka z podziału (linia „Long meeting"), generowanie z postępem i „Cancel", korekta blokuje generowanie.
                    // Fixture nie ładuje transkryptu z dysku; bez niego „Generate notes" jest nieaktywne z innego powodu.
                    var split = withNotes; split.notes.summary?.condensedParts = 4
                    split.transcript = try JSONDecoder().decode(Transcript.self, from: Data(sampleTranscript.utf8))
                    try render("meeting-summary-split", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: split, state: summaryTab) }
                    var unwritten = split; unwritten.notes.summary = nil
                    model.notes.setPreview(unwritten.id, generating: .condensing(pass: 1, part: 3, of: 6))
                    try render("meeting-summary-generating", size: CGSize(width: 900, height: 360), dark: dark, model: model) { MeetingDetailView(item: unwritten, state: summaryTab) }
                    model.notes.setPreview(unwritten.id, correcting: true)
                    try render("meeting-summary-correcting", size: CGSize(width: 900, height: 360), dark: dark, model: model) { MeetingDetailView(item: unwritten, state: summaryTab) }
                    model.notes.setPreview(unwritten.id)
                    model.notes.setPreview(split.id, generating: .condensing(pass: 2, part: 1, of: 2))
                    try render("meeting-summary-regenerating", size: CGSize(width: 900, height: 360), dark: dark, model: model) { MeetingDetailView(item: split, state: summaryTab) }
                    model.notes.setPreview(split.id, generating: .writing)
                    try render("meeting-summary-writing", size: CGSize(width: 900, height: 360), dark: dark, model: model) { MeetingDetailView(item: split, state: summaryTab) }
                    model.notes.setPreview(split.id)
                    // Uwaga 7: „Add context” rozwinięte w miejscu (pole rośnie z treścią).
                    let contextOpen = MeetingViewState(); contextOpen.tab = .summary; contextOpen.showContext = true
                    try render("meeting-summary-context", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: withNotes, state: contextOpen) }
                    // Faza 1.6 T12: okno „Select calendar event" (dane przykładowe) i nagłówek z powiązanym wydarzeniem.
                    let at = withNotes.startedAt
                    let sample = [CalendarEventInfo(title: "Weekly staffing review", start: at, end: at + 1800, attendees: [.init(name: "Piotr Nowak"), .init(name: "Ada Lis"), .init(email: "team@example.com"), .init(name: "Jan Kos")]),
                                  CalendarEventInfo(title: "Dentist (Main St clinic)", start: at - 5400, end: at - 3600, location: "Main St"),
                                  CalendarEventInfo(title: "Forecast sync", start: at + 7200, end: at + 9000)]
                    var linkedItem = withNotes; linkedItem.notes.meta.calendarEvent = sample[0].link()
                    let picker = EventPickerState(); picker.ready = true
                    picker.rows = EventRanking.order(sample, recordingStart: at, recordingEnd: at + 1800, now: at + 3600)
                    try render("event-picker", size: CGSize(width: 380, height: 360), dark: dark, model: model) {
                        EventPickerContent(state: picker, item: linkedItem, onPick: { _ in }, onUnlink: {}, onSettings: {})
                    }
                    let pickerOff = EventPickerState()
                    try render("event-picker-not-connected", size: CGSize(width: 380, height: 130), dark: dark, model: model) {
                        EventPickerContent(state: pickerOff, item: withNotes, onPick: { _ in }, onUnlink: {}, onSettings: {})
                    }
                    try render("meeting-linked-event", size: CGSize(width: 900, height: 300), dark: dark, model: model) { MeetingDetailView(item: linkedItem, state: summaryTab) }
                    // Uwaga 7 pkt 3: notatka bez proponowanej szerokości (sonda `fixedSize`) ma mieć 640 pt, nie ~250.
                    if let s = withNotes.notes.summary {
                        try render("meeting-note-unproposed", size: CGSize(width: 900, height: 360), dark: dark, model: model) {
                            MarkdownView(blocks: MarkdownBlocks.group(s.markdown)).fixedSize()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(20).contentBackground()
                        }
                    }
                    // Transcript (b-transcript.png): w pamięci echo w wypowiedzi „Me” i wersja poprawiona → linia „Corrected ⌄”.
                    var echoed = withNotes
                    if var t = echoed.transcript {
                        t.utterances[1].echoOfThem = true
                        echoed.transcript = t
                        echoed.corrected = CorrectedTranscript(transcript: t, model: "deepseek/deepseek-v4.1-flash", batches: 1, failedBatches: 0, rejectedLines: 0)
                    }
                    let transcriptTab = MeetingViewState(); transcriptTab.tab = .transcript
                    try render("meeting-transcript", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: echoed, state: transcriptTab) }
                    // 1.5b: mikrofon wyciszony w pigułce 0:17–0:19 → linia między wypowiedziami.
                    var mutedItem = echoed
                    var mic = SessionSummary.Track(id: "mic_raw", sampleRate: 16_000, channels: 1, frames: 16_000 * 60)
                    mic.mutes = [SessionSummary.Mute(frameIndex: 16_000 * 17, endFrame: 16_000 * 19)]
                    mutedItem.summary?.tracks.append(mic)
                    try render("meeting-transcript-muted", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: mutedItem, state: transcriptTab) }
                    // Summary przed generowaniem (b-summary0.png): pasek z „Generate notes” i linia stanu pustego.
                    let summary0 = MeetingViewState(); summary0.tab = .summary
                    try render("meeting-summary0", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: transcriptOnly, state: summary0) }
                    let myNotes = MeetingViewState(); myNotes.tab = .myNotes
                    try render("meeting-my-notes", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: empty, state: myNotes) }
                    // Odbiór 2026-10-16: sam autotytuł (bez ręcznego) w polu tytułu jako tekst (błąd 4); cisza systemu tylko
                    // przez pierwszą minutę = informacja (poprawka 6); długi transkrypt ze stałym paskiem vs krótkie My notes —
                    // kolumna w tym samym miejscu (błąd 5).
                    var autoTitled = transcriptOnly
                    autoTitled.notes.meta = NoteMeta(autoTitle: "Nowe normy Euro 7 i system OBM w samochodach")
                    if let i = autoTitled.summary?.tracks.firstIndex(where: { $0.id == "system" }) { autoTitled.summary?.tracks[i].failure = "allZeros60s" }
                    let autoNotes = MeetingViewState(); autoNotes.tab = .myNotes
                    try render("meeting-autotitle", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: autoTitled, state: autoNotes) }
                    if let t = autoTitled.transcript { autoTitled.transcript?.utterances = Array(repeating: t.utterances, count: 8).flatMap { $0 } }
                    let autoTranscript = MeetingViewState(); autoTranscript.tab = .transcript
                    try render("meeting-autotitle-transcript", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: autoTitled, state: autoTranscript) }
                }
                // T9 / uwaga 2: wbudowany szablon po edycji („Built-in · edited"), niezapisana zmiana w sekcji; nowy własny.
                var edited = Template.standard
                edited.sections?[1].instruction = "One heading per topic with the concrete details: numbers, names, dates, the options discussed; mark a favored option. A side issue gets its own heading."
                try model.notes.templates.upsert(edited)
                try model.notes.templates.upsert(Template(id: "snapshot-custom", name: "Board update",
                                                          sections: [TemplateSection(title: "Decisions", instruction: "What was decided and by whom.")]))
                let builtin = TemplateEditorState(); builtin.select(model.notes.templates.all().first)
                builtin.draft?.sections?[2].instruction += " Keep it to one line."
                try render("templates-builtin", size: CGSize(width: 900, height: 640), dark: dark, model: model) { TemplatesView(state: builtin) }
                let custom = TemplateEditorState(); custom.startNew()
                try render("templates-new", size: CGSize(width: 900, height: 560), dark: dark, model: model) { TemplatesView(state: custom) }
                // Odbiór 2026-10-16: pigułka istnieje tylko podczas nagrywania — zwinięta i rozwinięta (kontroler z wymuszonym
                // stanem; okno, cień i przesuwanie to odbiór na żywo), plus osobno wiersze poziomów torów.
                let live = RecordingController.snapshotPreview(elapsed: 754)
                // Zwinięta w rozmiarze okna (`fittingSize`, jak `PillHostingView.fit`) przy najszerszym liczniku: przy stałym
                // 360 pt migawka nie mogła pokazać „Sto / p” z drugiego odbioru.
                let widest = RecordingController.snapshotPreview(elapsed: 35999) // 09:59:59
                let collapsed = RecordingPanelView(model: model, recording: widest, pill: PillState())
                try render("pill-collapsed", size: NSHostingView(rootView: collapsed.environment(model)).fittingSize, dark: dark, model: model) { collapsed }
                let open = PillState(); open.expanded = true
                try render("pill-expanded", size: CGSize(width: 400, height: 270), dark: dark, model: model) { RecordingPanelView(model: model, recording: live, pill: open) }
                // 1.5b: wyciszony mikrofon (zwinięta: ikona przy liczniku w zarezerwowanym miejscu; rozwinięta: „Muted”, szary pasek)
                // i próba wyciszenia drugiego toru („Nothing is being recorded” w miejscu linii presetu).
                let widestMuted = RecordingController.snapshotPreview(elapsed: 35999, muted: ["mic_raw"])
                let collapsedMuted = RecordingPanelView(model: model, recording: widestMuted, pill: PillState())
                try render("pill-collapsed-muted", size: NSHostingView(rootView: collapsedMuted.environment(model)).fittingSize, dark: dark, model: model) { collapsedMuted }
                try render("pill-expanded-muted", size: CGSize(width: 400, height: 270), dark: dark, model: model) {
                    RecordingPanelView(model: model, recording: RecordingController.snapshotPreview(elapsed: 754, muted: ["mic_raw"]), pill: open)
                }
                try render("pill-expanded-warning", size: CGSize(width: 400, height: 270), dark: dark, model: model) {
                    RecordingPanelView(model: model, recording: RecordingController.snapshotPreview(elapsed: 754, muted: ["system"], muteWarning: true), pill: open)
                }
                try render("pill-levels", size: CGSize(width: 360, height: 130), dark: dark, model: model) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preset: Polish · PL").font(.caption).foregroundStyle(.secondary)
                        LevelRow(title: "System audio", db: -22)
                        LevelRow(title: "Microphone: MacBook Air Microphone", db: -41, emphasized: true)
                        LevelRow(title: "Microphone: silent", db: -160, emphasized: true)
                    }
                    .padding(12)
                }
                // T9: pigułka bez nagrywania — oferta (kalendarz, rozmowa) i pytanie o koniec; rozmiar okna = `fittingSize` treści.
                let now = Date()
                let event = CalendarEventInfo(title: "Weekly product sync", start: now, end: now.addingTimeInterval(1800))
                for (name, mode) in [("pill-offer-calendar", PillMode.offer(Offer(id: "e", title: event.title, source: .calendar, event: event, app: nil))),
                                     ("pill-offer-call", .offer(Offer(id: "c", title: "Call in Teams", source: .call, event: nil, app: "com.microsoft.teams2"))),
                                     ("pill-end-prompt", .endPrompt(.callReleased))] {
                    let state = PillState(); state.mode = mode
                    let view = PillContentView(model: model, pill: state)
                    try render(name, size: NSHostingView(rootView: view.environment(model)).fittingSize, dark: dark, model: model) { view }
                }
                // Settings (§11.5): lista wszystkich dostawców (OpenRouter skonfigurowany, Ollama w błędzie), arkusz konfiguracji osobno.
                if let pid = model.providers.providers.first?.id {
                    model.providerChecks[pid] = .verified(models: 312)
                    try render("settings-verified", size: CGSize(width: 900, height: 700), dark: dark, model: model) { SettingsView() }
                    let ollama = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
                    model.providers.providers.append(ollama)
                    model.providerChecks[ollama.id] = .failed("Can't connect. Is the server running and the address correct?")
                    try render("settings-failed", size: CGSize(width: 900, height: 700), dark: dark, model: model) { SettingsView() }
                    model.providers.providers.removeAll { $0.id == ollama.id }
                    // R8: klucz ElevenLabs tylko do transkrypcji (403 z /v1/models) = ostrzeżenie, nie błąd.
                    let eleven = Provider(name: "ElevenLabs", baseURL: URL(string: "https://api.elevenlabs.io/v1")!, kind: .elevenLabs)
                    model.providers.providers.append(eleven)
                    model.providerChecks[eleven.id] = .limited("Key works for transcription only")
                    try render("settings-limited", size: CGSize(width: 900, height: 700), dark: dark, model: model) { SettingsView() }
                    model.providers.providers.removeAll { $0.id == eleven.id }
                    model.providerChecks[pid] = nil
                }
                // Arkusz osobną migawką (b-add.png): ElevenLabs z wynikiem, błąd klucza, Custom z błędem adresu.
                let sheetOK = ProviderSheetState(); sheetOK.setUp(.elevenLabs); sheetOK.result = .verified(models: 4)
                try render("settings-sheet-verified", size: CGSize(width: 520, height: 330), dark: dark, model: model) { ProviderSetupSheet(state: sheetOK) }
                let sheetBad = ProviderSheetState(); sheetBad.setUp(.elevenLabs); sheetBad.result = .failed("Key rejected (401). Check the key and try again.")
                try render("settings-sheet-failed", size: CGSize(width: 520, height: 330), dark: dark, model: model) { ProviderSetupSheet(state: sheetBad) }
                let sheetLimited = ProviderSheetState(); sheetLimited.setUp(.elevenLabs); sheetLimited.result = .limited("Key works for transcription only")
                try render("settings-sheet-limited", size: CGSize(width: 520, height: 330), dark: dark, model: model) { ProviderSetupSheet(state: sheetLimited) }
                let sheetCustom = ProviderSheetState(); sheetCustom.setUp(.custom); sheetCustom.error = "Enter a full address, e.g. https://openrouter.ai/api/v1."
                try render("settings-sheet-custom", size: CGSize(width: 520, height: 400), dark: dark, model: model) { ProviderSetupSheet(state: sheetCustom) }
                try render("settings", size: CGSize(width: 900, height: 700), dark: dark, model: model) { SettingsView() }
                // F20 T7: karta modelu lokalnego ASR w czterech stanach. Statusy są wymyślone (nic nie czyta magazynu, nic nie pobiera).
                let cardFolder = "~/Library/Application Support/FluidAudio/Models/\(ModelCardState.folder)"
                let cardScenes: [(String, ModelStatus, ModelActivity)] = [
                    ("ready", .ready, .idle), ("downloading", .missing, .downloading(0.41)), ("missing", .missing, .idle),
                    ("invalid", .invalid(reason: "Encoder.mlmodelc/weights/weight.bin has 218103808 bytes, expected 445187200"), .idle)]
                for (name, status, activity) in cardScenes {
                    try render("model-card-\(name)", size: CGSize(width: 700, height: 250), dark: dark, model: model) {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeader("On-device speech model")
                            ModelCardContent(card: ModelCardState(status: status, activity: activity), location: cardFolder)
                        }
                        .padding(.horizontal, 30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentBackground()
                    }
                }
                // Błąd pobrania pod opisem i wiersze edytora presetu (ASR, „On this Mac"): brak modelu / pobieranie / gotowy.
                try render("model-card-download-error", size: CGSize(width: 700, height: 250), dark: dark, model: model) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader("On-device speech model")
                        ModelCardContent(card: ModelCardState(status: .missing, activity: .idle), location: cardFolder,
                                         error: "The download didn't finish: The Internet connection appears to be offline.")
                    }
                    .padding(.horizontal, 30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentBackground()
                }
                try render("preset-on-this-mac-rows", size: CGSize(width: 700, height: 190), dark: dark, model: model) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach([("missing", ModelStatus.missing, ModelActivity.idle), ("downloading", .missing, .downloading(0.41)),
                                 ("invalid", .invalid(reason: "x"), .idle), ("ready", .ready, .idle)], id: \.0) { _, status, activity in
                            OnThisMacRoleContent(card: ModelCardState(status: status, activity: activity)).padding(.top, 10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentBackground()
                }
                // Dostawca „On this Mac" włączony (Settings) i preset z lokalnym ASR (edytor) — karta i wiersz pokazują stan magazynu TEGO
                // komputera (tylko odczyt), więc ta para nie jest deterministyczna; wymyślone stany są w migawkach powyżej.
                let onDevice = Provider(name: ProviderPreset.onThisMac.name, baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
                model.providers.providers.append(onDevice)
                model.providerChecks[onDevice.id] = RunGate.check(status: model.localASR.status).map { .failed($0.message) } ?? .verified(models: 1)
                try render("settings-on-this-mac", size: CGSize(width: 900, height: 1000), dark: dark, model: model) { SettingsView() }
                let localEditor = PresetEditorState(draft: Preset(name: "Polish, on this Mac", language: .polish,
                                                                  asr: RoleAssignment(providerID: onDevice.id, model: LocalASRModels.parakeetV3)), original: nil)
                try render("preset-form-on-this-mac", size: CGSize(width: 700, height: 420), dark: dark, model: model) { PresetForm(state: localEditor).contentBackground() }
                model.providers.providers.removeAll { $0.id == onDevice.id }
                model.providerChecks[onDevice.id] = nil
                // F20 T11: lokalne serwery tekstowe. Komunikaty błędów pochodzą z `LocalServerHint` (nie z palca), stany są wymyślone.
                let ollamaLocal = Provider(name: ProviderPreset.ollama.name, baseURL: URL(string: ProviderPreset.ollama.baseURL)!, contextTokens: 8_192)
                let llamaLocal = Provider(name: ProviderPreset.llamaCpp.name, baseURL: URL(string: ProviderPreset.llamaCpp.baseURL)!)
                let omlxLocal = Provider(name: ProviderPreset.omlx.name, baseURL: URL(string: ProviderPreset.omlx.baseURL)!)
                let parakeetLocal = Provider(name: ProviderPreset.onThisMac.name, baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
                let localServers = [ollamaLocal, llamaLocal, omlxLocal]
                model.providers.providers.append(contentsOf: localServers + [parakeetLocal])
                model.providerChecks[ollamaLocal.id] = .verified(models: 3)
                model.detectedContexts[ollamaLocal.id] = ContextProbe.describe(["bonsai-2": 4_096])
                model.providerChecks[llamaLocal.id] = .failed(LocalServerHint.message(for: llamaLocal, error: URLError(.cannotConnectToHost))!)
                model.providerChecks[omlxLocal.id] = .failed(LocalServerHint.message(for: omlxLocal, error: ProviderError.http(401, "API key required"))!)
                model.providerChecks[parakeetLocal.id] = .verified(models: 1)
                try render("settings-local-servers", size: CGSize(width: 900, height: 1000), dark: dark, model: model) { SettingsView() }
                let sheetOmlx = ProviderSheetState(); sheetOmlx.setUp(.omlx)
                try render("settings-sheet-omlx", size: CGSize(width: 520, height: 330), dark: dark, model: model) { ProviderSetupSheet(state: sheetOmlx) }
                let sheetOmlxDown = ProviderSheetState(); sheetOmlxDown.setUp(.omlx)
                sheetOmlxDown.result = .failed(LocalServerHint.message(for: omlxLocal, error: URLError(.cannotConnectToHost))!)
                try render("settings-sheet-omlx-down", size: CGSize(width: 520, height: 390), dark: dark, model: model) { ProviderSetupSheet(state: sheetOmlxDown) }
                // Preset w pełni lokalny (znaczniki „On this Mac" przy rolach, ostrzeżenie przy korekcie, plakietka „Fully local") i mieszany (chmura = bez plakietki).
                let fullyLocal = Preset(name: "Polish, fully local", language: .polish,
                                        asr: RoleAssignment(providerID: parakeetLocal.id, model: LocalASRModels.parakeetV3),
                                        correction: RoleAssignment(providerID: ollamaLocal.id, model: "qwen3:8b"),
                                        summary: RoleAssignment(providerID: ollamaLocal.id, model: "qwen3:8b"))
                var mixed = fullyLocal
                mixed.id = UUID(); mixed.name = "Polish, local notes only"
                if let cloud = model.providers.providers.first(where: { $0.id != parakeetLocal.id && !$0.isLocal }) {
                    mixed.asr = RoleAssignment(providerID: cloud.id, model: "microsoft/mai-transcribe-2")
                }
                let presetsBefore = model.presets
                model.presets.presets.append(contentsOf: [fullyLocal, mixed])
                let localEditing = PresetEditorState(); localEditing.select(fullyLocal)
                try render("presets-fully-local", size: CGSize(width: 900, height: 900), dark: dark, model: model) { PresetsView(state: localEditing) }
                let mixedEditing = PresetEditorState(); mixedEditing.select(mixed)
                try render("presets-local-notes-only", size: CGSize(width: 900, height: 900), dark: dark, model: model) { PresetsView(state: mixedEditing) }
                model.presets = presetsBefore
                model.providers.providers.removeAll { p in (localServers + [parakeetLocal]).contains { $0.id == p.id } }
                for p in localServers + [parakeetLocal] { model.providerChecks[p.id] = nil }
                // Faza 1.6 T7: Integrations + Meeting detection (kalendarz połączony, trzy kalendarze, jeden odznaczony; Advanced rozwinięte).
                let meetingState = MeetingSettingsState()
                meetingState.authorization = .granted
                meetingState.calendars = [CalendarInfo(id: "a", title: "Work"), CalendarInfo(id: "b", title: "Personal"), CalendarInfo(id: "c", title: "Holidays")]
                meetingState.advancedOpen = true
                meetingState.ignoredText = "com.example.dictation"
                model.settings.meetings = MeetingSettings(autoStart: true, appleCalendarEnabled: true, calendarIDs: ["a", "b"], startSeconds: 15)
                meetingState.load(model.settings.meetings)
                try render("settings-meetings", size: CGSize(width: 900, height: 900), dark: dark, model: model) {
                    ScrollPage(640) { VStack(alignment: .leading, spacing: 0) { MeetingSettingsSections(state: meetingState) } }.contentBackground()
                }
                let meetingDenied = MeetingSettingsState(); meetingDenied.authorization = .denied
                model.settings.meetings = nil
                try render("settings-meetings-denied", size: CGSize(width: 900, height: 560), dark: dark, model: model) {
                    ScrollPage(640) { VStack(alignment: .leading, spacing: 0) { MeetingSettingsSections(state: meetingDenied) } }.contentBackground()
                }
                // Auto + rola korekty: ostrzeżenie o języku i pole „Extra instructions" (nowy, niezapisany preset = „Unsaved").
                // Uwaga (T3): całe okno (`ContentView` z `NavigationSplitView`) renderuje się poza ekranem jako pusta plansza —
                // nie używamy go w migawkach.
                if let pid = model.providers.providers.first?.id {
                    let a = RoleAssignment(providerID: pid, model: "deepseek/deepseek-v4.1-flash", prompt: "Keep product names unchanged.")
                    let auto = PresetEditorState(draft: Preset(name: "Mixed meetings", language: nil, asr: RoleAssignment(providerID: pid, model: "microsoft/mai-transcribe-2"),
                                                                correction: a, languageAuto: true), original: nil)
                    try render("presets-auto", size: CGSize(width: 900, height: 780), dark: dark, model: model) { PresetsView(state: auto) }
                }
            }
            print("snapshots: \(directory!.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshots: \(error)\n".utf8))
            exit(1)
        }
    }
}

/// Wszystkie komponenty wspólne w jednym widoku (migawka „components").
struct ComponentGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle("Settings")
            SectionHeader("Correction", note: "— optional") { Toggle("", isOn: .constant(true)).toggleStyle(.switch).labelsHidden() }
            Card {
                FormRow(label: "Language", caption: "✓ Language enforced") { Text("Polish") }
                RowDivider()
                FormRow(label: "Address", caption: "Enter a full address.", isError: true) { Text("openrouter.ai") }
            }
            HStack(spacing: 8) {
                Button("Record") {}.buttonStyle(.pillPrimary)
                Button("Cancel") {}.buttonStyle(.pill)
                Button("Retry") {}.buttonStyle(.pillSmall)
                Button("Save") {}.buttonStyle(.pillPrimary).disabled(true)
                Button("Ollama") {}.buttonStyle(.pillSmall).disabled(true)
            }
            .padding(.vertical, 16)
            HStack(spacing: 14) {
                StateLabel(.ok, "Notes ready")
                StateLabel(.bad, "Correction failed")
                StateLabel(.live, "Recording 12:04")
            }
            HStack(spacing: 14) {
                StateLabel(.neutral, "Transcript ready")
                StateLabel(.progress(0.41), "Transcribing 41%")
                StateLabel(.progress(nil), "Correcting…")
            }
            .padding(.vertical, 10)
            MetaLine(["Oct 15, 11:29", "42 min", "Preset Polish"])
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentBackground()
    }
}
