import AppKit
import YascribeNotes
import YascribeProviders
import YascribeTranscription
import SwiftUI

enum MeetingTab: String, CaseIterable, Identifiable {
    case summary = "Summary", myNotes = "My notes", transcript = "Transcript"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: String(localized: "Summary")
        case .myNotes: String(localized: "My notes")
        case .transcript: String(localized: "Transcript")
        }
    }
}

final class MeetingViewState: ObservableObject {
    @Published var tab: MeetingTab?
    /// Edycja pola tytułu; `nil` = pole pokazuje bieżący tytuł sesji (odświeża się po zapisie autotytułu).
    @Published var titleEdit: String?
    /// Otwarty popover problemu toru (id toru) w nagłówku spotkania.
    @Published var problemPopover: String?
    @Published var myNotes = ""
    @Published var loadedMyNotes = false
    @Published var useCorrected = true
    @Published var templateID = Template.standard.id
    @Published var context = ""
    @Published var contextPrefilled = false
    @Published var showContext = false
    /// Okno „Models…" (zakładka wybiera treść); otwarte na `MeetingDetailView`, poza przewijaną stroną.
    @Published var modelsSheet = false
    /// Błąd korekty/notatki: „Retry" otwiera okno Improve (dostawca i model do zmiany), nie powtarza tego samego niedziałającego modelu.
    func openModelsSheet(on tab: MeetingTab) { self.tab = tab; modelsSheet = true }
    /// Source notatki wybrany w oknie Summary; `nil` = jak „Version" w Transcript. Żyje do zamknięcia widoku spotkania.
    @Published var summaryUseCorrected: Bool?
    var summaryCorrected: Bool { summaryUseCorrected ?? useCorrected }
    /// Jedyny otwarty edytor segmentu (TASK-109): przebieg i indeks z chwili otwarcia — szkic nie trafi do innego przebiegu.
    @Published var segmentDraft: SegmentDraft?
    /// TASK-119: zaznaczone wiersze (indeksy w `utterances`) tego przebiegu i wersji; kotwica ⇧-kliku.
    @Published var selection = Set<Int>()
    @Published var selectionAnchor: Int?
    @Published var selectionScope: SelectionScope?
    @Published var showHidden = false
    /// Ostatnio ukryte wypowiedzi — pasek „Undo”.
    @Published var lastHidden: HiddenUndo?

    /// `rows`: źródło każdego wiersza (TASK-127) — złączenie albo rozdzielenie mówców przesuwa podział, więc i numery wierszy.
    struct SelectionScope: Equatable { var runID: String; var corrected: Bool; var rows: [Int] = [] }
    struct HiddenUndo: Equatable { var runID: String; var keys: [TranscriptEdits.Hidden] }

    /// Zaznaczenie z innego przebiegu, wersji albo układu wierszy (inne indeksy) nie obowiązuje.
    func selected(runID: String?, corrected: Bool, rows: [Int] = []) -> Set<Int> {
        selectionScope == runID.map { SelectionScope(runID: $0, corrected: corrected, rows: rows) } ? selection : []
    }

    /// ⌘-klik przełącza wiersz, ⇧-klik zaznacza zakres od kotwicy po widocznych wierszach (`visible` w kolejności listy).
    func click(_ index: Int, command: Bool, shift: Bool, runID: String, corrected: Bool, visible: [Int], rows: [Int] = []) {
        let scope = SelectionScope(runID: runID, corrected: corrected, rows: rows)
        if selectionScope != scope { selection = []; selectionAnchor = nil; selectionScope = scope }
        if shift, let anchor = selectionAnchor, let a = visible.firstIndex(of: anchor), let b = visible.firstIndex(of: index) {
            selection.formUnion(visible[min(a, b)...max(a, b)])
        } else if command || shift {
            if selection.remove(index) == nil { selection.insert(index) }
            selectionAnchor = index
        }
    }

    func clearSelection() { selection = []; selectionAnchor = nil; selectionScope = nil }
}

/// `corrected` i `initial` z chwili otwarcia: przełączenie wersji w trakcie edycji nie zmienia celu zapisu.
struct SegmentDraft: Equatable {
    var runID: String
    var index: Int
    var speaker: Speaker
    var start: Double
    var corrected: Bool
    var initial: String
    var text: String
}

// MARK: Zakładki tekstowe (macos.md §11.5)

/// Zakładki jako tekst 13 Medium (`text2`, wybrana `text`), 2 pt podkreślenie pod wybraną i linia 0,5 pt pod całością.
struct MeetingTabBar: View {
    @Binding var selection: MeetingTab

