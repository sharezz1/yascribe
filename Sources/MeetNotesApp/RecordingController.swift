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
                // Źródło mikrofonu podąża za domyślnym wejściem systemu (np. AirPods podłączone w trakcie) — nazwa też.
                self.micName = CoreAudioDevices.defaultInputName() ?? self.micName
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

/// Panel bez ramki i tytułu, żeby szkło (§6.2) było jedynym tłem. Bez `canBecomeKey` panel `.borderless`
/// nie dostaje klawiatury (Cmd-. dla Stop, Tab); `.nonactivatingPanel` nadal nie aktywuje aplikacji.
private final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension RecordingController {
    /// 🔀 Odstępstwa 1 i 2 (`docs/design/macos.md` §10): okno zostaje na wierzchu, gdy aktywny
    /// jest Teams, i klik w nie nie odbiera fokusu spotkaniu.
    func makePanel(model: AppModel) -> NSPanel {
        let pill = PillState()
        // ponytail: okno ma stałą szerokość i dwie wysokości; przezroczysty margines wokół kapsuły przechwytuje klik.
        // Dopasowanie do treści (sizingOptions) dopiero, jeśli to będzie przeszkadzać.
        let p = PillPanel(contentRect: NSRect(origin: .zero, size: RecordingPanelView.windowSize(expanded: false)),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Recording" // nie widać, ale czyta go VoiceOver i menu Window
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true // cień kształtu szkła rysuje system; w treści cieni nie ma
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pill.onExpandedChange = { [weak p] e in
            guard let p else { return }
            // Górna krawędź zostaje w miejscu — pigułka rośnie w dół, nie skacze.
            var f = p.frame
            let size = RecordingPanelView.windowSize(expanded: e)
            f.origin.y += f.height - size.height
            f.size = size
            p.setFrame(f, display: true)
        }
        p.contentView = NSHostingView(rootView: RecordingPanelView(model: model, pill: pill))
        p.center()
        return p
    }
}

/// Szkło tylko tutaj (§6.2): Liquid Glass regular od macOS 26, niżej zwykły materiał z cienką obwódką.
private extension View {
    @ViewBuilder func pillGlass<S: InsettableShape>(_ shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape).overlay(shape.strokeBorder(.mnLine, lineWidth: 0.5))
        }
    }
}

/// Stop: kapsuła `card` z obwódką, czerwony kwadrat 10 pt (promień 2) i słowo — stan nie tylko kolorem.
private struct StopButtonStyle: ButtonStyle {
    var fill = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.mnRec).frame(width: 10, height: 10)
            configuration.label.fontWeight(.semibold)
        }
        .font(.system(size: 13))
        .foregroundStyle(.mnRec)
        .padding(.leading, 10).padding(.trailing, 12)
        .frame(maxWidth: fill ? .infinity : nil)
        .frame(height: 32)
        .background(.mnCard, in: Capsule())
        .overlay(Capsule().strokeBorder(.mnLine, lineWidth: 0.5))
        .opacity(configuration.isPressed ? 0.7 : 1)
        .contentShape(Capsule())
    }
}

