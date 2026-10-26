import AppKit
import YascribeNotes
import YascribeProviders
import SwiftUI

/// Zakładka Dictionary (faza 2.1, makiety `docs/design/makiety/dictionary-*.png`): jeden słownik użytkownika, Termy z Aliasami.
/// Edycja Terma w arkuszu, import i eksport `vocab_core.txt` + `replacements.tsv`, licznik Termów poza budżetem polecenia korektora.
struct DictionaryView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: DictionaryViewState

    init(state: DictionaryViewState = DictionaryViewState()) { _state = StateObject(wrappedValue: state) }

    private static let vocabularyFile = "vocab_core.txt"
    private static let replacementsFile = "replacements.tsv"
    private static let maxImportBytes = 5_000_000

    var body: some View {
        ScrollPage(640) {
            VStack(alignment: .leading, spacing: 0) {
                if model.dictionary.terms.isEmpty { emptyState } else { listState }
            }
        }
        .contentBackground()
        .navigationTitle("Dictionary")
        .dismissibleSheet(isPresented: Binding(get: { state.draft != nil }, set: { if !$0 { state.closeEditor() } }), onDismiss: { state.closeEditor() }) {
            DictionaryTermSheet(state: state)
        }
        .dismissibleSheet(isPresented: Binding(get: { state.importReport != nil }, set: { if !$0 { state.importReport = nil } }), onDismiss: { state.importReport = nil }) {
            if let report = state.importReport {
                DictionaryImportSheet(report: report, files: state.importedNames) { state.importReport = nil }
            }
        }
        .confirmationDialog("Replace existing files?", isPresented: Binding(get: { state.pendingExport != nil }, set: { if !$0 { state.pendingExport = nil } })) {
            Button("Replace", role: .destructive) { if let dir = state.pendingExport { write(to: dir) } }
        } message: {
            Text("\(state.pendingExport?.lastPathComponent ?? "The folder") already has files with these names. Their contents will be replaced.")
        }
    }

    // MARK: Stan pusty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle("Dictionary").padding(.bottom, 18)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No terms yet").font(.system(size: 14, weight: .semibold)).foregroundStyle(.mnText)
                    (Text("Add the names and words your meetings keep getting wrong. A ")
                        + Text("term").fontWeight(.semibold).foregroundStyle(.mnText)
                        + Text(" is the correct spelling. Its ")
                        + Text("aliases").fontWeight(.semibold).foregroundStyle(.mnText)
                        + Text(" are the wrong spellings the transcript produces; they are replaced automatically, in every meeting."))
                        .font(.callout).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text("Roky, Rokm").foregroundStyle(.mnText2)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.mnText3).accessibilityHidden(true)
                        Text("Nimbu").fontWeight(.semibold).foregroundStyle(.mnText)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.mnSunk, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityElement(children: .combine)
                    HStack(spacing: 10) {
                        Button { state.openNew() } label: { Label("New term", systemImage: "plus") }.buttonStyle(.pillPrimary)
                        Button("Import…") { importFiles() }.buttonStyle(.pill)
                        Text("Reads \(Self.vocabularyFile) and \(Self.replacementsFile)").font(.system(size: 11)).foregroundStyle(.mnText2)
                    }
                    .padding(.top, 4)
                    messages
                }
                .padding(16)
            }
        }
    }

    // MARK: Lista

    private var listState: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PageTitle("Dictionary")
                Spacer()
                Button("Import…") { importFiles() }.buttonStyle(.pill)
                Button("Export…") { exportFiles() }.buttonStyle(.pill)
                Button { state.openNew() } label: { Label("New term", systemImage: "plus") }
                    .buttonStyle(.pill)
                    .help("New term")
            }
            .padding(.bottom, 18)
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.mnText2).accessibilityHidden(true)
                    TextField("Search terms and aliases", text: $state.query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).frame(width: 260, height: 28)
                .background(.mnField, in: Capsule())
                .overlay(Capsule().strokeBorder(.mnLine, lineWidth: 0.5))
                Spacer(minLength: 0)
                Text(countLine).font(.system(size: 11)).monospacedDigit().foregroundStyle(.mnText2)
            }
            if let c = counter {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11, weight: .bold)).foregroundStyle(.mnWarn)
                    Text("\(c.count) \(c.count == 1 ? "term doesn’t" : "terms don’t") fit the correction prompt").foregroundStyle(.mnText)
                    Spacer(minLength: 8)
                    Text(c.detail).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.middle)
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.mnSunk, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
                .help("Terms are added to the correction prompt by priority; the rest are left out. A larger context window or a higher priority keeps more of them.")
            }
            messages.padding(.top, 10)
            if shown.isEmpty {
                Text("No terms match “\(state.query)”.").font(.callout).foregroundStyle(.mnText2).padding(.top, 16).padding(.horizontal, 2)
            } else {
                Card {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, term in
                        if i > 0 { RowDivider() }
                        Button { state.open(term) } label: { DictionaryRow(term: term, selected: state.selection == term.id) }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(state.selection == term.id ? .isSelected : [])
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    @ViewBuilder private var messages: some View {
        if let e = state.error {
            StateLabel(.bad, e).wrapping()
        } else if let n = state.notice {
            StateLabel(.ok, n).wrapping()
        }
    }

    /// Termy w kolejności polecenia (High, Normal, Low; w obrębie rangi kolejność słownika), po filtrze wyszukiwania.
    private var shown: [DictionaryTerm] {
        let ranked = TermPriority.allCases.flatMap { p in model.dictionary.terms.filter { $0.priority == p } }
        let q = UserDictionary.key(state.query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return ranked }
        return ranked.filter { t in
            UserDictionary.key(t.text).contains(q) || t.aliases.contains { UserDictionary.key($0.text).contains(q) }
        }
    }

    private var countLine: String {
        let terms = model.dictionary.terms
        let aliases = terms.reduce(0) { $0 + $1.aliases.count }
        let total = "\(terms.count) \(terms.count == 1 ? "term" : "terms") · \(aliases) \(aliases == 1 ? "alias" : "aliases")"
        return shown.count == terms.count ? total : "\(shown.count) of \(total)"
    }

    /// D10: ile Termów nie mieści się w poleceniu korektora presetu aktywnego dla nowych nagrań (nie liczy nadpisań w pojedynczym spotkaniu).
    /// Budżet lokalny z pola „Context window” (bez sondy `/api/ps`, więc przybliżenie), dla API stały limit; ukryte przy 0 i bez korekty.
    private var counter: (count: Int, detail: String)? {
        guard let c = model.activePreset?.correction, let provider = model.provider(c.providerID) else { return nil }
        let budget = ContextBudget.resolve(provider: provider, detected: nil)
        let omitted = DictionaryPrompt.make(model.dictionary, link: nil, maxChars: DictionaryPrompt.maxChars(budget: budget)).omittedTerms
        guard omitted > 0 else { return nil }
        return (omitted, budget.map { "\(c.model) · context \($0.tokens)" } ?? c.model)
    }

    // MARK: Import i eksport

    /// Jedno okno wyboru, wiele plików: `.tsv` to Aliasy (`replacements.tsv`), każdy inny plik to lista Termów (`vocab_core.txt`).
    private func importFiles() {
        state.error = nil; state.notice = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose \(Self.vocabularyFile) and/or \(Self.replacementsFile)"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var vocabularies: [String] = [], replacements: [String] = []
        do {
            for url in panel.urls {
                // Limit rozmiaru przed odczytem; przekroczenie przerywa cały import, zanim cokolwiek się zmieni.
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.maxImportBytes {
                    state.error = "“\(url.lastPathComponent)” is larger than 5 MB. Nothing was imported."
                    return
                }
                let text = try String(contentsOf: url, encoding: .utf8)
                if url.pathExtension.lowercased() == "tsv" { replacements.append(text) } else { vocabularies.append(text) }
            }
        } catch {
            state.error = "Couldn’t read the file: \(error.localizedDescription). Nothing was imported."
            return
        }
        // Każdy plik osobno (stan sekcji i BOM nie przechodzą dalej); słownik zmienia się dopiero po udanym zapisie.
        let result = DictionaryTransfer.importFiles(vocabularies: vocabularies, replacements: replacements, into: model.dictionary)
        if result.dictionary != model.dictionary {
            if let failure = DictionaryEdit.commit(result.dictionary, replacing: model.dictionary, set: { model.dictionary = $0 }, save: { model.saveDictionary() }) {
                state.error = "\(failure) Nothing was imported; try again."
                return
            }
        }
        state.importedNames = panel.urls.map(\.lastPathComponent)
        state.importReport = result.report
    }

    /// Wybór katalogu; istniejące pliki o tych nazwach nadpisujemy dopiero po zgodzie (arkusz potwierdzenia).
    private func exportFiles() {
        state.error = nil; state.notice = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for \(Self.vocabularyFile) and \(Self.replacementsFile)"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let clash = [Self.vocabularyFile, Self.replacementsFile].contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        if clash { state.pendingExport = dir } else { write(to: dir) }
    }

    private func write(to dir: URL) {
        state.pendingExport = nil
        do {
            try DictionaryTransfer.exportVocabulary(model.dictionary).write(to: dir.appendingPathComponent(Self.vocabularyFile), atomically: true, encoding: .utf8)
            try DictionaryTransfer.exportReplacements(model.dictionary).write(to: dir.appendingPathComponent(Self.replacementsFile), atomically: true, encoding: .utf8)
            state.notice = "Exported \(Self.vocabularyFile) and \(Self.replacementsFile) to \(dir.lastPathComponent)."
        } catch {
            state.error = "Couldn’t export: \(error.localizedDescription)"
        }
    }
}

/// Wiersz listy: Term, pod nim Aliasy (wyłączone z dopiskiem), ranga po prawej.
private struct DictionaryRow: View {
    let term: DictionaryTerm
    let selected: Bool

    private var aliasLine: String {
        guard !term.aliases.isEmpty else { return "No aliases · hint for the model only" }
        return term.aliases.map { a in
            switch (a.risky, a.enabled) {
            case (true, false): "\(a.text) (risky, off)"
            case (true, true): "\(a.text) (risky)"
            case (false, false): "\(a.text) (off)"
            default: a.text
            }
        }.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(term.text).font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText).lineLimit(1)
                Text(aliasLine).font(.system(size: 11)).italic(term.aliases.isEmpty).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(term.priority.label).font(.system(size: 12, weight: term.priority == .high ? .semibold : .regular))
                .foregroundStyle(term.priority == .high ? .mnText : .mnText2)
                .padding(.top, 3)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.mnSelection : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension TermPriority {
    var label: String {
        switch self {
        case .high: "High"
        case .normal: "Normal"
        case .low: "Low"
        }
    }
}

// MARK: - Arkusz edycji Terma

struct DictionaryTermSheet: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: DictionaryViewState

    private var term: Binding<String> {
        Binding(get: { state.draft?.text ?? "" }, set: { state.draft?.text = $0; state.termError = nil })
    }
    private var priority: Binding<TermPriority> {
        Binding(get: { state.draft?.priority ?? .normal }, set: { state.draft?.priority = $0 })
    }
    private var aliases: [DictionaryAlias] { state.draft?.aliases ?? [] }

    /// Dostęp do wiersza po indeksie z ochroną: po usunięciu wiersza SwiftUI jeszcze raz pyta o jego wiązanie.
    private func alias(_ i: Int) -> Binding<DictionaryAlias> {
        Binding(get: { state.draft.flatMap { $0.aliases.indices.contains(i) ? $0.aliases[i] : nil } ?? DictionaryAlias("") },
                set: { if state.draft?.aliases.indices.contains(i) == true { state.draft?.aliases[i] = $0 } })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.draftIsNew ? "New term" : "Edit term").font(.system(size: 14, weight: .semibold)).foregroundStyle(.mnText)
                        .padding(.bottom, 8)
                    FormRow(label: "Term", caption: state.termError, isError: true, labelWidth: 70) {
                        TextField("Correct spelling, e.g. Nimbu", text: term).textFieldStyle(.plain).fieldBox()
                    }
                    .padding(.horizontal, -16)
                    FormRow(label: "Priority", labelWidth: 70) {
                        HStack(spacing: 12) {
                            FieldMenu(label: "Priority", value: priority.wrappedValue.label, width: 120) {
                                Picker("Priority", selection: priority) {
                                    ForEach(TermPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.inline).labelsHidden()
                            }
                            Text("Low is left out of the prompt first.").font(.system(size: 11)).foregroundStyle(.mnText2)
                        }
                    }
                    .padding(.horizontal, -16)
                    SectionHeader("Aliases", note: nil) { Text("replaced in every transcript").font(.system(size: 11)).foregroundStyle(.mnText2) }
                    Card {
                        HStack(spacing: 12) {
                            Text("Alias").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Risky").frame(width: 62, alignment: .leading)
                            Text("On").frame(width: 38, alignment: .center)
                            Color.clear.frame(width: 18, height: 1)
                        }
                        .font(.system(size: 11)).foregroundStyle(.mnText2)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        // Wiele Aliasów (import potrafi dać dziesiątki): od kilku wierszy lista przewija się, a Save/Cancel/Delete zostają na widoku.
                        if aliases.count > 7 { ScrollView { aliasRows }.frame(maxHeight: 280) } else { aliasRows }
                        RowDivider(inset: 0)
                        HStack(spacing: 8) {
                            TextField("Add alias", text: $state.newAlias).textFieldStyle(.plain).fieldBox()
                                .onSubmit { _ = addAlias() }
                                .onChange(of: state.newAlias) { _, _ in state.aliasError = nil }
                            Button("Add") { _ = addAlias() }.buttonStyle(.pillSmall)
                                .disabled(state.newAlias.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(10)
                    }
                    if let e = state.aliasError { StateLabel(.bad, e).wrapping().padding(.top, 8).padding(.leading, 2) }
                    Text("Risky means the alias is also an ordinary word (Rok is a name). It is added switched off; turn it on only if you accept that it may replace correct text.")
                        .font(.system(size: 11)).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10).padding(.leading, 2)
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            }
            if let e = state.saveError {
                StateLabel(.bad, e).wrapping().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
                    .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
            }
            HStack(spacing: 8) {
                if !state.draftIsNew {
                    Button { state.confirmingDelete = true } label: { Text("Delete term").foregroundStyle(.mnRec) }.buttonStyle(.pillSmall)
                }
                Spacer()
                Button("Cancel") { state.closeEditor() }.buttonStyle(.pill).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.pillPrimary).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
        }
        .frame(width: 500)
        .background(.mnCard)
        .tint(.mnAccent) // arkusz nie dziedziczy akcentu z okna (macos.md §10, odstępstwo 5)
        .confirmationDialog("Delete “\(state.draft?.text ?? "this term")”?", isPresented: $state.confirmingDelete) {
            Button("Delete term", role: .destructive) { delete() }
        } message: {
            Text("Its aliases stop being replaced. Transcripts already corrected keep their text.")
        }
    }

    private var aliasRows: some View {
        VStack(spacing: 0) {
            ForEach(aliases.indices, id: \.self) { i in
                RowDivider(inset: 0)
                HStack(spacing: 12) {
                    Text(alias(i).wrappedValue.text).foregroundStyle(alias(i).wrappedValue.enabled ? .mnText : .mnText2)
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Risky", isOn: alias(i).risky).toggleStyle(.checkbox).frame(width: 62, alignment: .leading)
                        .accessibilityLabel("\(alias(i).wrappedValue.text) is risky")
                    Toggle("", isOn: alias(i).enabled).toggleStyle(.switch).labelsHidden().controlSize(.small).frame(width: 38)
                        .accessibilityLabel("\(alias(i).wrappedValue.text) is on")
                    Button { state.draft?.aliases.remove(at: i); state.aliasError = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.mnText2)
                    }
                    .buttonStyle(.plain).frame(width: 18)
                    .help("Remove alias")
                    .accessibilityLabel("Remove alias \(alias(i).wrappedValue.text)")
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14).padding(.vertical, 7)
            }
        }
    }

    /// Dodaje Alias z pola do kopii roboczej, jeśli cały słownik by go przyjął (reguły `upsert`); `false` = błąd pokazany przy polu.
    private func addAlias() -> Bool {
        guard var d = state.draft else { return true }
        let text = state.newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if d.aliases.contains(where: { UserDictionary.key($0.text) == UserDictionary.key(text) }) {
            state.aliasError = "“\(text)” is already in this list."
            return false
        }
        d.aliases.append(DictionaryAlias(text))
        // Próba na kopii słownika; pusty Term nie może zasłonić błędów Aliasu, błędy samego Terma wychodzą dopiero przy Save.
        var trial = d, scratch = model.dictionary
        if UserDictionary.key(trial.text).isEmpty { trial.text = "New term" }
        do { try scratch.upsert(trial) } catch {
            state.show(error, draftText: trial.text)
            if state.aliasError != nil { return false }
            state.termError = nil
        }
        state.draft = d
        state.newAlias = ""
        state.aliasError = nil
        return true
    }

    private func save() {
        guard addAlias(), let d = state.draft else { return }
        var dictionary = model.dictionary
        do { try dictionary.upsert(d) } catch {
            state.show(error, draftText: d.text)
            return
        }
        if let failure = DictionaryEdit.commit(dictionary, replacing: model.dictionary, set: { model.dictionary = $0 }, save: { model.saveDictionary() }) {
            state.saveError = failure // arkusz zostaje otwarty ze szkicem; ponowne Save próbuje jeszcze raz
            return
        }
        state.closeEditor()
        state.error = nil
        state.notice = nil
    }

    private func delete() {
        guard let id = state.draft?.id else { return }
        var dictionary = model.dictionary
        dictionary.remove(id)
        if let failure = DictionaryEdit.commit(dictionary, replacing: model.dictionary, set: { model.dictionary = $0 }, save: { model.saveDictionary() }) {
            state.saveError = failure
            return
        }
        state.closeEditor()
        state.error = nil
        state.notice = nil
    }
}