    var body: some View {
        HStack(spacing: 22) {
            ForEach(MeetingTab.allCases) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Color.mnText : Color.mnText2)
                        .frame(height: 28)
                        .padding(.bottom, 9)
                        .overlay(alignment: .bottom) {
                            if selected { RoundedRectangle(cornerRadius: 1).fill(.mnText).frame(height: 2).offset(y: 0.5) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) { Rectangle().fill(.mnLine).frame(height: 0.5) }
    }
}

/// Błąd: ikona + słowo w `rec` (łamie się na kilka linii, w przeciwieństwie do `StateLabel`) i Retry (otwiera okno wyboru modelu).
struct ErrorLine: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                Text(message).fixedSize(horizontal: false, vertical: true).help(message)
            }
            .font(.callout).foregroundStyle(.mnRec)
            .accessibilityElement(children: .combine)
            if let retry { Button("Retry", action: retry).buttonStyle(.pillSmall).help("Choose the model and try again") }
        }
    }
}

/// Kontekst dla modelu, rozwinięty w miejscu we wnęce paska: pole `field` + obwódka 1 pt + promień 7,
/// rośnie z treścią (uwaga 7 — bez własnego przewijania).
private struct ContextEditor: View {
    @Binding var text: String
    var body: some View {
        GrowingTextView(text: $text, minHeight: 36, accessibilityLabel: String(localized: "Context for the model"))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Who's there, what it's about — for the model").font(.system(size: 13)).foregroundStyle(.mnText2).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 1))
    }
}

// MARK: My notes

/// Edytor rosnący z treścią (uwaga 7): bez własnego przewijania, autozapis przy każdej zmianie.
struct MyNotesTab: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingViewState
    let item: SessionItem

    var body: some View {
        if model.recordingsMove != nil {
            // R3: tylko do odczytu. `GrowingTextView` to NSTextView — `.disabled` nie blokuje w nim pisania.
            Text(state.myNotes.isEmpty ? String(localized: "No notes.") : state.myNotes)
                .font(.system(size: 14)).lineSpacing(8)
                .foregroundStyle(state.myNotes.isEmpty ? Color.mnText2 : Color.mnText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        } else {
            GrowingTextView(text: Binding(get: { state.myNotes }, set: { state.myNotes = $0; model.notes.saveMyNotes($0, for: item) }),
                            fontSize: 14, lineSpacing: 8, minHeight: 240, accessibilityLabel: String(localized: "My notes"))
                .overlay(alignment: .topLeading) {
                    if state.myNotes.isEmpty {
                        Text("Write notes…").font(.system(size: 14)).foregroundStyle(.mnText2).allowsHitTesting(false)
                    }
                }
        }
    }
}

// MARK: Transcript

