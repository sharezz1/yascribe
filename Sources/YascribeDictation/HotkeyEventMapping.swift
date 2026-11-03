/// Zdarzenie `CGEvent` (kod klawisza, `CGEventFlags.rawValue`) → `HotkeyEvent`; bez CoreGraphics, żeby dało się testować.
public enum HotkeyEventMapping {
    public enum Kind: Sendable { case flagsChanged, keyDown, keyUp }

    /// Bit maski niezależnej od strony klawiatury, więc lewy i prawy modyfikator dzielą bit.
    public static func modifierBit(for keyCode: UInt16) -> UInt64? {
        switch keyCode {
        case 63: 0x800000              // Fn (maskSecondaryFn)
        case 55, 54: 0x100000          // Command
        case 56, 60: 0x20000           // Shift
        case 58, 61: 0x80000           // Option
        case 59, 62: 0x40000           // Control
        default: nil
        }
    }

    public static func event(keyCode: UInt16, flags: UInt64, type: Kind, isRepeat: Bool = false) -> HotkeyEvent {
        switch type {
        case .flagsChanged:
            let isDown = modifierBit(for: keyCode).map { flags & $0 != 0 } ?? false
            return .modifier(keyCode: keyCode, flags: flags, isDown: isDown)
        case .keyDown: return .keyDown(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        case .keyUp: return .keyUp(keyCode: keyCode)
        }
    }
}