/// Przycisk-ikona bez tła (⌃ / ⌄): podpis w `.help` i dla VoiceOver.
private struct PillIconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 32
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)).foregroundStyle(.mnText2)
                .frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct RecordingPanelView: View {
    let model: AppModel
    @ObservedObject var pill: PillState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Stała szerokość okna (320 pt panelu + 8 pt na szkło z każdej strony); wysokość zależy od rozwinięcia.
    static func windowSize(expanded: Bool) -> NSSize { NSSize(width: 336, height: expanded ? 224 : 60) }

    var body: some View {
        let rec = model.recording
        Group {
            if rec.isRecording && pill.expanded {
                expandedBody(rec).padding(14).frame(width: 320).pillGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    if rec.isRecording { collapsedBody(rec) } else { idleBody }
                }
                .padding(6).padding(.leading, 8).frame(height: 44).pillGlass(Capsule())
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(model)
    }

    /// Przed startem: preset z językiem widoczny i wybierany tutaj (W§2, W§6) + Record.
    private var idleBody: some View {
        HStack(spacing: 8) {
            PresetMenu().menuStyle(.borderlessButton).menuIndicator(.visible)
            Button { model.startRecording() } label: {
                HStack(spacing: 6) { Circle().fill(.mnRecDot).frame(width: 8, height: 8).accessibilityHidden(true); Text("Record") }
            }
            .buttonStyle(PillButtonStyle(kind: .primary, large: true))
        }
    }

    private func collapsedBody(_ rec: RecordingController) -> some View {
        HStack(spacing: 8) {
            // Stały wskaźnik, bez pulsowania (§7); stan mówi też licznik i słowo Stop.
            Circle().fill(.mnRecDot).frame(width: 8, height: 8).accessibilityHidden(true)
            LevelBars(fraction: Self.fraction(rec), animated: !reduceMotion)
            Text(Self.shortClock(rec.elapsed)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(.mnText)
                .frame(minWidth: 38, alignment: .leading).accessibilityLabel("Recording \(Self.shortClock(rec.elapsed))")
            Button("Stop") { rec.stop() }.buttonStyle(StopButtonStyle()).keyboardShortcut(".", modifiers: .command)
            PillIconButton(systemImage: "chevron.up", label: "Show details") { pill.expanded = true }
        }
    }

    /// Rozwinięta: tylko odczyt (nic tu nie przełącza nagrywania poza Stop).
    private func expandedBody(_ rec: RecordingController) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StateLabel(.live, "Recording")
                Text(Self.shortClock(rec.elapsed)).font(.callout).monospacedDigit().foregroundStyle(.mnText2)
                Spacer(minLength: 0)
                PillIconButton(systemImage: "chevron.down", label: "Hide details", size: 24) { pill.expanded = false }
            }
            Text(rec.presetLabel).font(.callout).foregroundStyle(.mnText2).padding(.leading, 16).padding(.top, 2).padding(.bottom, 14)
            LevelRow(title: "System audio", db: rec.levels["system"], animated: !reduceMotion)
            // Nazwa mikrofonu wyraźnie — żeby od razu było widać, gdy nagrywa nie ten (decyzja użytkownika).
            LevelRow(title: "Microphone: \(rec.micName)", db: rec.levels["mic_raw"], emphasized: true, animated: !reduceMotion)
                .padding(.top, 10)
            HStack(spacing: 8) {
                Button("Open note") {
                    if let id = rec.directory?.lastPathComponent { model.openSession(id) }
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(PillButtonStyle(kind: .secondary, large: true)).frame(maxWidth: .infinity)
                Button("Stop") { rec.stop() }.buttonStyle(StopButtonStyle(fill: true)).keyboardShortcut(".", modifiers: .command)
            }
            .padding(.top, 14)
        }
    }

    /// Głośniejsza ze ścieżek, 0…1 (−60…0 dBFS).
    static func fraction(_ rec: RecordingController) -> Double {
        LevelRow.fraction(db: [rec.levels["system"], rec.levels["mic_raw"]].compactMap { $0 }.max())
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// Licznik pigułki jak na makiecie: mm:ss, godziny dopiero po pełnej godzinie.
    static func shortClock(_ t: TimeInterval) -> String {
        t >= 3600 ? clock(t) : String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// Siedem słupków 3 pt (makieta `.lvl`): wzór wysokości stały, amplituda z poziomu. Bez animacji przy Reduce Motion.
private struct LevelBars: View {
    let fraction: Double
    let animated: Bool
    private static let profile: [CGFloat] = [6, 11, 15, 9, 13, 5, 8]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.profile.indices, id: \.self) { i in
                Capsule().fill(.mnText).frame(width: 3, height: max(3, Self.profile[i] * (0.3 + 0.7 * fraction)))
            }
        }
        .frame(height: 16)
        .animation(animated ? .easeOut(duration: 0.2) : nil, value: fraction)
        .accessibilityHidden(true)
    }
}

/// Poziom ścieżki (makieta `.meter`): ikona, nazwa, pasek 6 pt (`line` + wypełnienie `accent`) i ✓/— (stan nie tylko kolorem).
/// Tytuł „Microphone: nazwa” dzieli się na etykietę w wierszu i nazwę pogrubioną pod spodem (nazwa nie może być ucięta).
struct LevelRow: View {
    let title: String
    let db: Double?
    var emphasized = false
    var animated = true

    static func fraction(db: Double?) -> Double { max(0, min(1, ((db ?? -60) + 60) / 60)) }

    private var parts: (label: String, detail: String?) {
        guard let r = title.range(of: ": ") else { return (title, nil) }
        return (String(title[..<r.lowerBound]), String(title[r.upperBound...]))
    }
    private var hasSignal: Bool { (db ?? -160) > -60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: parts.label.hasPrefix("Microphone") ? "mic" : "speaker.wave.2")
                    .font(.system(size: 12)).foregroundStyle(.mnText2).frame(width: 14).accessibilityHidden(true)
                Text(parts.label).font(.callout).foregroundStyle(.mnText).frame(width: 92, alignment: .leading)
                ZStack(alignment: .leading) {
                    Capsule().fill(.mnLine)
                    GeometryReader { g in Capsule().fill(.mnAccent).frame(width: g.size.width * Self.fraction(db: db)) }
                }
                .frame(height: 6)
                .animation(animated ? .easeOut(duration: 0.2) : nil, value: db)
                Group {
                    if hasSignal { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.mnAccent) }
                    else { Text("—").foregroundStyle(.mnText2) }
                }
                .frame(width: 14).accessibilityLabel(hasSignal ? "Signal present" : "No signal")
            }
            if let detail = parts.detail {
                Text(detail).font(.callout.weight(.semibold)).foregroundStyle(.mnText).lineLimit(2).padding(.leading, 22)
            }
        }
    }
}
