import MeetNotesNotes
import MeetNotesProviders
import SwiftUI

/// Stan popovera chipa modelu (bez `@State`: CLT nie ma SwiftUIMacros).
final class MeetingModelChipState: ObservableObject {
    @Published var showing = false
    @Published var providerID: UUID?
    @Published var model = ""
    @Published var thinking: Bool?
}

/// „Model · <id> ⌄" w pasku Summary i obok „Improve transcript": model tylko dla tego nagrania (faza 2.0.1).
/// Zmiana zapisuje się w `meta.json` od razu, gdy dostawca i model są wybrane; działa od następnego przebiegu.
struct MeetingModelChip: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = MeetingModelChipState()
    let role: Role
    let item: SessionItem
    /// Tylko migawki: popover rysowany w miejscu (ImageRenderer/NSHostingView nie łapie okna popovera).
    var inlinePopover = false
    /// Tryb „sterowany z zewnątrz" (pozycja w `MoreMenu`): bez chipa, sam popover otwierany flagą; widok kładzie się w `.background` `⋯`.
    var presented: Binding<Bool>? = nil

    static func assignment(_ role: Role, item: SessionItem, model: AppModel) -> RoleAssignment? {
        role == .summary ? model.notes.summaryChoice(for: item)?.assignment : model.notes.correctionAssignment(for: item)
    }
    static func override(_ role: Role, item: SessionItem, model: AppModel) -> RoleOverride? {
        model.notes.overrides(for: item).usable(role, knownProviders: model.notes.knownProviderIDs())
    }
    static func stale(_ role: Role, item: SessionItem, model: AppModel) -> Bool {
        model.notes.overrides(for: item).isStale(role, knownProviders: model.notes.knownProviderIDs())
    }
    /// Etykieta pozycji `⋯`: „Correction model: V4.1 Flash · changed…" — czytelna nazwa, pełne `id` zostaje w popoverze.
    static func menuTitle(_ role: Role, item: SessionItem, model: AppModel) -> String {
        let name = assignment(role, item: item, model: model).map { model.modelDisplayName($0.model) } ?? "none"
        let mark = override(role, item: item, model: model) != nil ? " · changed" : stale(role, item: item, model: model) ? " · unavailable" : ""
        return "\(role == .summary ? "Summary" : "Correction") model: \(name)\(mark)…"
    }

    private var assignment: RoleAssignment? { Self.assignment(role, item: item, model: model) }
    private var presetModel: String? {
        (role == .summary ? model.notes.presetSummaryChoice(for: item)?.assignment : model.notes.presetCorrection(for: item))?.model
    }
    private var override: RoleOverride? { Self.override(role, item: item, model: model) }
    /// Wybór zapisany, ale dostawca zniknął: chip pokazuje to i nadal pozwala wrócić do presetu.
    private var stale: Bool { Self.stale(role, item: item, model: model) }
    /// Popover otwarty: własna flaga chipa albo przekazana z zewnątrz.
    private var isShown: Binding<Bool> {
        Binding(get: { presented?.wrappedValue ?? state.showing },
                set: { if let presented { presented.wrappedValue = $0 } else { state.showing = $0 } })
    }
    private func provider(_ id: UUID?) -> Provider? { model.providers.providers.first { $0.id == id } }
    private var title: String { role == .summary ? "summary" : "correction" }

    var body: some View {
        if inlinePopover {
            content.onAppear { open() }
        } else if let presented {
            Color.clear
                .popover(isPresented: presented, arrowEdge: .bottom) { content }
                .onChange(of: presented.wrappedValue) { _, on in if on { prefill() } }
        } else {
            chip
        }
    }

    private var chip: some View {
        Button { open() } label: {
            HStack(spacing: 5) {
                if provider(assignment?.providerID)?.isLocal == true {
                    Image(systemName: "cpu").font(.system(size: 10)).accessibilityHidden(true)
                }
                Text(assignment?.model ?? "Choose model").lineLimit(1).truncationMode(.middle)
                if override != nil { Text("· changed").fixedSize() } else if stale { Text("· unavailable").fixedSize() }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11)).foregroundStyle(.mnText2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $state.showing, arrowEdge: .bottom) { content }
        .help(override != nil ? "Chosen for this meeting. The preset uses \(presetModel ?? "no model")."
              : "Choose another \(title) model for this meeting")
        .accessibilityLabel("Model for \(title)")
        .accessibilityValue(assignment?.model ?? "None")
    }

    private func open() {
        prefill()
        state.showing = true
    }

    private func prefill() {
        let o = override
        state.providerID = o?.providerID ?? assignment?.providerID
        state.model = o?.model ?? assignment?.model ?? ""
        state.thinking = o?.thinking
    }

    private var providers: [Provider] {
        RoleProviders.choices(model.providers.providers, role: role, current: state.providerID)
    }
    private var thinkingOn: Binding<Bool> {
        Binding(get: { state.thinking ?? model.settings.summaryThinkingEnabled },
                set: { state.thinking = $0; save() })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model for this meeting's \(title)").font(.system(size: 13, weight: .medium))
            if override != nil || stale {
                Button("Use preset (\(presetModel ?? "none"))") {
                    model.notes.setOverride(role, nil, item: item)
                    isShown.wrappedValue = false
                }
                .buttonStyle(.pillSmall)
            }
            FieldMenu(label: "Provider", value: provider(state.providerID)?.roleLabel ?? "None", width: 280) {
                Picker("Provider", selection: Binding(get: { state.providerID }, set: { id in
                    guard id != state.providerID else { return }
                    state.providerID = id
                    state.model = "" // model innego dostawcy nie pasuje; zapis dopiero po wyborze nowego
                })) {
                    ForEach(providers) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if let pid = state.providerID {
                ModelPicker(providerID: pid, role: role, selection: Binding(get: { state.model }, set: { state.model = $0; save() }))
                    .frame(width: 280)
                if provider(pid)?.isLocal == true {
                    OnThisMacTag()
                } else if role == .summary {
                    Toggle("Thinking", isOn: thinkingOn).toggleStyle(.switch).controlSize(.small)
                        .help("Let the model think before it writes the notes")
                }
            }
            Text("Applies to the next run. The preset stays as it is.").font(.subheadline).foregroundStyle(.mnText2)
        }
        .padding(14)
        .frame(width: 308)
    }

    /// Zapis tylko przy pełnym wyborze; „Thinking" dotyczy podsumowania i dostawcy spoza tego komputera.
    private func save() {
        guard let pid = state.providerID, !state.model.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let thinking = role == .summary && provider(pid)?.isLocal != true ? state.thinking : nil
        model.notes.setOverride(role, RoleOverride(providerID: pid, model: state.model, thinking: thinking), item: item)
    }
}