struct TranscriptActions: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingViewState
    let item: SessionItem
    let compact: Bool

    var body: some View {
        if item.transcript != nil {
            HStack(spacing: 8) {
                if item.corrected != nil {
                    Button("Improve") { state.modelsSheet = true }
                        .buttonStyle(.pill).help("Improve or redo the transcript with another model")
                } else if model.notes.correctionFailureMessage(item.id) == nil, model.notes.canRetryCorrection(item) {
                    Button(compact ? "Improve" : "Improve transcript") { model.notes.retryCorrection(item) }
                        .buttonStyle(.pillPrimary)
                        .accessibilityLabel("Improve transcript")
                        .disabled(model.recordingsMove != nil || model.isTranscribing(item))
                        .help("Run the correction model on this transcript")
                } else if model.notes.correctionFailureMessage(item.id) == nil {
                    // Preset bez modelu korekty: okno Improve pozwala wybrać model albo transkrybować od nowa.
                    Button("Improve") { state.modelsSheet = true }
                        .buttonStyle(.pill).help("Improve or redo the transcript with another model")
                }
                Button { copy() } label: {
                    if compact { Image(systemName: "doc.on.doc") } else { Label("Copy", systemImage: "doc.on.doc") }
                }
                    .accessibilityLabel("Copy")
                    .buttonStyle(.pill).help("Copy the transcript")
            }
        }
    }

    /// Kopia kanoniczna (angielskie „Me”/„Them” i linie wyciszenia), niezależna od języka interfejsu; kolumna pokazuje nazwy przetłumaczone.
    /// Ten sam zapis co eksport MCP (`MeetingArchive`).
    static func copyLine(_ u: Utterance) -> String { MeetingArchive.copyLine(u) }

    private func copy() {
        guard let t = model.transcript(of: item, corrected: state.useCorrected) else { return }
        let text = MeetingArchive.copyLines(t, summary: item.summary).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct TranscriptTab: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingViewState
    let item: SessionItem
    /// Wiersz z ikoną ⏸ (gra) i wiersz podświetlony (gra albo ostatni po pauzie) — indeksy w `utterances` (TASK-131).
    var playing: Int? = nil
    var current: Int? = nil
    let onJump: (Int, TranscriptPlaylist) -> Void
    private var busy: Bool { model.isTranscribing(item) }
    /// Diaryzacja po transkrypcji trzyma `busy` (F01), ale wiersz mówi, co naprawdę trwa.
    private var detecting: Bool { model.isDetectingSpeakers(item) }
    private var moving: Bool { model.recordingsMove != nil }
    /// Wznowienie w trakcie korekty dałoby drugą korektę tego samego przebiegu (F2).
    private var correcting: Bool { model.notes.isCorrecting(item.id) }
    private var suggestionCount: Int { model.aliasSuggestions.filter { $0.sessions.contains(item.id) }.count }

    var body: some View {
        PinnedBarPage {
            // Poprawka 6: ta sama linia co w nagłówku spotkania (problem toru nagrania).
            ForEach(item.trackProblems, id: \.trackID) { p in
                if p.isWarning { WarnLabel(p.line) } else { StateLabel(.neutral, p.line) }
            }
            if model.notes.isCorrecting(item.id) {
                StateLabel(.progress(nil), correctionProgress)
                    .help(modelName ?? "")
            }
            if let why = model.notes.correctionFailureMessage(item.id) {
                ErrorLine(message: String(localized: "Correction failed: \(why)"), retry: model.notes.canCorrectNow(item) ? { state.openModelsSheet(on: .transcript) } : nil)
                    .disabled(moving)
            }
            // TASK-112: korekta tego spotkania podsunęła Aliasy do słownika (lista i Add w zakładce Dictionary).
            if item.corrected != nil, !correcting, suggestionCount > 0 {
                HStack(spacing: 8) {
                    StateLabel(.neutral, String.localizedStringWithFormat(NSLocalizedString("%lld dictionary suggestions from this meeting", comment: ""), Int64(suggestionCount)))
                    LinkButton(String(localized: "Review")) { model.section = .dictionary }
                }
            }
            // „Transcribe again…": stary transkrypt zostaje widoczny, dopóki nowy przebieg się nie zakwalifikuje (R23). Linia ogólna
            // tylko do pierwszego przeładowania, zanim próba ma `input.json` (wtedy wchodzi baner z modelem).
            if detecting {
                StateLabel(.progress(nil), String(localized: "Detecting speakers…"))
            } else if busy, item.transcript != nil, item.attemptNotPromoted == nil {
                StateLabel(.progress(nil), String(localized: "Transcribing again…"))
            }
            attemptBanner
            hiddenBar
            if item.transcript != nil, item.corrected != nil {
                FieldMenu(label: String(localized: "Version"), value: state.useCorrected ? String(localized: "Corrected") : String(localized: "Original"), width: 120) {
                    Picker("Version", selection: $state.useCorrected) {
                        Text("Corrected").tag(true)
                        Text("Original").tag(false)
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                .padding(.bottom, 4)
            }
        } content: {
            content
        }
    }

    private var correctionProgress: String {
        let displayModel = modelName.map { model.modelDisplayName($0) }
        return switch (item.corrected == nil, displayModel) {
        case (true, let name?): String(localized: "After the meeting, we improve the transcript with \(name)…")
        case (true, nil): String(localized: "After the meeting, we improve the transcript…")
        case (false, let name?): String(localized: "Improving the transcript with \(name)…")
        case (false, nil): String(localized: "Improving the transcript…")
        }
    }

    /// Baner R23: najnowsza próba nie jest bieżącym przebiegiem (trwa, padła, z lukami albo pusta).
    @ViewBuilder private var attemptBanner: some View {
        if let a = item.attemptNotPromoted {
            let from = item.runSnapshot.map { String(localized: "the transcript from \(runLabel($0))") }
                ?? String(localized: "the previous transcript")
            let run = a.snapshot.map(runLabel)
            // W toku także przy wznowieniu próby z lukami (na dysku wciąż `.gaps`); tuż po starcie nowej próby baner może do
            // pierwszego przeładowania nazywać model poprzedniej.
            if busy {
                StateLabel(.progress(nil), run.map { String(localized: "Transcription with \($0) is in progress — showing \(from).") }
                           ?? String(localized: "The new transcription is in progress — showing \(from).")).wrapping()
            } else {
                // Jedna linia: krótkie „Resume" obok komunikatu (pełna etykieta z modelem ucinała się przy 900 pt).
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    WarnLabel(run.map { String(localized: "Transcription with \($0) didn't finish — showing \(from).") }
                              ?? String(localized: "The new transcription didn't finish — showing \(from).")).help(Self.why(a.reason))
                    if a.snapshot != nil {
                        Button("Resume") { model.resume(item, runID: item.latestAttemptID) }
                            .buttonStyle(.pillSmall).fixedSize().disabled(moving || correcting)
                            .help("\(resumeLabel) — \(a.snapshot?.model ?? ""). Finished parts aren't paid for again.")
                    }
                }
            }
        }
    }

    /// „parakeet-tdt (EN)" — czytelna nazwa modelu i język przebiegu.
    private func runLabel(_ s: RunSnapshot) -> String {
        "\(model.modelDisplayName(s.model)) (\(s.preset.isAutoLanguage ? String(localized: "Auto") : s.language?.rawValue.uppercased() ?? "?"))"
    }

    private static func why(_ r: RunSelection.Reason) -> String {
        switch r {
        case .unfinished: String(localized: "It stopped before the end (failed, cancelled or the app was closed).")
        case .gaps(let n): String(format: NSLocalizedString("%lld parts couldn't be transcribed.", comment: ""), locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"), Int64(n))
        case .empty: String(localized: "No speech was recognized.")
        }
    }

    /// Wznowienie zawsze idzie do najnowszej próby; etykieta mówi, którą, gdy to nie bieżący przebieg.
    private var resumeLabel: String {
        item.attemptNotPromoted?.snapshot.map { String(localized: "Resume Transcription with \(runLabel($0))") }
            ?? String(localized: "Resume Transcription")
    }

    // Nadpisanie per spotkanie (chip modelu) wygrywa z presetem, tak jak przy samej korekcie.
    private var modelName: String? { model.notes.correctionAssignment(for: item)?.model }
    /// Pełny transkrypt (z ukrytymi, TASK-119): indeksy ▶/✎ to pozycje w `utterances`; ukryte wiersze pokazuje tylko „Show deleted”.
    private var shown: Transcript? { model.transcript(of: item, corrected: state.useCorrected, includeHidden: true) }
    private var selected: Set<Int> {
        state.selected(runID: item.runID, corrected: state.useCorrected, rows: shown.map(Self.rows) ?? [])
    }
    /// Układ wierszy dla zakresu zaznaczenia: źródło każdego wiersza.
    static func rows(_ t: Transcript) -> [Int] { t.utterances.indices.map { t.utterances[$0].sourceIndex ?? $0 } }
    private var canHide: Bool { item.runID != nil && !moving }
    /// Przebieg w Auto: jedyna flaga to „obcy alfabet" (T1), więc etykieta mówi to wprost. Z migawki przebiegu (I2).
    private var isAuto: Bool { model.runLanguage(item).isAuto }

    @ViewBuilder private var content: some View {
        if let t = shown {
            let numbers = UtteranceRow.speakerNumbers(t)
            let edited = item.editedIndices(corrected: state.useCorrected)
            let playlist = TranscriptPlaylist(t)
            // Uwaga 7: lista rośnie z treścią (przewija strona), separator `line2` między wierszami.
            LazyVStack(alignment: .leading, spacing: 0) {
                if !t.failedChunks.isEmpty {
                    Button(busy && !detecting ? "Transcribing…" : "Retry Failed Parts") { model.resume(item, runID: item.runID) }
                        .buttonStyle(.pillSmall)
                        .disabled(busy || moving || correcting)
                        .help("Sends only the parts that failed; finished parts aren't paid for again")
                        .padding(.bottom, 8)
                }
                Rectangle().fill(.mnLine2).frame(height: 0.5)
                let lines = Self.lines(t, item: item, showHidden: state.showHidden)
                let visible = lines.compactMap { if case .utterance(let i, _) = $0 { i } else { nil } }
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    if i > 0 { Rectangle().fill(.mnLine2).frame(height: 0.5) }
                    switch line {
                    case .utterance(let index, let u): row(index, u, number: numbers[u.speakerKey ?? ""],
                                                           edited: edited.contains(u.sourceIndex ?? index), in: t, visible: visible, playlist: playlist)
                    case .mute(let m): MuteRow(note: m)
                    }
                }
                if !t.failedChunks.isEmpty {
                    Text("Gaps").font(.system(size: 13, weight: .semibold)).foregroundStyle(.mnText)
                        .padding(.top, 22).padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(t.failedChunks.enumerated()), id: \.offset) { _, f in
                        Label("Couldn't transcribe \(MeetingDetailView.time(f.start))–\(MeetingDetailView.time(f.end))", systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.mnWarn)
                            .padding(.vertical, 4)
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("No transcript yet", systemImage: "text.alignleft")
            } actions: {
                if busy {
                    StateLabel(.progress(nil), String(localized: "Transcribing…"))
                } else {
                    // Preset zamrożony przy nagraniu, nie bieżący (spec §1.5); Resume bierze migawkę z input.json przebiegu.
                    Group {
                        if let p = model.presetFor(sessionURL: item.url) {
                            Button("Transcribe with \(p.name)") { model.transcribe(sessionURL: item.url, preset: p) }.buttonStyle(.pillPrimary)
                        }
                        if item.latestAttemptID != nil {
                            Button(resumeLabel) { model.resume(item, runID: item.latestAttemptID) }.buttonStyle(.pill).disabled(correcting)
                        }
                        // D13 (F6): po próbie bez transkryptu inny model i język też do wyboru (okno Improve).
                        Button("Improve") { state.modelsSheet = true }
                            .buttonStyle(.pill).help("Improve or redo the transcript with another model")
                    }
                    .disabled(moving)
                }
            }
        }
    }

    private func row(_ index: Int, _ u: Utterance, number: Int?, edited: Bool, in t: Transcript, visible: [Int], playlist: TranscriptPlaylist) -> UtteranceRow {
        // Jeden szkic naraz: otwarty edytor wyłącza pozostałe ołówki (niezapisany szkic nie znika).
        var startEdit: (() -> Void)?
        let corrected = state.useCorrected
        // Szkic z poprzedniego przebiegu (nowy przebieg został bieżącym) nie blokuje ołówków — nowy go zastępuje.
        let active = state.segmentDraft.map { $0.runID == item.runID } ?? false
        let source = u.sourceIndex ?? index
        if let runID = item.runID, !moving, !active, let target = Self.editTarget(index, u), item.canEdit(corrected: corrected) {
            startEdit = {
                state.segmentDraft = SegmentDraft(runID: runID, index: target.index, speaker: u.speaker, start: target.start,
                                                  corrected: corrected, initial: target.text, text: target.text)
            }
        }
        let onSave: (() -> Void)? = moving ? nil : { save() }
        let hidden = u.hidden == true
        // Usunięcie wiersza z zaznaczenia usuwa całe zaznaczenie; inaczej tylko ten wiersz.
        let targets = selected.contains(index) ? selected.sorted() : [index]
        var row = UtteranceRow(utterance: u, isAuto: isAuto, item: item, speakerNumber: number, isPlaying: playing == index, isCurrent: current == index,
                               isEdited: edited, draft: u.isFirstPart ? draft(source) : nil, onStartEdit: hidden ? nil : startEdit, onSave: onSave,
                               onCancel: { state.segmentDraft = nil }, onJump: { onJump(index, playlist) })
        row.isSelected = selected.contains(index)
        if canHide, let runID = item.runID {
            if hidden {
                row.onRestore = { setHidden([index], in: t, false) }
            } else {
                row.deleteCount = Self.sourceCount(targets, in: t)
                row.onDelete = { setHidden(targets, in: t, true) }
                row.onSelect = { command, shift in
                    state.click(index, command: command, shift: shift, runID: runID, corrected: state.useCorrected, visible: visible,
                                rows: Self.rows(t))
                }
            }
        }
        return row
    }

    // Części podzielonej wypowiedzi (TASK-127) to jedno źródło: edycja całości w pierwszej części, ukrycie i liczniki po źródłach.
    // Wiersz ≠ źródło: każda wypowiedź za podzieloną ma przesunięty wiersz, więc zawsze `sourceIndex` (pozycja przed podziałem).
    // `t` musi mieć wszystkie wypowiedzi (`includeHidden: true`), inaczej `sourceIndex` nie jest indeksem `edits.json`.

    /// Indeks, początek i tekst całej wypowiedzi źródłowej; ołówek dalszej części otwiera ten sam edytor, co pierwszej (stoi w niej).
    static func editTarget(_ index: Int, _ u: Utterance) -> (index: Int, start: Double, text: String)? {
        (u.sourceIndex ?? index, u.part?.start ?? u.start, u.part?.text ?? u.text)
    }

    /// Klucze ukrycia bez powtórek (obie części dają klucz źródła).
    static func hiddenKeys(_ indices: [Int], in t: Transcript) -> [TranscriptEdits.Hidden] {
        indices.filter(t.utterances.indices.contains).map { TranscriptEdits.Hidden(t.utterances[$0]) }
            .reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Liczba wypowiedzi źródłowych pod wierszami `indices` („N selected”, „Delete N”).
    static func sourceCount(_ indices: some Collection<Int>, in t: Transcript) -> Int {
        Set(indices.filter(t.utterances.indices.contains).map { t.utterances[$0].sourceIndex ?? $0 }).count
    }

    /// Ukryte wypowiedzi źródłowe („Show deleted (N)”).
    static func hiddenSourceCount(_ t: Transcript) -> Int { t.utterances.filter { $0.hidden == true && $0.isFirstPart }.count }

    /// Ukrycie (TASK-119) po mówcy i początku z pełnego transkryptu tej wersji; po sukcesie pasek „Undo”.
    private func setHidden(_ indices: [Int], in t: Transcript, _ on: Bool) {
        guard let runID = item.runID else { return }
        let keys = Self.hiddenKeys(indices, in: t)
        guard model.setHidden(item, runID: runID, keys: keys, hidden: on) else { return }
        if on {
            state.lastHidden = .init(runID: runID, keys: keys)
            state.clearSelection()
        } else {
            state.lastHidden = nil
        }
    }

    /// Pasek zaznaczenia, „Undo” po usunięciu i przełącznik „Show deleted”.
    @ViewBuilder private var hiddenBar: some View {
        if let t = shown {
            let count = Self.hiddenSourceCount(t)
            if !selected.isEmpty, canHide {
                HStack(spacing: 8) {
                    Text(String.localizedStringWithFormat(NSLocalizedString("%lld selected", comment: ""), Int64(Self.sourceCount(selected, in: t))))
                        .font(.callout).foregroundStyle(.mnText2)
                    Button(String(localized: "Delete")) { setHidden(selected.sorted(), in: t, true) }.buttonStyle(.pillSmall)
                    Button(String(localized: "Cancel")) { state.clearSelection() }.buttonStyle(.pillSmall)
                }
            }
            if let undo = state.lastHidden, undo.runID == item.runID, canHide {
                HStack(spacing: 8) {
                    StateLabel(.neutral, String.localizedStringWithFormat(NSLocalizedString("Deleted %lld segments", comment: ""), Int64(undo.keys.count)))
                    LinkButton(String(localized: "Undo")) {
                        if let runID = item.runID, model.setHidden(item, runID: runID, keys: undo.keys, hidden: false) { state.lastHidden = nil }
                    }
                }
            }
            if count > 0 {
                Toggle(String.localizedStringWithFormat(NSLocalizedString("Show deleted (%lld)", comment: ""), Int64(count)), isOn: $state.showHidden)
                    .toggleStyle(.checkbox).font(.callout)
                    .help("Deleted segments stay out of notes, search, copy and the agent tools")
            }
        }
    }

    /// Szkic tylko w wierszu, dla którego go otwarto, i tylko w tym samym przebiegu.
    private func draft(_ index: Int) -> Binding<String>? {
        // Po przełączeniu na wersję z innymi indeksami edytor nie staje pod obcą wypowiedzią.
        guard let d = state.segmentDraft, d.index == index, d.runID == item.runID,
              d.corrected == state.useCorrected || item.canEdit(corrected: state.useCorrected) else { return nil }
        return Binding(get: { state.segmentDraft?.text ?? "" }, set: { state.segmentDraft?.text = $0 })
    }

    /// Edytor zamyka się tylko po udanym zapisie (inaczej szkic zostaje, błąd w `lastError`).
    private func save() {
        guard let d = state.segmentDraft else { return }
        let trimmed = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if trimmed(d.text) == trimmed(d.initial) || model.editUtterance(item, runID: d.runID, index: d.index, speaker: d.speaker, start: d.start,
                                                                     corrected: d.corrected, text: d.text) {
            state.segmentDraft = nil
        }
    }

    /// Indeks wypowiedzi to pozycja w `utterances` (klucz poprawek i odtwarzania), nie pozycja linii z wyciszeniami.
    enum Line { case utterance(Int, Utterance), mute(MuteNote) }

    /// Wypowiedzi z liniami wyciszenia („Microphone muted 0:05–0:12", macos.md §11.5) w kolejności czasu.
    /// Ukryte wypowiedzi (TASK-119) tylko z „Show deleted”.
    static func lines(_ t: Transcript, item: SessionItem, showHidden: Bool = false) -> [Line] {
        MeetingArchive.lines(t, summary: item.summary).compactMap { line in
            switch line {
            case .utterance(let i, let u): showHidden || u.hidden != true ? .utterance(i, u) : nil
            case .mute(let m): .mute(m)
            }
        }
    }
}

// MARK: Summary

struct SummaryActions: View {
    @ObservedObject var state: MeetingViewState
    let item: SessionItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.notesText ?? "", forType: .string) } label: {
                if compact { Image(systemName: "doc.on.doc") } else { Label("Copy", systemImage: "doc.on.doc") }
            }.buttonStyle(.pill).help("Copy the notes").accessibilityLabel("Copy")
            Button("Improve…") { state.modelsSheet = true }
                .buttonStyle(.pill).help("Change the template, context or model and regenerate")
        }
    }
}

