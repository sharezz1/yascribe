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
/// Układ jak Presets (macos.md §11.5): lista 196 pt + edytor, pasek na dole.
struct TemplatesView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state: TemplateEditorState

    init(state: TemplateEditorState = TemplateEditorState()) { _state = StateObject(wrappedValue: state) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        PageTitle("Templates")
                        Spacer()
                        Button { state.startNew() } label: { Label("New template", systemImage: "plus") }
                            .buttonStyle(.pill)
                            .disabled(state.isDirty)
                            .help("New template")
                    }
                    .padding(.bottom, 18)
                    HStack(alignment: .top, spacing: 18) {
                        list.frame(width: 196)
                        Group {
                            if state.draft != nil {
                                TemplateForm(state: state)
                            } else {
                                ContentUnavailableView("Choose a template", systemImage: "doc.text",
                                                       description: Text("A template shapes the notes: the structure and what to focus on."))
                                    .padding(.top, 40)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .contentColumn(700)
            }
            if let d = state.draft {
                EditorFooter(dirty: state.isDirty, error: state.error) {
                    if !state.isNew {
                        if !d.builtin { Button("Delete", role: .destructive) { delete(d) }.buttonStyle(.pill) }
                        Button("Duplicate") { duplicate(d) }.buttonStyle(.pill)
                    }
                    if !state.isBuiltin {
                        Button("Cancel") { state.cancel() }.buttonStyle(.pill).disabled(!state.isDirty)
                        Button("Save") { save() }.buttonStyle(.pillPrimary).keyboardShortcut("s", modifiers: .command).disabled(!state.isDirty)
                    }
                }
            }
        }
        .contentBackground()
        .navigationTitle("Templates")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            if state.isNew, let d = state.draft {
                PresetRow(title: d.name.isEmpty ? "New template" : d.name, subtitle: "unsaved", selected: true, dim: true)
            }
            ForEach(model.notes.templates.all()) { t in
                Button {
                    guard !state.isDirty else { return }
                    state.select(t)
                } label: {
                    PresetRow(title: t.name, subtitle: t.builtin ? "Built-in" : "Custom", selected: state.draft?.id == t.id)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(state.draft?.id == t.id ? .isSelected : [])
            }
            if state.isDirty {
                Text("Save or cancel your changes to switch templates.")
                    .font(.system(size: 11)).foregroundStyle(.mnText2).padding(.horizontal, 10).padding(.top, 8)
            }
        }
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

struct TemplateForm: View {
    @ObservedObject var state: TemplateEditorState

    private var draft: Binding<Template> {
        Binding(get: { state.draft ?? Template(name: "", instructions: "") }, set: { state.draft = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorNameField(placeholder: "Name", text: draft.name, readOnly: state.isBuiltin)
            SectionHeader("Instructions")
            Card {
                FormRow(label: "For the model",
                        caption: state.isBuiltin
                            ? "Built-in templates can't be edited. Duplicate it to make your own."
                            : "Describe the structure of the notes, e.g. “A summary, then decisions, then action items with owners.”") {
                    EditorPromptField(text: draft.instructions, minHeight: 220).disabled(state.isBuiltin)
                }
            }
        }
    }
}
