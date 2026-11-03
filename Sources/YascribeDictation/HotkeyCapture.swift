import YascribeProviders

/// Decyzje pola „Press a key…” w Settings (bez AppKit): z zachowania klawiatury robi `DictationHotkey`.
/// Przyjmowane: sam Fn, modyfikator(y) + klawisz, klawisz funkcyjny, zwykły klawisz. Samotny Command/Option/Control/Shift
/// jest odrzucany: monitor sprowadza lewą i prawą stronę do jednego bitu, więc taki skrót działałby na obu klawiszach.
public struct HotkeyCapture: Sendable {
    public static let loneModifierMessage = "Use Fn, or a modifier together with another key."

    private static let escape: UInt16 = 53
    private static let tab: UInt16 = 48
    private static let fn: UInt16 = 63
    /// Command, Option, Control, Shift (`CGEventFlags`); bez Fn, który klawisze strzałek i funkcyjne dokładają same.
    private static let modifierMask: UInt64 = 0x100000 | 0x80000 | 0x40000 | 0x20000

    /// Esc albo Tab: użytkownik zrezygnował, pole kończy przechwytywanie bez zmiany.
    public private(set) var cancelled = false
    /// Powód odrzucenia ostatniego gestu; czyszczony przy następnym zdarzeniu.
    public private(set) var message: String?

    /// Modyfikator wciśnięty jako pierwszy i jeszcze nie puszczony.
    private var pending: UInt16?
    /// W trakcie trzymania modyfikatora padł inny klawisz albo drugi modyfikator: to nie jest „sam modyfikator”.
    private var combined = false

    public init() {}

    public mutating func handle(_ e: HotkeyEvent) -> DictationHotkey? {
        message = nil
        switch e {
        case let .modifier(keyCode, _, isDown):
            if isDown {
                if pending == nil { pending = keyCode; combined = false } else { combined = true }
                return nil
            }
            guard pending == keyCode else { return nil }
            pending = nil
            if combined { return nil }
            if keyCode == Self.fn { return .fn }
            message = Self.loneModifierMessage
            return nil
        case let .keyDown(keyCode, flags, isRepeat):
            if isRepeat { return nil }
            // Tab opuszcza pole (nawigacja klawiaturą), tak jak Esc; nie bywa skrótem.
            if keyCode == Self.escape || keyCode == Self.tab {
                cancelled = true
                return nil
            }
            combined = true
            return DictationHotkey(keyCode: keyCode, flags: flags & Self.modifierMask, isModifierOnly: false)
        case .keyUp:
            return nil
        }
    }

    /// „Fn”, „Left ⌥”, „⌥ Space”, „⌃⇧ F5”; kod spoza tabeli → „Key 99”.
    public static func label(_ h: DictationHotkey) -> String {
        if h.isModifierOnly {
            switch h.keyCode {
            case 63: return "Fn"
            case 55: return "Left ⌘"
            case 54: return "Right ⌘"
            case 56: return "Left ⇧"
            case 60: return "Right ⇧"
            case 58: return "Left ⌥"
            case 61: return "Right ⌥"
            case 59: return "Left ⌃"
            case 62: return "Right ⌃"
            default: return "Key \(h.keyCode)"
            }
        }
        let symbols = [(0x40000, "⌃"), (0x80000, "⌥"), (0x20000, "⇧"), (0x100000, "⌘")]
            .filter { h.flags & UInt64($0.0) != 0 }.map(\.1).joined()
        let key = keyNames[h.keyCode] ?? "Key \(h.keyCode)"
        return symbols.isEmpty ? key : "\(symbols) \(key)"
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 49: "Space",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑", 36: "Return", 51: "Delete", 117: "Forward Delete",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
    ]
}
