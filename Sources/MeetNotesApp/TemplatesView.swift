import MeetNotesNotes
import SwiftUI

final class TemplateEditorState: ObservableObject {
    @Published var draft: Template?
    /// Zapisana wersja; `nil` = nowy, niezapisany.
    @Published var original: Template?
    @Published var error: String?

    var isNew: Bool { draft != nil && original == nil }
    var isDirty: Bool { draft != nil && draft != original }
    var isBuiltin: Bool { draft?.builtin == true }

    func select(_ t: Template?) { draft = t; original = t; error = nil }
    func startNew() { draft = Template(name: "New template", instructions: ""); original = nil; error = nil }
    func cancel() { draft = original; error = nil }
}

/// Szablony podsumowania (spec 1.5 §5.4): wbudowane tylko do odczytu + „Duplicate"; własne edytowalne z Save/Cancel.
struct TemplatesView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: TemplateEditorState

    init(state: TemplateEditorState = TemplateEditorState()) { _state = StateObject(wrappedValue: state) }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { state.draft?.id }, set: { id in
                    guard !state.isDirty else { return }
                    state.select(model.notes.templates.all().first { $0.id == id })
                })) {
                    if state.isNew, let d = state.draft { Text(d.name.isEmpty ? "New template…" : d.name).tag(d.id) }
                    ForEach(model.notes.templates.all()) { t in
                        HStack {
                            Text(t.name)
                            if t.builtin { Spacer(); Text("Built-in").font(.caption).foregroundStyle(.secondary) }
                        }
                        .tag(t.id)
                    }
                }
                if state.isDirty { Text("Save or cancel your changes to switch templates.").font(.caption).foregroundStyle(.secondary).padding(8) }
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 300, maxHeight: .infinity)
            Group {
                if state.draft != nil {
                    TemplateForm(state: state)
                } else {
                    ContentUnavailableView("Choose a template", systemImage: "doc.text",
                                           description: Text("A template shapes the notes: the structure and what to focus on."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button { state.startNew() } label: { Label("New Template", systemImage: "plus") }
                    .help("New template").disabled(state.isDirty)
            }
        }
        .navigationTitle("Templates")
    }
}

struct TemplateForm: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: TemplateEditorState

    private var draft: Binding<Template> {
        Binding(get: { state.draft ?? Template(name: "", instructions: "") }, set: { state.draft = $0 })
    }

    var body: some View {
        Form {
            TextField("Name", text: draft.name).disabled(state.isBuiltin)
            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions for the model").font(.callout)
                TextEditor(text: draft.instructions).frame(minHeight: 220).font(.body).disabled(state.isBuiltin)
                Text("Describe the structure of the notes, e.g. “A summary, then decisions, then action items with owners.”")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if state.isBuiltin { Text("Built-in templates can't be edited. Duplicate it to make your own.").font(.caption).foregroundStyle(.secondary) }
            if let e = state.error { Text(e).foregroundStyle(.red) }
            HStack {
                if let d = state.draft, !state.isNew {
                    Button("Duplicate") { duplicate(d) }
                    if !d.builtin { Button("Delete", role: .destructive) { delete(d) } }
                }
                Spacer()
                if !state.isBuiltin {
                    Button("Cancel") { state.cancel() }.disabled(!state.isDirty)
                    Button("Save") { save() }.keyboardShortcut("s", modifiers: .command).disabled(!state.isDirty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        guard let d = state.draft else { return }
        var file = model.notes.templates
        do {
            try file.upsert(d)
        } catch TemplateError.nameTaken(let n) {
            state.error = "A template named “\(n)” already exists."
            return
        } catch TemplateError.missingName {
            state.error = "Give the template a name."
            return
        } catch {
            state.error = "\(error)"
            return
        }
        model.notes.templates = file
        state.error = model.saveTemplates()
        if state.error == nil { state.select(file.templates.first { $0.id == d.id }) }
    }

    private func duplicate(_ t: Template) {
        var copy = t.duplicate()
        var n = 2
        let names = Set(model.notes.templates.all().map(\.name))
        while names.contains(copy.name) { copy.name = "\(t.name) copy \(n)"; n += 1 }
        state.draft = copy
        state.original = nil
        state.error = nil
    }

    private func delete(_ t: Template) {
        model.notes.templates.remove(id: t.id)
        state.error = model.saveTemplates()
        if state.error == nil { state.select(nil) }
    }
}
