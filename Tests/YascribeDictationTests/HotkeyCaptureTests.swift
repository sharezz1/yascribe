import Testing
import YascribeProviders
@testable import YascribeDictation

private let option: UInt64 = 1 << 19
private let shift: UInt64 = 1 << 17
private let command: UInt64 = 1 << 20

private func down(_ code: UInt16, flags: UInt64 = 0) -> HotkeyEvent { .modifier(keyCode: code, flags: flags, isDown: true) }
private func up(_ code: UInt16) -> HotkeyEvent { .modifier(keyCode: code, flags: 0, isDown: false) }
private func key(_ code: UInt16, flags: UInt64 = 0, repeated: Bool = false) -> HotkeyEvent { .keyDown(keyCode: code, flags: flags, isRepeat: repeated) }

@Test func loneModifierCommitsOnRelease() {
    var c = HotkeyCapture()
    #expect(c.handle(down(63, flags: 1 << 23)) == nil)
    #expect(c.handle(up(63)) == .fn)
}

@Test func modifierPlusKeyCommitsCombo() {
    var c = HotkeyCapture()
    #expect(c.handle(down(58, flags: option)) == nil)
    let h = c.handle(key(2, flags: option | 1 << 23))   // bit Fn z klawiatury nie wchodzi do skrótu
    #expect(h == DictationHotkey(keyCode: 2, flags: option, isModifierOnly: false))
    #expect(c.handle(up(58)) == nil)   // puszczenie modyfikatora po kombinacji niczego nie zatwierdza
}

@Test func escapeCancelsCapture() {
    var c = HotkeyCapture()
    #expect(c.handle(key(53)) == nil)
    #expect(c.cancelled)
}

@Test func loneSidedModifierIsRejected() {
    for code: UInt16 in [55, 54, 56, 60, 58, 61, 59, 62] {
        var c = HotkeyCapture()
        #expect(c.handle(down(code, flags: option)) == nil)
        #expect(c.handle(up(code)) == nil)
        #expect(c.message == "Use Fn, or a modifier together with another key.")
    }
    // komunikat znika przy następnym zdarzeniu
    var c = HotkeyCapture()
    _ = c.handle(down(58)); _ = c.handle(up(58))
    _ = c.handle(key(49, flags: 0))
    #expect(c.message == nil)
}

@Test func twoModifiersWithoutKeyCommitNothing() {
    var c = HotkeyCapture()
    _ = c.handle(down(58, flags: option)); _ = c.handle(down(56, flags: option | shift))
    #expect(c.handle(up(56)) == nil)
    #expect(c.handle(up(58)) == nil)
}

@Test func functionAndPlainKeysAreAccepted() {
    var c = HotkeyCapture()
    #expect(c.handle(key(96, flags: 1 << 23)) == DictationHotkey(keyCode: 96, flags: 0, isModifierOnly: false))
    var d = HotkeyCapture()
    #expect(d.handle(key(49, repeated: true)) == nil)
    #expect(d.handle(key(49)) == DictationHotkey(keyCode: 49, flags: 0, isModifierOnly: false))
}

@Test func labels() {
    #expect(HotkeyCapture.label(.fn) == "Fn")
    #expect(HotkeyCapture.label(DictationHotkey(keyCode: 58, isModifierOnly: true)) == "Left ⌥")
    #expect(HotkeyCapture.label(DictationHotkey(keyCode: 61, isModifierOnly: true)) == "Right ⌥")
    #expect(HotkeyCapture.label(DictationHotkey(keyCode: 49, flags: option, isModifierOnly: false)) == "⌥ Space")
    #expect(HotkeyCapture.label(DictationHotkey(keyCode: 96, flags: shift | command, isModifierOnly: false)) == "⇧⌘ F5")
    #expect(HotkeyCapture.label(DictationHotkey(keyCode: 99 + 200, isModifierOnly: false)) == "Key 299")
}
