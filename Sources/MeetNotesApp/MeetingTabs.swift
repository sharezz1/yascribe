import AppKit
import MeetNotesNotes
import MeetNotesProviders
import MeetNotesTranscription
import SwiftUI

enum MeetingTab: String, CaseIterable, Identifiable {
    case myNotes = "My notes", transcript = "Transcript", summary = "Summary"
    var id: String { rawValue }
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
    /// Popovery otwierane z `⋯` w Transcript (kotwiczą się do `⋯`).
    @Published var correctionModelPopover = false
    @Published var transcribeAgainPopover = false
    /// Popover modelu podsumowania otwierany z `⋯` w Summary.
    @Published var summaryModelPopover = false
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
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Color.mnText : Color.mnText2)
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

/// Błąd: ikona + słowo w `rec` (łamie się na kilka linii, w przeciwieństwie do `StateLabel`) i Retry.
struct ErrorLine: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                Text(message).fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout).foregroundStyle(.mnRec)
            .accessibilityElement(children: .combine)
            if let retry { Button("Retry", action: retry).buttonStyle(.pillSmall) }
        }
    }
}

/// Kontekst dla modelu, rozwinięty w miejscu we wnęce paska: pole `field` + obwódka 0,5 pt + promień 7,
/// rośnie z treścią (uwaga 7 — bez własnego przewijania).
private struct ContextEditor: View {
    @Binding var text: String
    var body: some View {
        GrowingTextView(text: $text, minHeight: 36, accessibilityLabel: "Context for the model")
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Who's there, what it's about — for the model").font(.system(size: 13)).foregroundStyle(.mnText2).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
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
            Text(state.myNotes.isEmpty ? "No notes." : state.myNotes)
                .font(.system(size: 14)).lineSpacing(8)
                .foregroundStyle(state.myNotes.isEmpty ? Color.mnText2 : Color.mnText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        } else {
            GrowingTextView(text: Binding(get: { state.myNotes }, set: { state.myNotes = $0; model.notes.saveMyNotes($0, for: item) }),
                            fontSize: 14, lineSpacing: 8, minHeight: 240, accessibilityLabel: "My notes")
                .overlay(alignment: .topLeading) {
                    if state.myNotes.isEmpty {
                        Text("Write notes…").font(.system(size: 14)).foregroundStyle(.mnText2).allowsHitTesting(false)
                    }
                }
        }
    }
}

// MARK: Transcript

