import MeetNotesProviders
import SwiftUI

final class ModelPickerState: ObservableObject {
    @Published var showing = false
    @Published var query = ""
}

/// Przycisk z nazwą modelu → popover z wyszukiwarką i listą dla roli (spec 1.5 §5.4).
/// Licznik pokazuje to, co widać; model spoza listy (np. wpisany z ręki) wybiera się wierszem „Use …".
struct ModelPicker: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = ModelPickerState()
    let providerID: UUID
    let role: Role
    @Binding var selection: String

    private var all: [ModelInfo] { model.models(provider: providerID, role: role) }
    private var visible: [ModelInfo] { ModelCatalog.visible(all, role: role, query: state.query) }
    private var kindName: String {
        switch role {
        case .asr: "transcription"
        case .embedding: "embedding"
        case .correction, .summary: "text"
        }
    }
    /// Wpisany identyfikator, którego nie ma na liście.
    private var typed: String? {
        let q = state.query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || all.contains { $0.id == q } ? nil : q
    }

    var body: some View {
        Button {
            state.query = ""
            state.showing = true
            Task { await model.loadModels(provider: providerID, role: role) }
        } label: {
            // `ModelField` (macos.md §11.4): popup „Dostawca · id ⌄”, dostawca w `text2`.
            HStack(spacing: 6) {
                if let name = model.providers.providers.first(where: { $0.id == providerID })?.roleLabel {
                    Text("\(name)  ·").foregroundStyle(.mnText2).fixedSize()
                }
                Text(selection.isEmpty ? "Choose model" : selection).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(selection.isEmpty ? .mnText2 : .mnText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.mnText2)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $state.showing, arrowEdge: .bottom) { content }
        .help("Search and choose a model")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search models", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading) // popover dziedziczy wyrównanie do prawej z formularza (odbiór T13, 6a)
                .onSubmit { if let typed { pick(typed) } }
            if model.isLoadingModels(provider: providerID, role: role) && all.isEmpty {
                ProgressView("Loading models…")
            } else {
                Text("\(visible.count) of \(all.count) \(kindName) models").font(.caption).foregroundStyle(.secondary)
            }
            List(visible, id: \.id) { m in
                Button { pick(m.id) } label: {
                    HStack {
                        // Jedna linia, skracanie w środku (długie id typu `nvidia/nemotron-…-0.6b` zawijały się), pełne id w podpowiedzi.
                        Text(m.id).lineLimit(1).truncationMode(.middle).help(m.id)
                        Spacer()
                        if m.id == selection { Image(systemName: "checkmark") }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 200)
            if let typed { Button("Use “\(typed)”") { pick(typed) } }
        }
        .padding(12)
        .frame(width: 520, height: 380)
    }

    private func pick(_ id: String) {
        selection = id
        state.showing = false
    }
}
