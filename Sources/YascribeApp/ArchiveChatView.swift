import SwiftUI

struct ArchiveChatView: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: AskBarState

    private func newChat() {
        model.archive.newChat()
        state.text = ""
        state.showingSource = false
        state.pane = .chat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    state.showingSource = false
                    state.pane = .meetings
                    model.selectedSessionID = nil
                } label: { Label("Back to meetings", systemImage: "arrow.left") }
                    .buttonStyle(.pillSmall)
                Text(state.pane == .history ? "Past chats" : (model.archive.currentChatTitle.isEmpty ? "New chat" : model.archive.currentChatTitle))
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button("New chat", action: newChat).buttonStyle(.pillSmall)
            }
            if state.pane == .history {
                history
            } else {
                conversation
            }
        }
        .padding(.horizontal, 22).padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var history: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.archive.savedChats.isEmpty {
                    Text("No past chats yet.").foregroundStyle(.mnText2).padding(.vertical, 16)
                }
                ForEach(model.archive.savedChats) { chat in
                    Button {
                        model.archive.openChat(chat.id)
                        if model.archive.currentChatID == chat.id {
                            state.text = ""
                            state.pane = .chat
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chat.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Text(chat.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11)).foregroundStyle(.mnText2)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    RowDivider(inset: 0)
                }
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.archive.turns.isEmpty {
                        Text("Ask a question about your meetings.").foregroundStyle(.mnText2).padding(.vertical, 16)
                    }
                    ForEach(model.archive.turns) { turn in
                        turnView(turn).id(turn.id)
                    }
                    if let consent = model.archive.consent {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Index \(consent.meetings) meetings with \(consent.provider) · \(consent.model)?").fontWeight(.semibold)
                            Text("Their transcripts and notes are sent to \(consent.provider) to build a search index stored on this Mac.")
                            HStack {
                                Button("Cancel") { model.archive.cancel() }.buttonStyle(.pillSmall)
                                Button("Index Meetings") { model.archive.confirmIndexing() }.buttonStyle(.pillPrimary)
                            }
                        }.font(.system(size: 12))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.archive.turns) { _, turns in
                if let id = turns.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private func turnView(_ turn: ArchiveModel.Turn) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(turn.question).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
            switch turn.state {
            case .working(let message):
                HStack { ProgressView().controlSize(.small); Text(message); Button("Cancel") { model.archive.cancel() }.buttonStyle(.pillSmall) }
            case .answered(let answer):
                Text(answer.text).textSelection(.enabled)
                ForEach(Array(answer.sources.enumerated()), id: \.offset) { index, source in
                    if let item = model.sessions.first(where: { $0.id == source.sessionID }) {
                        Button {
                            state.showingSource = true
                            model.selectedSessionID = item.id
                        } label: {
                            Text("[\(index + 1)] \(item.title) · \(item.startedAt.formatted(date: .abbreviated, time: .omitted))" + (source.start.map { " · " + MeetingDetailView.time($0) } ?? ""))
                                .underline().frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    } else {
                        Text("[\(index + 1)] Meeting unavailable").foregroundStyle(.mnText2)
                    }
                }
            case .noAnswer(let message): Text(message).foregroundStyle(.mnText2)
            case .failed(let message, let opensSettings):
                WarnLabel(message)
                if opensSettings { LinkButton("Open Settings") { model.section = .settings } }
            case .cancelled: Text("Cancelled").foregroundStyle(.mnText2)
            }
        }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }
}
