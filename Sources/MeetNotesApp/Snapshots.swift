import AppKit
import MeetNotesNotes
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
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
                if let withNotes = model.sessions.first(where: { $0.id.hasSuffix("aa11") }),
                   let transcriptOnly = model.sessions.first(where: { $0.id.hasSuffix("bb22") }),
                   let empty = model.sessions.first(where: { $0.id.hasSuffix("cc33") }) {
                    let summaryTab = MeetingViewState(); summaryTab.tab = .summary
                    try render("meeting-summary", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: withNotes, state: summaryTab) }
                    // Uwaga 7: „Add context” rozwinięte w miejscu (pole rośnie z treścią).
                    let contextOpen = MeetingViewState(); contextOpen.tab = .summary; contextOpen.showContext = true
                    try render("meeting-summary-context", size: CGSize(width: 900, height: 640), dark: dark, model: model) { MeetingDetailView(item: withNotes, state: contextOpen) }
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
                try render("pill-collapsed", size: CGSize(width: 360, height: 64), dark: dark, model: model) { RecordingPanelView(model: model, recording: live, pill: PillState()) }
                let open = PillState(); open.expanded = true
                try render("pill-expanded", size: CGSize(width: 360, height: 270), dark: dark, model: model) { RecordingPanelView(model: model, recording: live, pill: open) }
                try render("pill-levels", size: CGSize(width: 360, height: 130), dark: dark, model: model) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preset: Polish · PL").font(.caption).foregroundStyle(.secondary)
                        LevelRow(title: "System audio", db: -22)
                        LevelRow(title: "Microphone: MacBook Air Microphone", db: -41, emphasized: true)
                        LevelRow(title: "Microphone: silent", db: -160, emphasized: true)
                    }
                    .padding(12)
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
