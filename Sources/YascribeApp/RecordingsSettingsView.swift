import AppKit
import YascribeNotes
import YascribeProviders
import SwiftUI

/// Sekcja „Recordings” w Settings (macos.md §11.5, `b-settings.png`): folder ze spotkaniami (przenoszenie
/// z kopią i weryfikacją) i retencja audio. Ustawienia zapisują się od razu, poza Save / Cancel sekcji Archive.
struct RecordingsSection: View {
    @Environment(AppModel.self) private var model

    /// Pozycje „Keep audio”; 0 = Forever tylko w UI (w ustawieniach Forever to osobna flaga).
    private static let options = [7, 14, 30, 90, 0]

    var body: some View {
        SectionHeader("Recordings") {
            if let size = model.recordingsSize {
                Text("\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) on disk")
                    .font(.system(size: 12)).foregroundStyle(.mnText2)
            }
        }
        .task { model.refreshRecordingsSize() }
        Card {
            FormRow(label: "Location", caption: locationCaption.text, isError: locationCaption.isError) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(Self.abbreviated(model.sessionsDirectory.path))
                            .foregroundStyle(.mnText).lineLimit(1).truncationMode(.middle)
                            .help(model.sessionsDirectory.path)
                        Spacer(minLength: 8)
                        Button("Change…") { chooseFolder() }
                            .buttonStyle(.pillSmall)
                            .disabled(model.recordingsMoveBlocked != nil)
                            .help(model.recordingsMoveBlocked ?? "Move all meetings to another folder")
                        Button("Show in Finder") { showInFinder() }.buttonStyle(.pillSmall)
                    }
                    if let p = model.recordingsMove {
                        StateLabel(.progress(p.fraction), Self.progressText(p))
                    } else if let r = model.recordingsMoveResult {
                        // Pełny powód jest w podpisie (StateLabel ma jedną linię).
                        StateLabel(r.moved ? .ok : .bad, r.moved ? "Meetings moved" : "Not moved")
                    }
                }
            }
            RowDivider()
            FormRow(label: "Keep audio",
                    caption: "Only audio is deleted. Transcripts, notes and My notes stay. Audio is kept until its transcription has finished.") {
                FieldMenu(label: "Keep audio", value: Self.label(model.settings.audioRetentionDays ?? 0), width: 140) {
                    Picker("Keep audio", selection: Binding(
                        get: { model.settings.audioRetentionDays ?? 0 },
                        set: { model.requestKeepAudio(days: $0 == 0 ? nil : $0) })) {
                        ForEach(Self.options, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        }
        // R1: skrócenie, które kasuje audio, wymaga potwierdzenia; Cancel zostawia ustawienie bez zmian.
        .confirmationDialog(keepAudioQuestion, isPresented: Binding(
            get: { model.pendingKeepAudio != nil }, set: { if !$0 { model.pendingKeepAudio = nil } }), titleVisibility: .visible) {
            // Dni łapiemy przy budowie dialogu: zamknięcie (binding → nil) może przyjść przed akcją przycisku.
            if let days = model.pendingKeepAudio?.days {
                Button("Delete Audio", role: .destructive) { model.setKeepAudio(days: days) }
            }
            Button("Cancel", role: .cancel) { model.pendingKeepAudio = nil }
        } message: {
            Text("Transcripts, notes and My notes stay. Deleted audio can't be played or transcribed again.")
        }
    }

    private var keepAudioQuestion: String {
        guard let p = model.pendingKeepAudio else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: p.bytes, countStyle: .file)
        return "Delete \(size) of audio from \(p.meetings) \(p.meetings == 1 ? "meeting" : "meetings") older than \(p.days) days?"
    }

    /// Błąd przenoszenia (czerwony) albo, gdy zmiana jest zablokowana, powód (`text2`).
    private var locationCaption: (text: String?, isError: Bool) {
        if let detail = model.recordingsMoveResult?.detail { return (detail, true) }
        if model.recordingsMove == nil, let reason = model.recordingsMoveBlocked { return (reason, false) }
        return (nil, false)
    }

    private static func label(_ days: Int) -> String { days == 0 ? "Forever" : "\(days) days" }

    private static func progressText(_ p: RecordingsMove.Progress) -> String {
        switch p.phase {
        case .copying: "Copying \(min(p.done + 1, p.total)) of \(p.total)…"
        case .verifying: "Checking the copy…"
        case .removing: "Removing from the old folder…"
        }
    }

    private static func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        panel.message = "Choose an empty folder. All meetings will be copied there, checked, and only then removed from the current folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.changeRecordingsLocation(to: url)
    }

    private func showInFinder() {
        let dir = model.sessionsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
