import AppKit
import Observation
import SwiftUI
import YascribeDictation
import YascribeRecording

/// Pastylka dyktowania na głównym ekranie: kółko, po najechaniu pigułka „Dictate” / „Record meeting”, w trakcie sesji status.
/// Panel nigdy nie staje się oknem klucza ani nie aktywuje aplikacji: syntetyczne Cmd-V i fokus AX muszą zostać
/// w aplikacji, która była na wierzchu przy starcie dyktowania (bez `PillPanel` z `canBecomeKey`).
@MainActor final class LauncherPanelController: ObservableObject {
    @Published private(set) var presentation: LauncherPresentation = .dot
    @Published private(set) var level: Float = 0
    unowned let controller: DictationController
    private unowned let model: AppModel
    private var state = LauncherState()
    private var panel: NSPanel?
    private var enabled = false
    /// Pokolenie pętli obserwacji (jak `DictationController.trackPhase`): `hide()` + `show()` nie zostawia dwóch łańcuchów.
    private var generation = 0
    /// Nasze `setFrame` też wysyła `didMove`; zapisujemy tylko przeciągnięcie przez użytkownika.
    private var placing = false
    private var collapseTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(controller: DictationController, model: AppModel) {
        self.controller = controller
        self.model = model
    }

    func show() {
        guard !enabled else { return refresh() }
        enabled = true
        generation += 1
        track(generation)
    }

    func hide() {
        enabled = false
        generation += 1
        collapseTask?.cancel()
        saveTask?.cancel()
        stopLevel()
        panel?.orderOut(nil)
    }

    func dictate() { controller.toggleFromLauncher() }

    /// Jak przycisk w Meetings: powód odmowy w `lastError`; dźwięk, bo okno aplikacji może być zamknięte.
    func recordMeeting() {
        if !model.startRecording(event: nil) { NSSound.beep() }
    }

    func hoverChanged(_ inside: Bool) {
        state.hoverChanged(inside, at: Self.clock)
        refresh()
        collapseTask?.cancel()
        guard !inside else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LauncherState.collapseDelay + 0.05))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private static var clock: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func track(_ gen: Int) {
        guard enabled, gen == generation else { return }
        withObservationTracking {
            _ = controller.engine.phase
            _ = model.recording.isRecording
        } onChange: { [weak self] in
            // `onChange` przychodzi przed zmianą: stan czytamy świeżo w kolejnym obrocie.
            Task { @MainActor in self?.track(gen) }
        }
        refresh()
    }

    private func refresh() {
        guard enabled, let p = state.presentation(phase: controller.engine.phase,
                                                  meetingRecording: model.recording.isRecording, now: Self.clock) else {
            stopLevel()
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        let changed = p != presentation || !panel.isVisible
        presentation = p
        if p == .status(.listening) { startLevel() } else { stopLevel() }
        if changed { place(panel, keepAnchor: panel.isVisible) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Środek dolnej krawędzi stoi w miejscu przy zmianie rozmiaru; przy pokazaniu i zmianie ekranów: zapamiętane X
    /// (środek dolnej krawędzi) albo środek `visibleFrame`, 12 pt nad dolną krawędzią. Tylko główny ekran.
    private func place(_ panel: NSPanel, keepAnchor: Bool) {
        guard let v = NSScreen.screens.first?.visibleFrame else { return }
        let anchor = keepAnchor ? CGPoint(x: panel.frame.midX, y: panel.frame.minY)
            : CGPoint(x: model.settings.dictationOrDefault.launcherOriginX.map { CGFloat($0) } ?? v.midX, y: v.minY + 12)
        placing = true
        panel.setFrame(PillPlacement.frame(size: Self.size(presentation), bottomCenter: anchor, screens: [v]), display: true)
        placing = false
        DispatchQueue.main.async { panel.invalidateShadow() }
    }

    static func size(_ p: LauncherPresentation) -> CGSize {
        switch p {
        case .dot: CGSize(width: 40, height: 40)
        case .expanded: CGSize(width: 270, height: 44)
        case .status(.error): CGSize(width: 340, height: 56)
        case .status: CGSize(width: 180, height: 44)
        }
    }

    private func startLevel() {
        guard levelTask == nil else { return }
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.level = self.controller.level
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopLevel() {
        levelTask?.cancel()
        levelTask = nil
        if level != 0 { level = 0 }
    }

    private func moved() {
        guard !placing else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, let panel = self.panel, let v = NSScreen.screens.first?.visibleFrame else { return }
            // Przeciągnięcie na drugi ekran nie może zapisać X spoza głównego.
            let x = LauncherState.originX(Double(panel.frame.midX), minX: Double(v.minX), maxX: Double(v.maxX))
            var d = self.model.settings.dictationOrDefault
            guard d.launcherOriginX != x else { return }
            d.launcherOriginX = x
            self.model.settings.dictation = d
            self.model.save()   // bez `applySettings`: położenie nie zmienia skrótu ani uprawnień
        }
    }

    private func screensChanged() {
        guard let panel, panel.isVisible else { return }
        place(panel, keepAnchor: false)
    }

    private func makePanel() -> NSPanel {
        // `.borderless` bez `canBecomeKey`: klik nie zabiera klawiatury aplikacji docelowej; `.nonactivatingPanel` jej nie aktywuje.
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size(.dot)),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Dictation"   // czyta go VoiceOver
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = LauncherHostingView(rootView: LauncherView(launcher: self))
        host.sizingOptions = []   // rozmiar okna ustawia tylko `place`
        p.contentView = host
        let center = NotificationCenter.default
        _ = center.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }
        _ = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        panel = p
        return p
    }
}

