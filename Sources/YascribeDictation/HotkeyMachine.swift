import YascribeProviders

/// `flags` to pełna maska flag zdarzenia (`CGEventFlags.rawValue`); `.modifier` pochodzi z `flagsChanged`,
/// a `isDown` ustala monitor z obecności bitu danego modyfikatora w `flags`. `isRepeat` = autorepeat klawisza.
public enum HotkeyEvent: Equatable, Sendable {
    case modifier(keyCode: UInt16, flags: UInt64, isDown: Bool)
    case keyDown(keyCode: UInt16, flags: UInt64, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
}

public enum HotkeyAction: Equatable, Sendable { case start, stop, cancel }

/// Czysta maszyna stanów skrótu dyktowania (bez AppKit/CGEvent), karmiona przez monitor.
public struct HotkeyMachine: Sendable {
    private static let escape: UInt16 = 53

    private let hotkey: DictationHotkey
    private let mode: DictationTriggerMode
    /// Skrót jest fizycznie wciśnięty (dla `.cancel` po kombinacji potrzebny, by „zjeść” późniejsze puszczenie).
    private var held = false
    public private(set) var isListening = false

    public init(hotkey: DictationHotkey, mode: DictationTriggerMode) {
        self.hotkey = hotkey
        self.mode = mode
    }

    public mutating func reset() {
        held = false
        isListening = false
    }

    /// Stan sesji z zewnątrz (start z launchera, auto-stop, awaria). Nie rusza `held`: puszczenie trzymanego klawisza zostaje „zjedzone”.
    public mutating func setListening(_ on: Bool) { isListening = on }

    public mutating func handle(_ event: HotkeyEvent) -> HotkeyAction? {
        switch event {
        case let .modifier(keyCode, _, isDown):
            guard hotkey.isModifierOnly, keyCode == hotkey.keyCode else { return nil }
            return isDown ? press() : release()
        case let .keyDown(keyCode, flags, isRepeat):
            if isRepeat { return nil }
            if keyCode == Self.escape, isListening {
                isListening = false
                return .cancel
            }
            if hotkey.isModifierOnly {
                // Modyfikator użyty w kombinacji (Fn+F1…): to nie dyktowanie.
                guard held, isListening else { return nil }
                isListening = false
                return .cancel
            }
            guard keyCode == hotkey.keyCode, flags & hotkey.flags == hotkey.flags else { return nil }
            return press()
        case let .keyUp(keyCode):
            guard !hotkey.isModifierOnly, keyCode == hotkey.keyCode else { return nil }
            return release()
        }
    }

    private mutating func press() -> HotkeyAction? {
        guard !held else { return nil }
        held = true
        if mode == .toggle, isListening {
            isListening = false
            return .stop
        }
        isListening = true
        return .start
    }

    private mutating func release() -> HotkeyAction? {
        guard held else { return nil }
        held = false
        guard mode == .hold, isListening else { return nil }
        isListening = false
        return .stop
    }
}
