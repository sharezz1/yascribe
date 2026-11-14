import SwiftUI
import YascribeDictation
import YascribeProviders

final class DictationSettingsUI: ObservableObject {
    /// Powód odrzucenia ostatniego gestu w polu skrótu.
    @Published var hotkeyMessage: String?
}

/// Karta „Dictation" edytuje wspólny szkic ustawień.
struct DictationSettingsSection: View {
    @Environment(AppModel.self) private var model
    @StateObject private var ui = DictationSettingsUI()
    @Binding var settings: DictationSettings

    private var s: DictationSettings { settings }
    private var asrProviders: [Provider] { RoleProviders.choices(model.providers.providers, role: .asr, current: s.asr?.providerID) }
    private var correctionProviders: [Provider] { RoleProviders.choices(model.providers.providers, role: .correction, current: s.correction?.model?.providerID) }
    /// Język, z którym dyktowanie naprawdę ruszy: jawny, inaczej język aktywnego presetu (Auto nie przechodzi).
    private var effectiveLanguage: LanguageCode? { s.language ?? model.activePreset?.language }

    var body: some View {
        SectionHeader("Dictation")
        Card {
            shortcutRow
            RowDivider()
            FormRow(label: "Mode") {
                Picker("Mode", selection: Binding(get: { s.triggerModeOrDefault }, set: { m in update { $0.triggerMode = m } })) {
                    Text("Hold to talk").tag(DictationTriggerMode.hold)
                    Text("Press to toggle").tag(DictationTriggerMode.toggle)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            RowDivider()
            modelRows
            RowDivider()
            languageRow
            RowDivider()
            FormRow(label: "Correct dictation", caption: "Cleans up the text with a model before it is inserted. If it fails, the original text is used.") {
                Toggle("Correct dictation", isOn: Binding(get: { s.correctionEnabled }, set: setCorrection)).labelsHidden().toggleStyle(.switch)
            }
            if s.correctionEnabled { correctionRows }
            RowDivider()
            FormRow(label: "Floating button", caption: "Shows a small button on the main display to start and stop dictation.") {
                Toggle("Show floating button", isOn: Binding(get: { s.showLauncherOrDefault }, set: { on in update { $0.showLauncher = on } }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: Zapis

    private func update(_ change: (inout DictationSettings) -> Void) {
        var next = s
        change(&next)
        settings = next
    }

    // MARK: Skrót

    private var shortcutRow: some View {
        FormRow(label: "Shortcut", caption: ui.hotkeyMessage ?? (s.hotkeyOrDefault == .fn ? DictationPresentation.fnHint : nil),
                isError: ui.hotkeyMessage != nil) {
            HotkeyRecorder(hotkey: s.hotkeyOrDefault, message: $ui.hotkeyMessage,
                           onCapturing: { model.dictation.setCapturingHotkey($0) }) { h in update { $0.hotkey = h } }
                .frame(width: 180, height: 28)
        }
    }

    // MARK: Model

    @ViewBuilder private var modelRows: some View {
        let showProvider = asrProviders.count > 1 || s.asr == nil
        if showProvider {
            FormRow(label: "Provider") {
                FieldMenu(label: "Provider", value: asrProviders.first { $0.id == s.asr?.providerID }?.roleLabel ?? "Choose…", width: 180) {
                    Picker("Provider", selection: Binding(get: { s.asr?.providerID }, set: { id in
                        guard let id, id != s.asr?.providerID else { return }
                        update { $0.asr = RoleAssignment(providerID: id, model: LocalASRModels.modelWhenSelecting(model.provider(id))) }
                    })) {
                        ForEach(asrProviders) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }
            if s.asr != nil { RowDivider() }
        }
        if let a = s.asr {
            FormRow(label: "Model") {
                ModelPicker(providerID: a.providerID, role: .asr, selection: Binding(get: { s.asr?.model ?? "" }, set: setASRModel))
            }
            if let p = model.provider(a.providerID) {
                if p.api == .fluidAudio {
                    if let support = model.localASR(a.model) {
                        OnThisMacRoleRow(support: support)
                    } else {
                        UnknownOnDeviceModelRow { setASRModel(LocalASRModels.parakeetV3) }
                    }
                } else {
                    probeRow(a)
                }
            }
        }
    }

    private func setASRModel(_ id: String) {
        guard var a = s.asr, a.model != id else { return }
        a.model = id
        update { $0.asr = a }
        probe(a)
    }

    /// Sonda potrzebuje języka: jawnego albo z aktywnego presetu; bez żadnego nic nie wysyłamy.
    private func probe(_ a: RoleAssignment) {
        guard !a.model.isEmpty, let language = effectiveLanguage, model.provider(a.providerID)?.api != .fluidAudio else { return }
        Task { await model.probe(providerID: a.providerID, model: a.model, role: .asr, language: language) }
    }

    private func probeRow(_ a: RoleAssignment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ProbeBadges(result: model.probeCache.result(provider: a.providerID, model: a.model, role: .asr, language: effectiveLanguage))
            Spacer(minLength: 0)
            Button("Test") { probe(a) }
                .buttonStyle(.pillSmall)
                .disabled(a.model.isEmpty || effectiveLanguage == nil)
                .help("Sends a short test request to check this model works for transcription")
        }
        .padding(.leading, 158).padding(.trailing, 16).padding(.bottom, 10)
    }

    // MARK: Język

    private var languageRow: some View {
        let missing = s.language == nil && model.activePreset?.language == nil
        let caption: String? = missing
            ? "Choose a language: the active preset has none (Auto), and dictation needs an explicit one."
            : (s.language == nil ? "Uses the language of the active preset." : nil)
        return FormRow(label: "Language", caption: caption, isError: missing) {
            FieldMenu(label: "Language", value: s.language.map { $0.englishName } ?? "Same as active preset", width: 180) {
                Picker("Language", selection: Binding(get: { s.language }, set: { l in update { $0.language = l } })) {
                    Text("Same as active preset").tag(LanguageCode?.none)
                    ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
        }
    }

    // MARK: Korekta

    private func setCorrection(_ on: Bool) {
        update { d in
            var c = d.correction ?? DictationCorrectionSettings()
            c.enabled = on
            if on, c.model == nil, let p = correctionProviders.first { c.model = RoleAssignment(providerID: p.id, model: "") }
            d.correction = c
        }
    }

    @ViewBuilder private var correctionRows: some View {
        let current = s.correction?.model
        if correctionProviders.count > 1 || current == nil {
            RowDivider()
            FormRow(label: "Correction provider") {
                FieldMenu(label: "Correction provider", value: correctionProviders.first { $0.id == current?.providerID }?.roleLabel ?? "Choose…", width: 180) {
                    Picker("Correction provider", selection: Binding(get: { current?.providerID }, set: { id in
                        guard let id, id != current?.providerID else { return }
                        update { $0.correction = DictationCorrectionSettings(enabled: true, model: RoleAssignment(providerID: id, model: "")) }
                    })) {
                        ForEach(correctionProviders) { p in Text(p.roleLabel).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }
        }
        if let a = current {
            RowDivider()
            FormRow(label: "Correction model",
                    caption: a.model.isEmpty ? "Choose a model, or the original text is used." : nil, isError: a.model.isEmpty) {
                ModelPicker(providerID: a.providerID, role: .correction, selection: Binding(get: { s.correction?.model?.model ?? "" }, set: { id in
                    update { d in
                        var c = d.correction ?? DictationCorrectionSettings(enabled: true)
                        c.model?.model = id
                        d.correction = c
                    }
                }))
            }
        }
    }
}