struct TranscriptTab: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingViewState
    let item: SessionItem
    let onJump: (Utterance) -> Void
    private var busy: Bool { model.isTranscribing(item) }
    private var moving: Bool { model.recordingsMove != nil }
    /// Wznowienie w trakcie korekty dałoby drugą korektę tego samego przebiegu (F2).
    private var correcting: Bool { model.notes.isCorrecting(item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Poprawka 6: ta sama linia co w nagłówku spotkania (problem toru nagrania).
            ForEach(item.trackProblems, id: \.trackID) { p in
                if p.isWarning { WarnLabel(p.line) } else { StateLabel(.neutral, p.line) }
            }
            if model.notes.isCorrecting(item.id) {
                StateLabel(.progress(nil), "After the meeting, we improve the transcript\(modelName.map { " with \(model.modelDisplayName($0))" } ?? "")…")
                    .help(modelName ?? "")
            }
            if let why = model.notes.correctionFailureMessage(item.id) {
                ErrorLine(message: "Correction failed: \(why)", retry: model.notes.canRetryCorrection(item) ? { model.notes.retryCorrection(item) } : nil)
                    .disabled(moving)
            }
            // „Transcribe again…": stary transkrypt zostaje widoczny, dopóki nowy przebieg się nie zakwalifikuje (R23). Linia ogólna
            // tylko do pierwszego przeładowania, zanim próba ma `input.json` (wtedy wchodzi baner z modelem).
            if busy, item.transcript != nil, item.attemptNotPromoted == nil { StateLabel(.progress(nil), "Transcribing again…") }
            attemptBanner
            // Jedna linia nad listą: wersja po lewej; „Improve transcript" (tylko przed pierwszą korektą), Copy i `⋯` po prawej.
            if item.transcript != nil {
                HStack(spacing: 8) {
                    if item.corrected != nil {
                        FieldMenu(label: "Version", value: state.useCorrected ? "Corrected" : "Original", width: 120) {
                            Picker("Version", selection: $state.useCorrected) {
                                Text("Corrected").tag(true)
                                Text("Original").tag(false)
                            }
                            .pickerStyle(.inline).labelsHidden()
                        }
                    }
                    Spacer(minLength: 0)
                    if canImprove, item.corrected == nil {
                        Button("Improve transcript") { model.notes.retryCorrection(item) }
                            .buttonStyle(.pillPrimary)
                            .layoutPriority(2)
                            .disabled(moving)
                            .help("Run the correction model on this transcript")
                    }
                    copyButton
                    moreMenu
                }
                .padding(.bottom, 4)
            }
            content
        }
    }

    /// Bez wyświetlonego błędu korekty (ten ma własne Retry) — ten sam warunek co dawny przycisk na pasku.
    private var canImprove: Bool { model.notes.correctionFailureMessage(item.id) == nil && model.notes.canRetryCorrection(item) }
    /// Chip modelu był tylko przy niepustym transkrypcie przebiegu; ten sam warunek dla pozycji `⋯`.
    private var showsModelItem: Bool { item.runID != nil && item.transcript?.utterances.isEmpty == false }

    /// „Corrected with …" i „N parts kept as heard" — informacje przeniesione z paska do notki w `⋯`.
    private var menuNotes: [String] {
        guard let c = item.corrected else { return [] }
        var out: [String] = []
        if c.model != model.notes.correctionAssignment(for: item)?.model { out.append("Corrected with \(model.modelDisplayName(c.model))") }
        if c.failedBatches + c.rejectedLines > 0 { out.append("\(c.failedBatches + c.rejectedLines) parts kept as heard") }
        return out
    }

    /// `⋯` zawsze ma „Transcribe again…", więc przy transkrypcie nigdy nie jest puste.
    /// NSMenu ignoruje własną czcionkę i kolor: notka to wyłączone pozycje systemowe, nie 11 pt `mnText2`.
    private var moreMenu: some View {
        MoreMenu {
            if canImprove, item.corrected != nil {
                Button("Improve transcript again") { model.notes.retryCorrection(item) }.disabled(moving)
            }
            if showsModelItem {
                Button(MeetingModelChip.menuTitle(.correction, item: item, model: model)) {
                    DispatchQueue.main.async { state.correctionModelPopover = true }
                }
            }
            if canImprove && item.corrected != nil || showsModelItem { Divider() }
            Button("Transcribe again…") { DispatchQueue.main.async { state.transcribeAgainPopover = true } }
                .disabled(TranscribeAgainButton.blocker(item: item, model: model) != nil)
            let notes = menuNotes
            if !notes.isEmpty {
                Divider()
                ForEach(notes, id: \.self) { Text($0) }
            }
        }
        .background {
            MeetingModelChip(role: .correction, item: item, presented: $state.correctionModelPopover)
        }
        .background {
            TranscribeAgainButton(item: item, presented: $state.transcribeAgainPopover)
        }
    }

    private var copyButton: some View {
        Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.pill).help("Copy the transcript")
    }

    /// Baner R23: najnowsza próba nie jest bieżącym przebiegiem (trwa, padła, z lukami albo pusta).
    @ViewBuilder private var attemptBanner: some View {
        if let a = item.attemptNotPromoted {
            let what = a.snapshot.map { "Transcription with \(runLabel($0))" } ?? "The new transcription"
            let from = item.runSnapshot.map { "the transcript from \(runLabel($0))" } ?? "the previous transcript"
            // W toku także przy wznowieniu próby z lukami (na dysku wciąż `.gaps`); tuż po starcie nowej próby baner może do
            // pierwszego przeładowania nazywać model poprzedniej.
            if busy {
                StateLabel(.progress(nil), "\(what) is in progress — showing \(from).").wrapping()
            } else {
                // Jedna linia: krótkie „Resume" obok komunikatu (pełna etykieta z modelem ucinała się przy 900 pt).
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    WarnLabel("\(what) didn't finish — showing \(from).").help(Self.why(a.reason))
                    if a.snapshot != nil {
                        Button("Resume") { model.resume(item, runID: item.latestAttemptID) }
                            .buttonStyle(.pillSmall).fixedSize().disabled(moving || correcting)
                            .help("\(resumeLabel). Finished parts aren't paid for again.")
                    }
                }
            }
        }
    }

    /// „parakeet-tdt (EN)" — czytelna nazwa modelu i język przebiegu.
    private func runLabel(_ s: RunSnapshot) -> String {
        "\(model.modelDisplayName(s.model)) (\(s.preset.isAutoLanguage ? "Auto" : s.language?.rawValue.uppercased() ?? "?"))"
    }

    private static func why(_ r: RunSelection.Reason) -> String {
        switch r {
        case .unfinished: "It stopped before the end (failed, cancelled or the app was closed)."
        case .gaps(let n): "\(n) part\(n == 1 ? "" : "s") couldn't be transcribed."
        case .empty: "No speech was recognized."
        }
    }

    /// Wznowienie zawsze idzie do najnowszej próby; etykieta mówi, którą, gdy to nie bieżący przebieg.
    private var resumeLabel: String {
        item.attemptNotPromoted?.snapshot.map { "Resume Transcription with \(runLabel($0))" } ?? "Resume Transcription"
    }

    private var modelName: String? { model.presetFor(sessionURL: item.url)?.correction?.model }
    private var shown: Transcript? { model.transcript(of: item, corrected: state.useCorrected) }
    /// Przebieg w Auto: jedyna flaga to „obcy alfabet" (T1), więc etykieta mówi to wprost. Z migawki przebiegu (I2).
    private var isAuto: Bool { model.runLanguage(item).isAuto }

    @ViewBuilder private var content: some View {
        if let t = shown {
            // Uwaga 7: lista rośnie z treścią (przewija strona), separator `line2` między wierszami.
            LazyVStack(alignment: .leading, spacing: 0) {
                if !t.failedChunks.isEmpty {
                    Button(busy ? "Transcribing…" : "Retry Failed Parts") { model.resume(item, runID: item.runID) }
                        .buttonStyle(.pillSmall)
                        .disabled(busy || moving || correcting)
                        .help("Sends only the parts that failed; finished parts aren't paid for again")
                        .padding(.bottom, 8)
                }
                Rectangle().fill(.mnLine2).frame(height: 0.5)
                ForEach(Array(lines(t).enumerated()), id: \.offset) { i, line in
                    if i > 0 { Rectangle().fill(.mnLine2).frame(height: 0.5) }
                    switch line {
                    case .utterance(let u): UtteranceRow(utterance: u, isAuto: isAuto) { onJump(u) }
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
                    StateLabel(.progress(nil), "Transcribing…")
                } else {
                    // Preset zamrożony przy nagraniu, nie bieżący (spec §1.5); Resume bierze migawkę z input.json przebiegu.
                    Group {
                        if let p = model.presetFor(sessionURL: item.url) {
                            Button("Transcribe with \(p.name)") { model.transcribe(sessionURL: item.url, preset: p) }.buttonStyle(.pillPrimary)
                        }
                        if item.latestAttemptID != nil {
                            Button(resumeLabel) { model.resume(item, runID: item.latestAttemptID) }.buttonStyle(.pill).disabled(correcting)
                        }
                        // D13 (F6): po próbie bez transkryptu inny model i język też do wyboru — ta sama bramka co w nagłówku.
                        TranscribeAgainButton(item: item)
                    }
                    .disabled(moving)
                }
            }
        }
    }

    private enum Line { case utterance(Utterance), mute(MuteNote) }

    /// Wypowiedzi z liniami wyciszenia („Microphone muted 0:05–0:12”, macos.md §11.5) w kolejności czasu.
    private func lines(_ t: Transcript) -> [Line] {
        var mutes = MuteNote.of(summary: item.summary)[...]
        var out: [Line] = []
        for u in t.utterances {
            while let m = mutes.first, m.start <= u.start { out.append(.mute(m)); mutes = mutes.dropFirst() }
            out.append(.utterance(u))
        }
        return out + mutes.map(Line.mute)
    }

    private func copy() {
        guard let t = shown else { return }
        let text = lines(t).map { line in
            switch line {
            case .utterance(let u): "[\(MeetingDetailView.time(u.start))] \(u.speaker == .me ? "Me" : "Them"): \(u.text)"
            case .mute(let m): "[\(MeetingDetailView.time(m.start))] \(m.line)"
            }
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: Summary

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
    /// Spec 6: notatka powstała innym modelem niż ten z presetu — notka w `⋯`, znika po zgodności. Pełne id w tekście.
    private var madeWithLine: String? {
        guard let made = item.notes.summary?.model, let preset = model.notes.presetSummaryChoice(for: item)?.assignment.model,
              made != preset else { return nil }
        return "Made with \(model.modelDisplayName(made)) (\(made)); preset: \(model.modelDisplayName(preset)) (\(preset))"
    }
    private var hasText: Bool {
        guard let t = model.transcript(of: item, corrected: state.useCorrected) else { return false }
        return !NotePromptBuilder.transcriptLines(t).isEmpty
    }
    /// Powód, dla którego „Generate notes" jest nieaktywne: brak transkryptu to coś innego niż transkrypt bez treści.
    private var disabledReason: String {
        item.transcript == nil ? "Transcript isn't ready yet." : "Nothing to summarize: the transcript has no usable text."
    }

    /// Uwaga 7 (b-summary0.png, b-meeting.png): bez karty — ten sam pasek we wnęce przed i po generowaniu, pod nim
    /// linie stanu i notatka albo jedna linia stanu pustego. Przewija strona widoku spotkania.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar(item.notes.summary)
            if choice?.isFallback == true || choice == nil { modelLine }
            if item.notes.summary == nil, !hasText { Text(disabledReason).font(.callout).foregroundStyle(.mnText2) }
            if gen == .generating { generatingRow }
            if correcting, gen != .generating, hasText {
                Text("Generate notes once the transcript has been improved.").font(.callout).foregroundStyle(.mnText2)
            }
            errorView
            if let s = item.notes.summary {
                MarkdownView(blocks: MarkdownBlocks.group(s.markdown)).padding(.top, 8)
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
            StateLabel(.progress(nil), model.notes.progress[item.id]?.text ?? "Generating notes…")
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
        let kind = state.useCorrected && item.corrected != nil ? "corrected" : "original"
        let details = [
            item.duration.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) },
            model.runLanguage(item).language?.englishName,
        ].compactMap { $0 }
        return "Uses the \(kind) transcript\(details.isEmpty ? "" : " (\(details.joined(separator: ", ")))")."
    }

    /// Jedna linia bez wnęki: szablon · kontekst · przycisk · Copy · `⋯`. „Add context" rozwija pole pod linią.
    /// Przed notatką jedyny primary „Generate notes", po — „Regenerate" + Copy (oba `.pill`).
    private func bar(_ s: NoteSummary?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
                if let s {
                    Button { run() } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                        .buttonStyle(.pill)
                        .layoutPriority(2)
                        .disabled(gen == .generating || !hasText || choice == nil || moving || correcting)
                    Button { copy(s.markdown) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.pill)
                        .layoutPriority(2)
                        .help("Copy the notes")
                } else {
                    Button("Generate notes") { run() }
                        .buttonStyle(.pillPrimary)
                        .layoutPriority(2)
                        .disabled(gen == .generating || !hasText || choice == nil || moving || correcting)
                        // ⌘↩, nie sam Return: Return w polu kontekstu ma wstawić nową linię, a nie uruchomić płatne generowanie.
                        .keyboardShortcut(.return, modifiers: .command)
                }
                moreMenu
            }
            if state.showContext {
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

    /// Notatki o przebiegu: model inny niż w presecie i długie spotkanie. NSMenu ignoruje czcionkę — to wyłączone pozycje.
    private var menuNotes: [String] {
        var out: [String] = []
        if let made = madeWithLine { out.append(made) }
        if let parts = item.notes.summary?.condensedParts { out.append("Long meeting: condensed in \(parts) parts before summarizing.") }
        return out
    }

    /// `⋯` zawsze ma pozycję modelu (jak dawny chip na pasku).
    private var moreMenu: some View {
        MoreMenu {
            Button(MeetingModelChip.menuTitle(.summary, item: item, model: model)) {
                DispatchQueue.main.async { state.summaryModelPopover = true }
            }
            .help(MeetingModelChip.override(.summary, item: item, model: model) != nil
                  ? "Chosen for this meeting. The preset uses \(model.notes.presetSummaryChoice(for: item)?.assignment.model ?? "no model")."
                  : "Choose another summary model for this meeting")
            let notes = menuNotes
            if !notes.isEmpty {
                Divider()
                ForEach(notes, id: \.self) { Text($0) }
            }
        }
        .background {
            MeetingModelChip(role: .summary, item: item, presented: $state.summaryModelPopover)
        }
    }

    /// Popup szablonu: pole 130 × 28, promień 7 (makieta: `.field`). Menu zostaje systemowe.
    private var templateMenu: some View {
        FieldMenu(label: "Template", value: template.name, width: 130) {
            ForEach(model.notes.templates.all()) { t in
                Button(t.name) { state.templateID = t.id }
            }
            Divider()
            Button("Manage templates…") { model.section = .templates }
        }
    }

    @ViewBuilder private var errorView: some View {
        if case .failed(let message) = gen { ErrorLine(message: message) { run() }.disabled(moving || correcting) }
    }

    private func run() {
        model.notes.generate(item: item, useCorrected: state.useCorrected, template: template, context: state.context)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Linia wyciszenia toru w transkrypcie: czas w kolumnie czasu, opis w `text2` (informacja, nie ostrzeżenie).
private struct MuteRow: View {
    let note: MuteNote
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(MeetingDetailView.time(note.start)).monospacedDigit().frame(width: 72, alignment: .leading)
            Label(note.line, systemImage: note.trackID == "system" ? "speaker.slash" : "mic.slash")
        }
        .font(.system(size: 13)).foregroundStyle(.mnText2)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