struct SummaryTab: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingViewState
    let item: SessionItem

    private var gen: NotesModel.GenState { model.notes.state(item.id) }
    private var template: Template { model.notes.templates.all().first { $0.id == state.templateID } ?? .standard }
    private var choice: SummaryChoice? { model.notes.summaryChoice(for: item) }
    private var moving: Bool { model.recordingsMove != nil }
    /// Korekta tej sesji trwa na tym samym lokalnym serwerze: notatka czekałaby w kolejce i wpadła w limit czasu części.
    private var correcting: Bool { model.notes.isCorrecting(item.id) }

    /// „Using <model> from preset <nazwa>" przy zastępstwie; ostrzeżenie, gdy żaden preset nie ma modelu podsumowania.
    @ViewBuilder private var modelLine: some View {
        if let c = choice {
            if let label = c.label { Text(label).font(.subheadline).foregroundStyle(.mnText2) }
        } else {
            Label("No preset has a summary model. Choose one in Presets.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.mnWarn)
        }
    }
    /// Source z okna Summary (albo „Version" z Transcript), znormalizowany: bez korekty zawsze oryginał.
    private var corrected: Bool { state.summaryCorrected && item.corrected != nil }
    private var transcribing: Bool { model.isTranscribing(item) }
    private var hasText: Bool {
        guard let t = model.transcript(of: item, corrected: corrected) else { return false }
        return !NotePromptBuilder.transcriptLines(t).isEmpty
    }
    /// Powód, dla którego „Generate notes" jest nieaktywne: brak transkryptu to coś innego niż transkrypt bez treści.
    private var disabledReason: String {
        item.transcript == nil ? String(localized: "Transcript isn't ready yet.") : String(localized: "Nothing to summarize: the transcript has no usable text.")
    }

    /// Uwaga 7 (b-summary0.png, b-meeting.png): bez karty — ten sam pasek we wnęce przed i po generowaniu, pod nim
    /// linie stanu i notatka albo jedna linia stanu pustego. Przewija się treść pod kartami.
    var body: some View {
        // Linie stanu (postęp + Cancel, błąd) przypięte nad notatką, żeby nie znikały po przewinięciu (TASK-90).
        PinnedBarPage(spacing: 12) {
            if gen == .generating { generatingRow }
            // TASK-119: notatka mogła powstać z tekstem, który użytkownik potem ukrył (albo bez przywróconego).
            if item.notesPredateHiding, gen != .generating {
                HStack(spacing: 8) {
                    StateLabel(.neutral, String(localized: "Notes were generated before segments were deleted or restored."))
                    LinkButton(String(localized: "Regenerate…")) { state.modelsSheet = true }
                }
            }
            if correcting, gen != .generating, hasText {
                Text("Generate notes once the transcript has been improved.").font(.callout).foregroundStyle(.mnText2)
            }
            errorView
        } content: {
            if item.notes.summary == nil { bar(nil) }
            if item.attemptNotPromoted != nil || (model.transcript(of: item, corrected: corrected).map { t in
                !t.failedChunks.isEmpty || t.utterances.contains(where: { $0.excludedFromNotes })
            } ?? false) {
                HStack {
                    WarnLabel(String(localized: "The transcript may be incomplete or contain excluded content."))
                    Button("View transcript") { state.tab = .transcript }.buttonStyle(.link)
                }
            }
            if let numbers = item.notes.summary?.unverifiedNumbers, !numbers.isEmpty {
                WarnLabel(String(localized: "Not written as digits in the transcript: \(numbers.joined(separator: ", ")). Check these numbers in the notes."))
            }
            if choice?.isFallback == true || choice == nil { modelLine }
            if item.notes.summary == nil, !hasText { Text(disabledReason).font(.callout).foregroundStyle(.mnText2) }
            if let s = item.notes.summary {
                MarkdownView(blocks: item.speakerMarkers.linked(MarkdownBlocks.group(s.markdown)), speakerPicker: speakerPicker).padding(.top, 8)
            } else if gen != .generating, hasText {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { prefillContext() }
    }

    /// Postęp generowania (krok z `NoteGenerator`) i „Cancel": podział długiego transkryptu może trwać kilka minut.
    private var generatingRow: some View {
        HStack(spacing: 10) {
            StateLabel(.progress(nil), model.notes.progress[item.id]?.text ?? String(localized: "Generating notes…"))
            Button("Cancel") { model.notes.cancelGeneration(item.id) }
                .buttonStyle(.pillSmall)
                .help("Stop generating the notes")
        }
    }

    /// Kontekst wstępnie z My notes, dopóki użytkownik go nie ruszył.
    private func prefillContext() {
        guard !state.contextPrefilled else { return }
        state.contextPrefilled = true
        let mine = item.notes.myNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.context.isEmpty, !mine.isEmpty { state.context = mine }
        if let s = item.notes.summary { state.templateID = s.templateID; if state.context.isEmpty { state.context = s.context } }
    }

    /// Stan pusty: co zrobić i z jakiego transkryptu powstanie notatka.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No notes yet. Pick a template, add context if you like, and generate.")
                .font(.system(size: 13)).foregroundStyle(.mnText2)
            Text(sourceLine).font(.subheadline).foregroundStyle(.mnText2)
        }
        .padding(.top, 34).padding(.leading, 4)
    }

    private var sourceLine: String {
        let details = [
            item.duration.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) },
            model.runLanguage(item).language.map { languageDisplayName($0) },
        ].compactMap { $0 }.joined(separator: ", ")
        switch (corrected, details.isEmpty) {
        case (true, true): return String(localized: "Uses the corrected transcript.")
        case (false, true): return String(localized: "Uses the original transcript.")
        case (true, false): return String(localized: "Uses the corrected transcript (\(details)).")
        case (false, false): return String(localized: "Uses the original transcript (\(details)).")
        }
    }

    /// Jedna linia bez wnęki: przed notatką szablon · kontekst · opcje · „Generate notes"; po notatce tylko „Improve" + Copy.
    private func bar(_ s: NoteSummary?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let s {
                    // Po wygenerowaniu notatki wszystkie opcje (szablon, kontekst, model, Regenerate) są w oknie „Improve".
                    Spacer(minLength: 0)
                    Button("Improve") { state.modelsSheet = true }
                        .buttonStyle(.pill).layoutPriority(2).help("Change the template, context or model and regenerate")
                    Button { copy(item.notesText ?? s.markdown) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.pill)
                        .layoutPriority(2)
                        .help("Copy the notes")
                } else {
                    templateMenu
                    Button { state.showContext.toggle() } label: {
                        Text(state.context.isEmpty || state.showContext ? "Add context" : "Context: \(state.context.replacingOccurrences(of: "\n", with: " "))")
                            .font(.system(size: 13)).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(moving)
                    .help(state.showContext ? "Hide the context field" : "Add or change the context for the model")
                    .accessibilityValue(state.showContext ? "Expanded" : "Collapsed")
                    Button { state.modelsSheet = true } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.pill).layoutPriority(2).help("More options: choose the summary model")
                        .accessibilityLabel("More options")
                    Button("Generate notes") { run() }
                        .buttonStyle(.pillPrimary)
                        .layoutPriority(2)
                        .disabled(gen == .generating || !hasText || choice == nil || moving || correcting || transcribing)
                        // ⌘↩, nie sam Return: Return w polu kontekstu ma wstawić nową linię, a nie uruchomić płatne generowanie.
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            if s == nil, state.showContext {
                if moving {
                    // R3: tylko do odczytu (NSTextView nie reaguje na `.disabled`).
                    Text(state.context).font(.system(size: 13)).foregroundStyle(.mnText2).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                } else {
                    ContextEditor(text: $state.context).padding(.horizontal, 2).padding(.bottom, 2)
                }
            }
        }
    }

    /// Popup szablonu: pole 130 × 28, promień 7 (makieta: `.field`). Menu zostaje systemowe.
    private var templateMenu: some View {
        FieldMenu(label: String(localized: "Template"), value: template.displayName(), width: 130) {
            ForEach(model.notes.templates.all()) { t in
                Button(t.displayName()) { state.templateID = t.id }
            }
            Divider()
            Button("Manage templates…") { model.section = .templates }
        }
    }

    @ViewBuilder private var errorView: some View {
        if case .failed(let message) = gen { ErrorLine(message: message) { state.openModelsSheet(on: .summary) }.disabled(moving || correcting || transcribing) }
    }

    /// Ten sam „Who is this?” co w transkrypcie; zmiana imienia od razu przerysowuje notatkę (bloki zawierają nazwy).
    private func speakerPicker(_ number: Int, close: @escaping () -> Void) -> AnyView {
        let numbers = item.speakerMarkers.numbers
        guard let key = numbers.first(where: { $0.value == number })?.key else { return AnyView(EmptyView()) }
        let options = model.speakerMergeOptions(item, key: key, numbers: numbers)
        return AnyView(SpeakerPicker(attendees: item.notes.meta.calendarEvent?.attendees ?? [],
                                     known: KnownPeople.load(root: model.paths.root).names,
                                     currentName: item.speakers?.names?[key], number: number,
                                     recognized: model.voiceRecognition(item, key: key),
                                     others: options.others, merged: options.merged,
                                     merge: { model.mergeSpeaker(item: item, key: key, into: $0); close() },
                                     split: { model.splitSpeaker(item: item, original: $0); close() }) { name in
            model.renameSpeaker(item: item, key: key, name: name)
            close()
        })
    }

    private func run() {
        model.notes.generate(item: item, useCorrected: corrected, template: template, context: state.context)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Linia wyciszenia toru w transkrypcie: czas w kolumnie czasu, opis w `text2` (informacja, nie ostrzeżenie).
private struct MuteRow: View {
    let note: MuteNote

    private var text: String {
        let name = note.trackID == "system" ? String(localized: "System audio") : String(localized: "Microphone")
        if let end = note.endTime { return String(localized: "\(name) muted \(note.startTime)–\(end)") }
        return String(localized: "\(name) muted from \(note.startTime) to the end")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(MeetingDetailView.time(note.start)).monospacedDigit().frame(width: 72, alignment: .leading)
            Label(text, systemImage: note.trackID == "system" ? "speaker.slash" : "mic.slash")
        }
        .font(.system(size: 13)).foregroundStyle(.mnText2)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
