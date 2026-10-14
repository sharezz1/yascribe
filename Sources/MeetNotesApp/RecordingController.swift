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
    /// Ostatni poziom (dBFS) każdej ścieżki i nazwa mikrofonu — dla rozwiniętej pigułki.
    private(set) var levels: [String: Double] = [:]
    private(set) var micName = ""
    /// Katalog trwającej sesji — lista sesji go pomija (Hermes 4.5: nie „Recovered").
    private(set) var directory: URL?
    private var recorder: SessionRecorder?
    private var timer: Timer?
    private var started = Date()
    private var panel: NSPanel?
    private var levelTimer: Timer?

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
        micName = CoreAudioDevices.defaultInputName() ?? "Unknown microphone"
        started = Date()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.elapsed = Date().timeIntervalSince(self.started)
                self.recorder?.tick()
            }
        }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in self.levels = self.recorder?.currentLevels() ?? [:] }
        }
    }

    func stop() { recorder?.stop(reason: .button) }

    private func finish(_ reason: EndReason) {
        isRecording = false
        lastEndReason = reason
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        levels = [:]
        recorder = nil
        directory = nil
    }

    func showPanel(model: AppModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        panel = makePanel(model: model)
        panel?.orderFrontRegardless()
    }
}

/// Stan rozwinięcia pigułki; zmiana zmienia rozmiar panelu.
final class PillState: ObservableObject {
    @Published var expanded = false { didSet { onExpandedChange?(expanded) } }
    var onExpandedChange: ((Bool) -> Void)?
}

extension RecordingController {
    /// 🔀 Odstępstwa 1 i 2 (`docs/design/macos.md` §10): okno zostaje na wierzchu, gdy aktywny
    /// jest Teams, i klik w nie nie odbiera fokusu spotkaniu.
    func makePanel(model: AppModel) -> NSPanel {
        let pill = PillState()
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Recording"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pill.onExpandedChange = { [weak p] e in p?.setContentSize(NSSize(width: 360, height: e ? 230 : 64)) }
        p.contentView = NSHostingView(rootView: RecordingPanelView(model: model, pill: pill))
        p.center()
        return p
    }
}

struct RecordingPanelView: View {
    let model: AppModel
    @ObservedObject var pill: PillState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rec = model.recording
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if rec.isRecording {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: !reduceMotion).accessibilityHidden(true)
                    // Stan nigdy samym kolorem: napis i licznik (macos.md §6.1).
                    Text("Recording \(Self.clock(rec.elapsed))").monospacedDigit()
                    Spacer()
                    Button("Stop") { rec.stop() }.keyboardShortcut(".", modifiers: .command)
                    Button { pill.expanded.toggle() } label: { Image(systemName: pill.expanded ? "chevron.down" : "chevron.up") }
                        .buttonStyle(.borderless).help(pill.expanded ? "Collapse" : "Show details")
                        .accessibilityLabel(pill.expanded ? "Collapse details" : "Show details")
                } else {
                    // 🔴 Preset z językiem widoczny i wybierany przed startem (W§2, W§6).
                    PresetMenu()
                    Spacer()
                    Button("Record") { model.startRecording() }
                }
            }
            if rec.isRecording && pill.expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preset: \(rec.presetLabel)").font(.caption).foregroundStyle(.secondary)
                    LevelRow(title: "System audio", db: rec.levels["system"])
                    // Nazwa mikrofonu wyraźnie — żeby od razu było widać, gdy nagrywa nie ten (decyzja użytkownika).
                    LevelRow(title: "Microphone: \(rec.micName)", db: rec.levels["mic_raw"], emphasized: true)
                    HStack {
                        Spacer()
                        Button("Open Note") {
                            if let id = rec.directory?.lastPathComponent { model.openSession(id) }
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
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

/// Poziom ścieżki: nazwa na całą szerokość (nazwa mikrofonu nie może być ucięta — decyzja użytkownika), pod nią pasek
/// i znacznik ✓/— (stan nie tylko kolorem; bez animacji przy Reduce Motion).
struct LevelRow: View {
    let title: String
    let db: Double?
    var emphasized = false

    private var fraction: Double { max(0, min(1, ((db ?? -60) + 60) / 60)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(emphasized ? .callout.weight(.semibold) : .callout).lineLimit(2)
                Spacer(minLength: 8)
                Text((db ?? -160) > -60 ? "✓" : "—").frame(width: 14)
                    .accessibilityLabel((db ?? -160) > -60 ? "Signal present" : "No signal")
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                GeometryReader { g in Capsule().fill(.secondary).frame(width: g.size.width * fraction) }
            }
            .frame(height: 6)
        }
    }
}
