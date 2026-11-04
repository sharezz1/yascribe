import AppKit
import SwiftUI
import YascribeDictation
import YascribeProviders

/// Pole skrótu w Settings: klik zaczyna przechwytywanie, decyzje podejmuje `HotkeyCapture` (czysta, testowana).
/// Esc anuluje; odrzucony gest (samotny Command/Option/Control/Shift) zgłasza komunikat przez `message`.
struct HotkeyRecorder: NSViewRepresentable {
    let hotkey: DictationHotkey
    @Binding var message: String?
    /// Początek i koniec przechwytywania: globalny skrót jest wtedy wstrzymany (kontroler wie o tym przez to wywołanie).
    var onCapturing: (Bool) -> Void = { _ in }
    var onChange: (DictationHotkey) -> Void

    func makeNSView(context: Context) -> HotkeyField { HotkeyField() }

    func updateNSView(_ view: HotkeyField, context: Context) {
        view.hotkey = hotkey
        view.onCommit = onChange
        view.onCapturing = onCapturing
        view.onMessage = { text in if message != text { message = text } }
    }
}

final class HotkeyField: NSView {
    var hotkey = DictationHotkey.fn { didSet { refresh() } }
    var onCommit: (DictationHotkey) -> Void = { _ in }
    var onMessage: (String?) -> Void = { _ in }
    var onCapturing: (Bool) -> Void = { _ in }

    private var capture: HotkeyCapture?
    /// Pole przyjmuje fokus tylko z kliknięcia: Tab nie może w nie wejść ani w nim utknąć.
    private var clicked = false
    private var observers: [any NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("Dictation shortcut")
        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { clicked }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 28) }

    override func mouseDown(with event: NSEvent) {
        clicked = true
        defer { clicked = false }
        window?.makeFirstResponder(self)
    }

    /// VoiceOver „naciśnij": to samo co kliknięcie, które zaczyna przechwytywanie.
    override func accessibilityPerformPress() -> Bool {
        clicked = true
        defer { clicked = false }
        return window?.makeFirstResponder(self) ?? false
    }

    override func becomeFirstResponder() -> Bool {
        capture = HotkeyCapture()
        onMessage(nil)
        onCapturing(true)
        refresh()
        // Przechwytywanie nie może przeżyć utraty uwagi użytkownika: inne okno, inna aplikacja, kliknięcie obok.
        let onLeave: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.leave() } }
        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main, using: onLeave),
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: onLeave),
        ]
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self, event.window !== window || !bounds.contains(convert(event.locationInWindow, from: nil)) { leave() }
            return event
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        endCapture()
        return true
    }

    /// Widok znika (zmiana zakładki) w trakcie przechwytywania: bez tego skrót zostałby wstrzymany na stałe.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endCapture() }
        super.viewWillMove(toWindow: newWindow)
    }

    isolated deinit { endCapture() }

    private func leave() { window?.makeFirstResponder(nil) }

    /// Jedyne miejsce, które zdejmuje obserwatorów i monitor oraz wznawia globalny skrót; bezpieczne przy wielokrotnym wywołaniu.
    private func endCapture() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        guard capture != nil else { return }
        capture = nil
        onCapturing(false)
        refresh()
    }

    override func keyDown(with event: NSEvent) { feed(HotkeyEventMapping.event(keyCode: event.keyCode, flags: UInt64(event.modifierFlags.rawValue), type: .keyDown, isRepeat: event.isARepeat)) }
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) { feed(HotkeyEventMapping.event(keyCode: event.keyCode, flags: UInt64(event.modifierFlags.rawValue), type: .flagsChanged)) }

    /// Kombinacje z Command trafiają najpierw tutaj (menu), a w trakcie przechwytywania mają zostać skrótem.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard capture != nil else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private func feed(_ event: HotkeyEvent) {
        guard var c = capture else { return }
        let result = c.handle(event)
        capture = c
        onMessage(c.message)
        if let result {
            onCommit(result)
            leave()
        } else if c.cancelled {
            leave()
        }
    }

    private func refresh() {
        label.stringValue = capture != nil ? "Press a key…" : HotkeyCapture.label(hotkey)
        label.textColor = capture != nil ? .secondaryLabelColor : .labelColor
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = 7
            layer?.cornerCurve = .continuous
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderWidth = capture != nil ? 1.5 : 0.5
            layer?.borderColor = (capture != nil ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }
}
