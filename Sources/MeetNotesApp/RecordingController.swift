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
    private var recorder: SessionRecorder?
    private var timer: Timer?
    private var started = Date()
    private var panel: NSPanel?

    func start(directory: URL, onEnded: @escaping @MainActor (EndReason) -> Void) throws {
        let r = SessionRecorder(directory: directory,
                                sources: [SystemTapSource(), RawMicrophoneSource()]) // bez VP: ściszałby Teams przez całe nagranie (S5, spec rdzenia §2 korekta 2026-09-29)
        r.onEnded = { reason in
            Task { @MainActor in
                self.finish(reason)
                onEnded(reason)
            }
        }
        try r.start()
        recorder = r
        isRecording = r.endReason == nil
        started = Date()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.elapsed = Date().timeIntervalSince(self.started)
                self.recorder?.tick()
            }
        }
        if isRecording { showPanel() }
    }

    func stop() { recorder?.stop(reason: .button) }

    private func finish(_ reason: EndReason) {
        isRecording = false
        lastEndReason = reason
        timer?.invalidate()
        timer = nil
        recorder = nil
        panel?.close()
        panel = nil
    }

    /// 🔀 Odstępstwa 1 i 2 z `docs/design/macos.md` §10: pływające okno zostaje na
    /// wierzchu, gdy aktywny jest Teams, i klik w nie nie odbiera fokusu spotkaniu.
    private func showPanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
                        styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Recording"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: RecordingPanelView(controller: self))
        p.center()
        p.orderFrontRegardless()
        panel = p
    }
}

struct RecordingPanelView: View {
    let controller: RecordingController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .accessibilityHidden(true)
            // Stan nigdy samym kolorem: napis i licznik (macos.md §6.1).
            Text("Recording \(Self.clock(controller.elapsed))")
                .monospacedDigit()
            Spacer()
            Button("Stop") { controller.stop() }
                .keyboardShortcut(".", modifiers: .command)
        }
        .padding(12)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
