import MeetNotesNotes
import SwiftUI

final class TemplateEditorState: ObservableObject {
    @Published var draft: Template?
    /// Zapisana wersja; `nil` = nowy, niezapisany.
    @Published var original: Template?
    @Published var error: String?
    @Published var confirmingDelete = false

    var isNew: Bool { draft != nil && original == nil }
    var isDirty: Bool { draft != nil && draft != original }

    /// Stary szablon z jednym promptem wchodzi do edytora jako jedna sekcja (migracja przy odczycie, bez utraty treści).
    func select(_ t: Template?) {
        let n = t.map { var n = $0; n.sections = n.effectiveSections; return n }
        draft = n; original = n; error = nil
    }
    func startNew() {
        draft = Template(name: "New template", sections: [TemplateSection(title: "", instruction: "")])
        original = nil; error = nil
    }
    func cancel() { draft = original; error = nil }
}

/// Szablony podsumowania (macos.md §11.5, odbiór 2026-10-16 uwaga 2): szablon to lista sekcji; wbudowane edytuje się
/// w miejscu (zapis jako nadpisanie, „Reset to default" je usuwa); własne można skasować po potwierdzeniu.
/// Układ jak Presets: lista 196 pt + edytor, pasek na dole.
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
                            if let d = state.draft {
                                TemplateForm(state: state, meta: meta(d), builtin: model.notes.templates.isBuiltin(id: d.id),
                                             edited: model.notes.templates.isEdited(id: d.id),
                                             onDuplicate: { duplicate(d) }, onReset: { reset(d) })
                            } else {
                                EmptyEditorHint(title: "Choose a template",
                                                text: "A template is a list of sections: the structure of the notes and what to focus on.")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .contentColumn(700)
            }
            if state.draft != nil {
                EditorFooter(dirty: state.isDirty, error: state.error) {
                    Button("Cancel") { state.cancel() }.buttonStyle(.pill).disabled(!state.isDirty)
                    Button("Save") { save() }.buttonStyle(.pillPrimary).keyboardShortcut("s", modifiers: .command).disabled(!state.isDirty)
                }
            }
        }
        .contentBackground()
        .navigationTitle("Templates")
        .confirmationDialog("Delete “\(state.original?.name ?? "this template")”?", isPresented: $state.confirmingDelete) {
            Button("Delete template", role: .destructive) { if let o = state.original { delete(o) } }
        } message: {
            Text("Notes already generated with it keep their text.")
        }
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
                    PresetRow(title: t.name, subtitle: meta(t), selected: state.draft?.id == t.id)
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

    /// „Built-in", „Built-in · edited" albo „Custom" — bez ikon (§11.6).
    private func meta(_ t: Template) -> String {
        let file = model.notes.templates
        guard file.isBuiltin(id: t.id) else { return "Custom" }
        return file.isEdited(id: t.id) ? "Built-in · edited" : "Built-in"
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
        } catch TemplateError.noSections {
            state.error = "Add at least one section with a title or instruction."
            return
        } catch {
            state.error = "\(error)"
            return
        }
        model.notes.templates = file
        state.error = model.saveTemplates()
        if state.error == nil { state.select(file.all().first { $0.id == d.id }) }
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

    /// Wbudowany: usuwa nadpisanie i wraca do domyślnej treści.
    private func reset(_ t: Template) {
        model.notes.templates.reset(id: t.id)
        state.error = model.saveTemplates()
        if state.error == nil { state.select(model.notes.templates.all().first { $0.id == t.id }) }
    }

    private func delete(_ t: Template) {
        do { try model.notes.templates.remove(id: t.id) } catch { state.error = "\(error)"; return }
        state.error = model.saveTemplates()
        if state.error == nil { state.select(nil) }
    }
}

private struct FocusTarget: Hashable {
    let id: UUID
    let title: Bool
}

struct TemplateForm: View {
    @ObservedObject var state: TemplateEditorState
    /// „Built-in · edited" itp. — obok nazwy.
    let meta: String
    let builtin: Bool
    let edited: Bool
    var onDuplicate: () -> Void
    var onReset: () -> Void
    @FocusState private var focus: FocusTarget?

