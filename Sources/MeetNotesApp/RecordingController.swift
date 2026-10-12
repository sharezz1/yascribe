import AppKit
import Foundation
import MeetNotesRecording
import Observation
import SwiftUI

/// Stan trwającego nagrania dla interfejsu i pływającego okna.
@MainActor
@Observable
final class RecordingController {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastEndReason: EndReason?
    /// Preset zamrożony przy starcie — pokazywany przez całe nagranie (ChatGPT #2).
    private(set) var presetLabel = ""
    /// Katalog trwającej sesji — lista sesji go pomija (Hermes 4.5: nie „Recovered").
    private(set) var directory: URL?
    private var recorder: SessionRecorder?
    private var timer: Timer?
    private var started = Date()
    private var panel: NSPanel?

    /// Drugi start przy żywym rejestratorze wyciekłby pierwszy (check S15 #1).
    enum StartError: Error { case alreadyRecording }

    func start(directory: URL, presetLabel: String, onEnded: @escaping @MainActor (EndReason) -> Void) throws {
        guard recorder == nil else { throw StartError.alreadyRecording }
        let r = SessionRecorder(directory: directory,
                                sources: [SystemTapSource(), RawMicrophoneSource()]) // bez VP: ściszałby Teams przez całe nagranie (S5, spec rdzenia §2 korekta 2026-09-29)
        r.onEnded = { [weak r] reason in
            Task { @MainActor in
                // Tylko bieżący rejestrator kończy stan — spóźnione zakończenie innego go nie zeruje.
                guard let r, self.recorder === r else { return }
                self.finish(reason)
                onEnded(reason)
            }
        }
        try r.start()
        recorder = r
        self.directory = directory
        self.presetLabel = presetLabel
        isRecording = r.endReason == nil
        started = Date()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.elapsed = Date().timeIntervalSince(self.started)
                self.recorder?.tick()
            }
        }
    }

    func stop() { recorder?.stop(reason: .button) }

    private func finish(_ reason: EndReason) {
        isRecording = false
        lastEndReason = reason
        timer?.invalidate()
        timer = nil
        recorder = nil
        directory = nil
    }

    /// 🔀 Odstępstwa 1 i 2 (`docs/design/macos.md` §10): okno zostaje na wierzchu, gdy aktywny
    /// jest Teams, i klik w nie nie odbiera fokusu spotkaniu.
    func showPanel(model: AppModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Recording"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: RecordingPanelView(model: model))
        p.center()
        p.orderFrontRegardless()
        panel = p
    }
}

struct RecordingPanelView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rec = model.recording
        HStack(spacing: 10) {
            if rec.isRecording {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                // Stan nigdy samym kolorem: napis i licznik (macos.md §6.1).
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recording \(Self.clock(rec.elapsed))").monospacedDigit()
                    Text(rec.presetLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop") { rec.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                // 🔴 Preset z językiem widoczny i wybierany przed startem (W§2, W§6).
                PresetMenu()
                Spacer()
                Button("Record") { model.startRecording() }
            }
        }
        .padding(12)
        .environment(model)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
