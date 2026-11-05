/// Zdarzenie `CGEvent` (kod klawisza, `CGEventFlags.rawValue`) → `HotkeyEvent`; bez CoreGraphics, żeby dało się testować.
public enum HotkeyEventMapping {
    public enum Kind: Sendable { case flagsChanged, keyDown, keyUp }

    /// Bit maski niezależnej od strony klawiatury, więc lewy i prawy modyfikator dzielą bit (strony rozróżnia `isDown` bitami urządzenia).
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

    /// Bity zależne od strony (`NX_DEVICE*KEYMASK`) w dolnym słowie flag: osobne dla lewego i prawego modyfikatora.
    public static func deviceBit(for keyCode: UInt16) -> UInt64? {
        switch keyCode {
        case 59: 0x1          // lewy Control
        case 62: 0x2000       // prawy Control
        case 56: 0x2          // lewy Shift
        case 60: 0x4          // prawy Shift
        case 55: 0x8          // lewy Command
        case 54: 0x10         // prawy Command
        case 58: 0x20         // lewy Option
        case 61: 0x40         // prawy Option
        default: nil
        }
    }

    private static let allDeviceBits: UInt64 = 0x1 | 0x2000 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40

    /// Czy modyfikator `keyCode` jest wciśnięty. Gdy zdarzenie niesie bity stron, rozstrzyga bit tej strony (prawy Option puszczony przy
    /// trzymanym lewym nie jest „wciśnięty"); gdy ich nie niesie (klawiatura wirtualna), zostaje bit wspólny.
    public static func isDown(keyCode: UInt16, flags: UInt64) -> Bool {
        if let device = deviceBit(for: keyCode), flags & allDeviceBits != 0 { return flags & device != 0 }
        return modifierBit(for: keyCode).map { flags & $0 != 0 } ?? false
    }

    public static func event(keyCode: UInt16, flags: UInt64, type: Kind, isRepeat: Bool = false) -> HotkeyEvent {
        switch type {
        case .flagsChanged:
            return .modifier(keyCode: keyCode, flags: flags, isDown: isDown(keyCode: keyCode, flags: flags))
        case .keyDown: return .keyDown(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        case .keyUp: return .keyUp(keyCode: keyCode)
        }
    }
}