    private var draftName: Binding<String> {
        Binding(get: { state.draft?.name ?? "" }, set: { state.draft?.name = $0 })
    }
    private var about: Binding<String> {
        Binding(get: { state.draft?.about ?? "" }, set: { state.draft?.about = $0.isEmpty ? nil : $0 })
    }
    private var sections: Binding<[TemplateSection]> {
        Binding(get: { state.draft?.sections ?? [] }, set: { state.draft?.sections = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                EditorNameField(placeholder: "Name", text: draftName)
                if !state.isNew {
                    Text(meta).font(.system(size: 12)).foregroundStyle(.mnText2).lineLimit(1).fixedSize()
                    actionsMenu
                }
            }
            SectionHeader("About this meeting type", note: "— optional")
            GrowingField(placeholder: "Describe the kind of meeting and what matters in its notes.", text: about, weight: .regular, color: .mnText)
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(.mnField, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
            SectionHeader("Sections") { Text("in this order").font(.system(size: 11)).foregroundStyle(.mnText2) }
            if !sections.wrappedValue.isEmpty {
                Card {
                    ForEach(sections) { $section in
                        if section.id != sections.wrappedValue.first?.id { RowDivider() }
                        SectionRow(section: $section, focus: $focus,
                                   canMoveUp: section.id != sections.wrappedValue.first?.id,
                                   canMoveDown: section.id != sections.wrappedValue.last?.id,
                                   onMove: { move(section.id, by: $0) }, onDelete: { remove(section.id) })
                            .dropDestination(for: String.self) { items, _ in
                                guard let s = items.first, let from = UUID(uuidString: s) else { return false }
                                moveTo(from, before: section.id)
                                return true
                            }
                    }
                }
            }
            Button { add() } label: { Label("Add section", systemImage: "plus") }
                .buttonStyle(.pillSmall)
                .padding(.top, 10)
                .help("Add a section")
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Duplicate") { onDuplicate() }
            if builtin {
                Button("Reset to default") { onReset() }.disabled(!edited)
            } else {
                Divider()
                Button("Delete template…", role: .destructive) { state.confirmingDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(.mnText2)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    private func add() {
        let s = TemplateSection(title: "", instruction: "")
        sections.wrappedValue.append(s)
        DispatchQueue.main.async { focus = FocusTarget(id: s.id, title: true) }
    }

    private func remove(_ id: UUID) { sections.wrappedValue.removeAll { $0.id == id } }

    private func move(_ id: UUID, by d: Int) {
        var a = sections.wrappedValue
        guard let i = a.firstIndex(where: { $0.id == id }), a.indices.contains(i + d) else { return }
        a.swapAt(i, i + d)
        sections.wrappedValue = a
    }

    /// Przeciąganie: sekcja ląduje w miejscu sekcji, na którą ją upuszczono.
    private func moveTo(_ id: UUID, before target: UUID) {
        var a = sections.wrappedValue
        guard id != target, let from = a.firstIndex(where: { $0.id == id }), let to = a.firstIndex(where: { $0.id == target }) else { return }
        a.insert(a.remove(at: from), at: to)
        sections.wrappedValue = a
    }
}

/// Karta sekcji: uchwyt ⋮⋮ (przeciąganie), tytuł (SF 13 Semibold) i instrukcja (`text2`) rosnące z treścią, ✕.
/// Przesuwanie i usuwanie także z menu kontekstowego i akcji dostępności.
private struct SectionRow: View {
    @Binding var section: TemplateSection
    var focus: FocusState<FocusTarget?>.Binding
    let canMoveUp: Bool
    let canMoveDown: Bool
    var onMove: (Int) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GripHandle()
                .padding(.top, 5)
                .draggable(section.id.uuidString) {
                    Text(section.title.isEmpty ? "Section" : section.title).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8).background(.mnCard)
                }
                .help("Drag to reorder")
                .accessibilityLabel("Reorder section")
            VStack(alignment: .leading, spacing: 2) {
                GrowingField(placeholder: "Section title", text: $section.title, weight: .semibold, color: .mnText)
                    .focused(focus, equals: FocusTarget(id: section.id, title: true))
                GrowingField(placeholder: "What should this section contain?", text: $section.instruction, weight: .regular, color: .mnText2)
                    .focused(focus, equals: FocusTarget(id: section.id, title: false))
            }
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.mnText2)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete section")
            .accessibilityLabel("Delete section")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(focus.wrappedValue?.id == section.id ? Color.mnSelection : .clear)
        .contextMenu {
            Button("Move up") { onMove(-1) }.disabled(!canMoveUp)
            Button("Move down") { onMove(1) }.disabled(!canMoveDown)
            Divider()
            Button("Delete section", role: .destructive) { onDelete() }
        }
        .accessibilityAction(named: "Move up") { if canMoveUp { onMove(-1) } }
        .accessibilityAction(named: "Move down") { if canMoveDown { onMove(1) } }
        .accessibilityAction(named: "Delete section") { onDelete() }
    }
}

/// Uchwyt ⋮⋮: dwie kolumny po trzy kropki (`text3`, to kontrolka — §11.1).
private struct GripHandle: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(.mnText3).frame(width: 2.5, height: 2.5) } }
            }
        }
        .frame(width: 12, height: 16)
        .contentShape(Rectangle())
    }
}

/// Pole tekstowe rosnące z treścią, bez własnego przewijania (koniec toru paska przewijania `TextEditor`):
/// `TextField` z osią pionową i `lineLimit(1...)`.
private struct GrowingField: View {
    let placeholder: String
    @Binding var text: String
    var weight: Font.Weight
    var color: Color
    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...)
            .font(.system(size: 13, weight: weight))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
