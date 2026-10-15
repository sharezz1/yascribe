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
    @Published var titleDraft = ""
    @Published var myNotes = ""
    @Published var loadedMyNotes = false
    @Published var useCorrected = true
    @Published var templateID = Template.standard.id
    @Published var context = ""
    @Published var contextPrefilled = false
    @Published var showContext = false
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

/// Okrągły przycisk ikony 28 pt (`.icon-btn` w makiecie) — Copy w pasku generowania.
private struct CircleIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Color.mnText : Color.mnText3)
            .frame(width: 28, height: 28)
            .background(.mnCard, in: Circle())
            .overlay(Circle().strokeBorder(.mnLine, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
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

/// Pole wielolinijkowe na kontekst: `field` + obwódka 0,5 pt + promień 7.
private struct ContextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat
    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13)).foregroundStyle(.mnText)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(minHeight: minHeight)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
    }
}

// MARK: My notes

struct MyNotesTab: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingViewState
    let item: SessionItem

    var body: some View {
        TextEditor(text: Binding(get: { state.myNotes }, set: { state.myNotes = $0; model.notes.saveMyNotes($0, for: item) }))
            .font(.system(size: 14))
            .lineSpacing(5)
            .foregroundStyle(.mnText)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
                if state.myNotes.isEmpty {
                    Text("Write notes…").font(.system(size: 14)).foregroundStyle(.mnText2).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.notes.isCorrecting(item.id) {
                StateLabel(.progress(nil), "After the meeting, we improve the transcript\(modelName.map { " with \($0)" } ?? "")…")
            }
            if let why = model.notes.correctionFailureMessage(item.id) {
                ErrorLine(message: "Correction failed: \(why)", retry: model.notes.canRetryCorrection(item) ? { model.notes.retryCorrection(item) } : nil)
            } else if model.notes.canRetryCorrection(item) {
                HStack { Spacer(); Button("Improve transcript") { model.notes.retryCorrection(item) }.buttonStyle(.pillSmall).help("Run the preset's correction model on this transcript") }
            }
            if item.corrected != nil {
                HStack {
                    Picker("Version", selection: $state.useCorrected) {
                        Text("Corrected").tag(true)
                        Text("Original").tag(false)
                    }
                    .pickerStyle(.segmented).frame(width: 220)
                    if let c = item.corrected, c.failedBatches > 0 || c.rejectedLines > 0 {
                        Label("\(c.failedBatches + c.rejectedLines) parts kept as heard", systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.mnText2)
                            .help("Corrections that failed a check were left as the model heard them")
                    }
                    Spacer()
                    copyButton
                }
            } else if item.transcript != nil {
                HStack { Spacer(); copyButton }
            }
            content
        }
    }

    private var copyButton: some View {
        Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.pillSmall).help("Copy the transcript")
    }

    private var modelName: String? { model.presetFor(sessionURL: item.url)?.correction?.model }
    private var shown: Transcript? { item.transcript(corrected: state.useCorrected) }
    /// Preset Auto: jedyna flaga to „obcy alfabet" (T1), więc etykieta mówi to wprost.
    private var isAuto: Bool { model.presetFor(sessionURL: item.url)?.isAutoLanguage == true }

    @ViewBuilder private var content: some View {
        if let t = shown {
            List {
                if !t.failedChunks.isEmpty {
                    Button(busy ? "Transcribing…" : "Retry Failed Parts") { model.resume(item) }
                        .buttonStyle(.pillSmall)
                        .disabled(busy)
                        .help("Sends only the parts that failed; finished parts aren't paid for again")
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(t.utterances.enumerated()), id: \.offset) { _, u in
                    UtteranceRow(utterance: u, isAuto: isAuto) { onJump(u) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
                        .listRowSeparatorTint(.mnLine2)
                }
                if !t.failedChunks.isEmpty {
                    SwiftUI.Section("Gaps") {
                        ForEach(Array(t.failedChunks.enumerated()), id: \.offset) { _, f in
                            Label("Couldn't transcribe \(MeetingDetailView.time(f.start))–\(MeetingDetailView.time(f.end))", systemImage: "exclamationmark.circle")
                                .font(.callout).foregroundStyle(.mnWarn)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView {
                Label("No transcript yet", systemImage: "text.alignleft")
            } actions: {
                if busy {
                    StateLabel(.progress(nil), "Transcribing…")
                } else {
                    // Preset zamrożony przy nagraniu, nie bieżący (spec §1.5); Resume bierze migawkę z input.json przebiegu.
                    if let p = model.presetFor(sessionURL: item.url) {
                        Button("Transcribe with \(p.name)") { model.transcribe(sessionURL: item.url, preset: p) }.buttonStyle(.pillPrimary)
                    }
                    if item.runID != nil { Button("Resume Transcription") { model.resume(item) }.buttonStyle(.pill) }
                }
            }
        }
    }

    private func copy() {
        guard let t = shown else { return }
        let text = t.utterances.map { "[\(MeetingDetailView.time($0.start))] \($0.speaker == .me ? "Me" : "Them"): \($0.text)" }.joined(separator: "\n")
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

    /// „Using <model> from preset <nazwa>" przy zastępstwie; ostrzeżenie, gdy żaden preset nie ma modelu podsumowania.
    @ViewBuilder private var modelLine: some View {
        if let c = choice {
            if let label = c.label { Text(label).font(.subheadline).foregroundStyle(.mnText2) }
        } else {
            Label("No preset has a summary model. Choose one in Presets.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.mnWarn)
        }
    }
    private var hasText: Bool {
        guard let t = item.transcript(corrected: state.useCorrected) else { return false }
        return !NotePromptBuilder.transcriptLines(t).isEmpty
    }
    /// Powód, dla którego „Generate notes" jest nieaktywne: brak transkryptu to coś innego niż transkrypt bez treści.
    private var disabledReason: String {
        item.transcript == nil ? "Transcript isn't ready yet." : "Nothing to summarize: the transcript has no usable text."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = item.notes.summary {
                    bar(s)
                    if gen == .generating { StateLabel(.progress(nil), "Generating notes…") }
                    errorView
                    MarkdownView(blocks: MarkdownBlocks.group(s.markdown))
                } else {
                    card
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { prefillContext() }
    }

    /// Kontekst wstępnie z My notes, dopóki użytkownik go nie ruszył.
    private func prefillContext() {
        guard !state.contextPrefilled else { return }
        state.contextPrefilled = true
        let mine = item.notes.myNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.context.isEmpty, !mine.isEmpty { state.context = mine }
        if let s = item.notes.summary { state.templateID = s.templateID; if state.context.isEmpty { state.context = s.context } }
    }

    // Przed pierwszym generowaniem: karta (spec 1.5, decyzja 3) z jedynym przyciskiem głównym.
    private var card: some View {
        Card {
            FormRow(label: "Template") { templateMenu }
            RowDivider()
            FormRow(label: "Context", caption: "For the model (optional)") {
                ContextEditor(text: $state.context, minHeight: 70)
            }
            RowDivider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    modelLine
                    if !hasText { Text(disabledReason).font(.subheadline).foregroundStyle(.mnText2) }
                }
                Spacer(minLength: 0)
                if gen == .generating {
                    StateLabel(.progress(nil), "Generating notes…")
                } else {
                    Button("Generate notes") { run() }
                        .buttonStyle(.pillPrimary)
                        .disabled(!hasText || choice == nil)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            if case .failed(let message) = gen {
                RowDivider()
                ErrorLine(message: message) { run() }.padding(.vertical, 12).padding(.horizontal, 16)
            }
        }
    }

    // Po wygenerowaniu: pasek we wnęce `sunk` nad notatką (makieta: `.genbar`).
    private func bar(_ s: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                templateMenu
                Button { state.showContext.toggle() } label: {
                    Text(state.context.isEmpty ? "Add context" : "Context: \(state.context.replacingOccurrences(of: "\n", with: " "))")
                        .font(.callout).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add or change the context for the model")
                if let c = choice {
                    Text(c.assignment.model).font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(1)
                        .layoutPriority(1) // id modelu wygrywa z kontekstem (przegląd migawek: „deepseek/…-fla…”)
                        .help(c.label ?? "Summary model")
                }
                Button { run() } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                    .buttonStyle(.pill)
                    .disabled(gen == .generating || !hasText || choice == nil)
                Button { copy(s.markdown) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(CircleIconButtonStyle())
                    .help("Copy the notes")
                    .accessibilityLabel("Copy the notes")
            }
            .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 6)
            .background(.mnSunk, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if choice?.isFallback == true { modelLine }
            if state.showContext { ContextEditor(text: $state.context, minHeight: 60) }
        }
        .padding(.bottom, 8)
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
        if case .failed(let message) = gen { ErrorLine(message: message) { run() } }
    }

    private func run() {
        model.notes.generate(item: item, useCorrected: state.useCorrected, template: template, context: state.context)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
