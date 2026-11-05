import SwiftUI
import YascribeNotes

final class AskBarState: ObservableObject {
    enum Pane { case meetings, chat, history }
    @Published var text = ""
    @Published var pane: Pane = .meetings
    @Published var showingSource = false
    @Published var height: CGFloat = 0
    var expanded: Bool {
        get { pane == .chat }
        set { pane = newValue ? .chat : .meetings }
    }
}

struct AskBar: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: AskBarState
    @FocusState private var focused: Bool
    init(state: AskBarState = AskBarState()) { self.state = state }

    private var prompt: String { "Ask about " + (state.pane == .meetings ? model.archive.draftScopeLabel : model.archive.currentScopeLabel) }

    private var question: String { state.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var questionTooLong: Bool { question.count > ArchiveAsk.maxQuestionChars }
    private var canSend: Bool {
        !question.isEmpty && !questionTooLong && !model.archive.isBusy && model.archive.consent == nil
    }
    private func submit() {
        guard canSend else { return }
        let text = question
        if state.pane == .meetings, !model.archive.turns.isEmpty { model.archive.newChat() }
        state.text = ""
        state.showingSource = false
        state.pane = .chat
        model.archive.ask(text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(.mnText2)
                TextField(prompt, text: $state.text)
                    .textFieldStyle(.plain).focused($focused).onSubmit(submit)
                    .accessibilityLabel(prompt)
                Button {
                    model.archive.loadChats()
                    state.showingSource = false
                    state.pane = .history
                } label: { Label("Past chats", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(.pillSmall)
                if model.archive.isBusy || model.archive.consent != nil {
                    Button("Cancel") { model.archive.cancel() }.buttonStyle(.pillSmall)
                } else {
                    Button(action: submit) { Image(systemName: "arrow.up") }
                        .buttonStyle(.pillSmall).disabled(!canSend).accessibilityLabel("Send question")
                }
            }
            .padding(10)
            .background(.mnField, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.mnLine, lineWidth: 1))
            if questionTooLong { WarnLabel("Questions can be up to 1 000 characters.").font(.system(size: 11)) }
            if let error = model.archive.persistenceError {
                WarnLabel(error).font(.system(size: 11))
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}
