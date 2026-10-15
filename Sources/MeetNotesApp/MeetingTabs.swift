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

// MARK: My notes

struct MyNotesTab: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: MeetingViewState
    let item: SessionItem

    var body: some View {
        TextEditor(text: Binding(get: { state.myNotes }, set: { state.myNotes = $0; model.notes.saveMyNotes($0, for: item) }))
            .font(.body)
            .overlay(alignment: .topLeading) {
                if state.myNotes.isEmpty {
                    Text("Write notes…").foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 8) {
            if model.notes.isCorrecting(item.id) {
                Label("After the meeting, we improve the transcript\(modelName.map { " with \($0)" } ?? "")…", systemImage: "wand.and.stars")
                    .font(.caption).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if let why = model.notes.correctionFailureMessage(item.id) {
                HStack {
                    Label("Correction failed: \(why)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Retry") { model.notes.retryCorrection(item) }.disabled(!model.notes.canRetryCorrection(item))
                }
            } else if model.notes.canRetryCorrection(item) {
                HStack { Spacer(); Button("Improve transcript") { model.notes.retryCorrection(item) }.help("Run the preset's correction model on this transcript") }
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
                            .font(.caption).foregroundStyle(.secondary)
                            .help("Corrections that failed a check were left as the model heard them")
                    }
                    Spacer()
                    Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }.help("Copy the transcript")
                }
            } else if item.transcript != nil {
                HStack { Spacer(); Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }.help("Copy the transcript") }
            }
            content
        }
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
                        .disabled(busy)
                        .help("Sends only the parts that failed; finished parts aren't paid for again")
                }
                ForEach(Array(t.utterances.enumerated()), id: \.offset) { _, u in
                    UtteranceRow(utterance: u, isAuto: isAuto) { onJump(u) }
                }
                if !t.failedChunks.isEmpty {
                    SwiftUI.Section("Gaps") {
                        ForEach(Array(t.failedChunks.enumerated()), id: \.offset) { _, f in
                            Label("Couldn't transcribe \(MeetingDetailView.time(f.start))–\(MeetingDetailView.time(f.end))", systemImage: "exclamationmark.circle")
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("No transcript yet", systemImage: "text.alignleft")
            } actions: {
                if busy {
                    ProgressView("Transcribing…")
                } else {
                    // Preset zamrożony przy nagraniu, nie bieżący (spec §1.5); Resume bierze migawkę z input.json przebiegu.
                    if let p = model.presetFor(sessionURL: item.url) {
                        Button("Transcribe with \(p.name)") { model.transcribe(sessionURL: item.url, preset: p) }
                    }
                    if item.runID != nil { Button("Resume Transcription") { model.resume(item) } }
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
            if let label = c.label { Text(label).font(.caption).foregroundStyle(.secondary) }
        } else {
            Text("No preset has a summary model. Choose one in Presets.").font(.caption).foregroundStyle(.orange)
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
                    if gen == .generating { ProgressView("Generating notes…") }
                    errorView
                    MarkdownView(blocks: MarkdownBlocks.group(s.markdown))
                } else {
                    card
                }
            }
            .padding(16)
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

    // Przed pierwszym generowaniem: karta (spec 1.5, decyzja 3).
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template").font(.caption).foregroundStyle(.secondary)
            templateMenu
            Text("Context for the model (optional)").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $state.context).frame(minHeight: 70).font(.body)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            modelLine
            if gen == .generating {
                ProgressView("Generating notes…")
            } else {
                Button("Generate notes") { run() }.disabled(!hasText || choice == nil).keyboardShortcut(.defaultAction)
                if !hasText { Text(disabledReason).font(.caption).foregroundStyle(.secondary) }
            }
            errorView
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 560)
    }

    // Po wygenerowaniu: pasek nad notatką.
    private func bar(_ s: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                templateMenu
                Button { state.showContext.toggle() } label: { Label("Context", systemImage: "text.badge.plus") }
                    .help("Add or change the context for the model")
                Spacer()
                Button { copy(s.markdown) } label: { Label("Copy", systemImage: "doc.on.doc") }.help("Copy the notes")
                Button("Regenerate") { run() }.disabled(gen == .generating || !hasText || choice == nil)
            }
            modelLine
            if state.showContext {
                TextEditor(text: $state.context).frame(minHeight: 60).font(.body)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        }
    }

    private var templateMenu: some View {
        Menu {
            ForEach(model.notes.templates.all()) { t in
                Button(t.name) { state.templateID = t.id }
            }
            Divider()
            Button("Manage templates…") { model.section = .templates }
        } label: {
            Text(template.name)
        }
        .fixedSize()
    }

    @ViewBuilder private var errorView: some View {
        if case .failed(let message) = gen {
            HStack {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                Button("Retry") { run() }
            }
        }
    }

    private func run() {
        model.notes.generate(item: item, useCorrected: state.useCorrected, template: template, context: state.context)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