// MARK: - Raport importu

struct DictionaryImportSheet: View {
    let report: DictionaryImportReport
    let files: [String]
    var onDone: () -> Void

    private var nothingChanged: Bool { report.termsAdded == 0 && report.aliasesAdded == 0 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: nothingChanged ? "minus" : "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.mnAccent)
                            .padding(.top, 3).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nothingChanged ? "Nothing new to import" : "Import finished").font(.system(size: 14, weight: .semibold)).foregroundStyle(.mnText)
                            if !files.isEmpty { Text(files.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.mnText2).lineLimit(1).truncationMode(.middle) }
                        }
                    }
                    Card {
                        HStack(alignment: .top, spacing: 0) {
                            stat(report.termsAdded, "terms added")
                            stat(report.aliasesAdded, "aliases added")
                            stat(report.riskyLeftOff, "risky, left off")
                            stat(report.conflicts.count, "conflicts")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(report.summary)
                    }
                    .padding(.top, 14)
                    if !report.conflicts.isEmpty {
                        SectionHeader("Conflicts") { Text("an alias belongs to one term").font(.system(size: 11)).foregroundStyle(.mnText2) }
                        Card {
                            // Setki konfliktów przy dużym pliku: od kilku wierszy lista przewija się, arkusz nie rośnie bez końca.
                            if report.conflicts.count > 4 { ScrollView { conflictRows }.frame(maxHeight: 190) } else { conflictRows }
                        }
                    }
                    if report.rejected > 0 {
                        Text("\(report.rejected) \(report.rejected == 1 ? "entry was" : "entries were") skipped: text can’t start with # or contain tabs or line breaks.")
                            .font(.system(size: 11)).foregroundStyle(.mnWarn).fixedSize(horizontal: false, vertical: true).padding(.top, 10).padding(.leading, 2)
                    }
                    Text(report.riskyLeftOff > 0
                         ? "Risky aliases are switched off. Turn them on one by one in the list. Terms and aliases you already had were left as they are."
                         : "Terms and aliases you already had were left as they are.")
                        .font(.system(size: 11)).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true).padding(.top, 10).padding(.leading, 2)
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            }
            HStack {
                Spacer()
                Button("Done") { onDone() }.buttonStyle(.pillPrimary).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(.mnLine2).frame(height: 0.5) }
            // Esc zamykał natywny arkusz; w nakładce potrzebny niewidoczny bliźniak (ramka 0×0, żeby nie łapał kliknięć, a skrót działał).
            .background { Button("") { onDone() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) }
        }
        .frame(width: 500)
        .background(.mnCard)
        .tint(.mnAccent)
    }

    private var conflictRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(report.conflicts.enumerated()), id: \.offset) { i, c in
                if i > 0 { RowDivider(inset: 0) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(c.alias)”").font(.system(size: 13, weight: .medium)).foregroundStyle(.mnText)
                    (Text("Kept for ") + Text(c.keptBy).fontWeight(.semibold).foregroundStyle(.mnText) + Text(", skipped for \(c.skippedFor)."))
                        .font(.system(size: 11)).foregroundStyle(.mnText2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.system(size: 26, design: .serif)).monospacedDigit().foregroundStyle(.mnText)
            Text(label).font(.system(size: 11)).foregroundStyle(.mnText2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
