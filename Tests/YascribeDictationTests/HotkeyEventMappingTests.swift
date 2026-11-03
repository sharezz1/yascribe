import Testing
@testable import YascribeDictation

private let option: UInt64 = 0x80000   // CGEventFlags.maskAlternate
private let command: UInt64 = 0x100000 // CGEventFlags.maskCommand

@Test func fnMapsToSecondaryFnBit() {
    #expect(HotkeyEventMapping.modifierBit(for: 63) == 0x800000)
    #expect(HotkeyEventMapping.event(keyCode: 63, flags: 0x800000, type: .flagsChanged)
            == .modifier(keyCode: 63, flags: 0x800000, isDown: true))
}

@Test func modifierDownDerivedFromFlags() {
    #expect(HotkeyEventMapping.event(keyCode: 58, flags: option | 0x100, type: .flagsChanged)
            == .modifier(keyCode: 58, flags: option | 0x100, isDown: true))
    // Inny modyfikator wciąż trzymany nie udaje wciśniętego Option.
    #expect(HotkeyEventMapping.event(keyCode: 58, flags: command, type: .flagsChanged)
            == .modifier(keyCode: 58, flags: command, isDown: false))
}

@Test func leftAndRightOptionShareBit() {
    #expect(HotkeyEventMapping.modifierBit(for: 58) == option)
    #expect(HotkeyEventMapping.modifierBit(for: 61) == option)
    #expect(HotkeyEventMapping.modifierBit(for: 55) == command)
    #expect(HotkeyEventMapping.modifierBit(for: 54) == command)
    #expect(HotkeyEventMapping.modifierBit(for: 56) == 0x20000)
    #expect(HotkeyEventMapping.modifierBit(for: 60) == 0x20000)
    #expect(HotkeyEventMapping.modifierBit(for: 59) == 0x40000)
    #expect(HotkeyEventMapping.modifierBit(for: 62) == 0x40000)
}

@Test func unknownKeyCodeHasNoModifierBit() {
    #expect(HotkeyEventMapping.modifierBit(for: 0) == nil)
    #expect(HotkeyEventMapping.modifierBit(for: 57) == nil)   // Caps Lock: nie jest skrótem dyktowania
    #expect(HotkeyEventMapping.event(keyCode: 57, flags: 0x10000, type: .flagsChanged)
            == .modifier(keyCode: 57, flags: 0x10000, isDown: false))
}

@Test func keyDownCarriesFlags() {
    #expect(HotkeyEventMapping.event(keyCode: 2, flags: option, type: .keyDown)
            == .keyDown(keyCode: 2, flags: option, isRepeat: false))
    #expect(HotkeyEventMapping.event(keyCode: 2, flags: option, type: .keyDown, isRepeat: true)
            == .keyDown(keyCode: 2, flags: option, isRepeat: true))
    #expect(HotkeyEventMapping.event(keyCode: 2, flags: option, type: .keyUp) == .keyUp(keyCode: 2))
}
