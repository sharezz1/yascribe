import AppKit
import SwiftUI
import YascribeDictation
import YascribeProviders

/// Pole skrótu w Settings: klik zaczyna przechwytywanie, decyzje podejmuje `HotkeyCapture` (czysta, testowana).
/// Esc anuluje; odrzucony gest (samotny Command/Option/Control/Shift) zgłasza komunikat przez `message`.
struct HotkeyRecorder: NSViewRepresentable {
    let hotkey: DictationHotkey
    @Binding var message: String?
    var onChange: (DictationHotkey) -> Void

    func makeNSView(context: Context) -> HotkeyField { HotkeyField() }

    func updateNSView(_ view: HotkeyField, context: Context) {
        view.hotkey = hotkey
        view.onCommit = onChange
        view.onMessage = { text in if message != text { message = text } }
    }
}

final class HotkeyField: NSView {
    var hotkey = DictationHotkey.fn { didSet { refresh() } }
    var onCommit: (DictationHotkey) -> Void = { _ in }
    var onMessage: (String?) -> Void = { _ in }

    private var capture: HotkeyCapture?
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

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 28) }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func becomeFirstResponder() -> Bool {
        capture = HotkeyCapture()
        onMessage(nil)
        refresh()
        return true
    }

    override func resignFirstResponder() -> Bool {
        capture = nil
        refresh()
        return true
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
            window?.makeFirstResponder(nil)
        } else if c.cancelled {
            window?.makeFirstResponder(nil)
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
