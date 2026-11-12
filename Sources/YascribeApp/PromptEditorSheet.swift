import SwiftUI
import YascribeNotes

/// Okno edycji własnego polecenia (korekty albo podsumowania): jak okna Presets i Dictionary (`EditorSheet`).
/// Renderowalne samodzielnie; zapis do szkicu Settings (`SettingsDraft.savePromptSheet`), na dysk dopiero Save w Settings.
struct PromptEditorSheet: View {
    let kind: PromptKind
    @ObservedObject var draft: SettingsDraft
    let localModel: Bool

    private var count: Int { draft.promptSheetText.trimmingCharacters(in: .whitespacesAndNewlines).count }
    private var tooLong: Bool { count > kind.maxChars }
    private var title: String { kind == .correction ? "Correction prompt" : "Summary prompt" }
    private var caption: String {
        let what = kind == .correction
            ? "The base instruction for the correction model. The line format, language, filler and dictionary lines are added after it, and the length checks always apply."
            : "The rules the summary model follows. The title line, notes language and the template structure are added after them."
        return what + (localModel ? " Long prompts leave less room for the transcript in a local model's context window." : "")
    }

    var body: some View {
        EditorSheet(title: title, dirty: draft.promptSheetChanged && !tooLong,
                    error: tooLong ? "The prompt is too long: \(count) of \(kind.maxChars) characters." : nil,
                    onCancel: { draft.editingPrompt = nil }, onSave: { draft.savePromptSheet() }, idealHeight: 560,
                    leading: {
                        Button("Reset to default") { draft.promptSheetText = kind.defaultBody }
                            .buttonStyle(.pillSmall).disabled(draft.promptSheetIsDefault)
                    }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(caption).font(.subheadline).foregroundStyle(.mnText2).fixedSize(horizontal: false, vertical: true)
                EditorPromptField(text: $draft.promptSheetText, minHeight: 320)
                Text("\(count) / \(kind.maxChars)").font(.subheadline).foregroundStyle(tooLong ? .mnRec : .mnText2)
            }
            .padding(.top, 8)
        }
    }
}