/// Pierwszy klik w nieaktywnej aplikacji trafia od razu w przyciski. Hover z własnego `NSTrackingArea` z `.activeAlways`:
/// panel nigdy nie jest kluczem, a aplikacja zwykle nieaktywna, więc nie polegamy na `.onHover` SwiftUI.
private final class LauncherHostingView: NSHostingView<LauncherView> {
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit woła to także po zmianie rozmiaru (kółko ⇄ pigułka); `.inVisibleRect` i tak śledzi bieżące granice.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        rootView.launcher.hoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        rootView.launcher.hoverChanged(false)
    }
}

/// `WindowDragGesture` z `pillGlass` działa tylko w oknie klucza, a ten panel nim nie bywa: uchwyt przeciąga okno sam.
private struct DragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { HandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct LauncherView: View {
    @ObservedObject var launcher: LauncherPanelController

    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)   // hover: `LauncherHostingView`
    }

    @ViewBuilder private var content: some View {
        switch launcher.presentation {
        case .dot:
            YascribeMark().scaleEffect(0.75).frame(width: 40, height: 40)
                .overlay(DragHandle())
                .pillGlass(Circle())
                .accessibilityElement()
                .accessibilityLabel("Yascribe dictation")
                .accessibilityHint("Hover to show Dictate and Record meeting")
                .accessibilityAction(named: "Dictate") { launcher.dictate() }
                .accessibilityAction(named: "Record meeting") { launcher.recordMeeting() }
        case .expanded:
            let busy = launcher.controller.engine.isBusy
            HStack(spacing: 8) {
                YascribeMark().scaleEffect(0.75).frame(width: 28, height: 28)
                    .overlay(DragHandle()).help("Drag to move")
                Button { launcher.dictate() } label: { Text("Dictate").lineLimit(1).fixedSize() }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .accessibilityLabel("Dictate")
                Button { launcher.recordMeeting() } label: { Text("Record meeting").lineLimit(1).fixedSize() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .disabled(busy)   // zabezpieczenie: w trakcie sesji status zastępuje pigułkę
                    .help(busy ? "Finish dictating first." : "Start recording a meeting")
                    .accessibilityLabel("Record meeting")
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pillGlass(Capsule())
        case .status(let s):
            HStack(spacing: 8) { status(s) }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pillGlass(Capsule())
        }
    }

    @ViewBuilder private func status(_ s: LauncherStatus) -> some View {
        switch s {
        case .listening:
            Image(systemName: "mic.fill").foregroundStyle(.mnText2).accessibilityHidden(true)
            ZStack(alignment: .leading) {
                Capsule().fill(.mnLine)
                Capsule().fill(.mnAccent).frame(width: 60 * CGFloat(min(1, max(0, launcher.level))))
            }
            .frame(width: 60, height: 6)
            .accessibilityLabel("Listening")
            Spacer(minLength: 0)
            Button("Stop") { launcher.dictate() }.buttonStyle(StopButtonStyle()).accessibilityLabel("Stop dictation")
        case .processing:
            ProgressView().controlSize(.small)
            Text("Transcribing…").font(.callout).foregroundStyle(.mnText)
        case .inserted:
            Image(systemName: "checkmark").foregroundStyle(.mnAccent).accessibilityHidden(true)
            Text("Pasted").font(.callout).foregroundStyle(.mnText)
        case .copied:
            Image(systemName: "doc.on.clipboard").foregroundStyle(.mnText2).accessibilityHidden(true)
            Text("Copied").font(.callout).foregroundStyle(.mnText)
        case .error(let message):
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.mnWarn).accessibilityHidden(true)
            Text(message).font(.caption).foregroundStyle(.mnText).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            if launcher.controller.engine.canRetry {
                Button("Retry") { launcher.controller.engine.retry() }.buttonStyle(PillButtonStyle(kind: .small))
            }
        }
    }
}
