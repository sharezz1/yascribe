import Testing
import YascribeProviders
@testable import YascribeDictation

private let option: UInt64 = 1 << 19   // CGEventFlags.maskAlternate
private let shift: UInt64 = 1 << 17
private let fnKey: UInt16 = 63
private let esc: UInt16 = 53

private func fnDown() -> HotkeyEvent { .modifier(keyCode: fnKey, flags: 1 << 23, isDown: true) }
private func fnUp() -> HotkeyEvent { .modifier(keyCode: fnKey, flags: 0, isDown: false) }

@Test func holdFnStartsAndStops() {
    var m = HotkeyMachine(hotkey: .fn, mode: .hold)
    #expect(m.handle(fnDown()) == .start)
    #expect(m.isListening)
    #expect(m.handle(fnUp()) == .stop)
    #expect(!m.isListening)
}

@Test func autorepeatIgnored() {
    var hold = HotkeyMachine(hotkey: .fn, mode: .hold)
    #expect(hold.handle(fnDown()) == .start)
    #expect(hold.handle(fnDown()) == nil)
    #expect(hold.isListening)

    let key = DictationHotkey(keyCode: 2, flags: option, isModifierOnly: false)
    for mode in [DictationTriggerMode.hold, .toggle] {
        var m = HotkeyMachine(hotkey: key, mode: mode)
        #expect(m.handle(.keyDown(keyCode: 2, flags: option, isRepeat: false)) == .start)
        #expect(m.handle(.keyDown(keyCode: 2, flags: option, isRepeat: true)) == nil)
        #expect(m.isListening)

        // powtórka na świeżej maszynie (np. Option dociśnięty po klawiszu) też nie startuje
        var fresh = HotkeyMachine(hotkey: key, mode: mode)
        #expect(fresh.handle(.keyDown(keyCode: 2, flags: option, isRepeat: true)) == nil)
        #expect(!fresh.isListening)
    }
}

@Test func fnComboCancelsAndSwallowsRelease() {
    var m = HotkeyMachine(hotkey: .fn, mode: .hold)
    #expect(m.handle(fnDown()) == .start)
    #expect(m.handle(.keyDown(keyCode: 122, flags: 1 << 23, isRepeat: false)) == .cancel)
    #expect(!m.isListening)
    #expect(m.handle(fnUp()) == nil)
    // po puszczeniu Fn kolejne naciśnięcie znów startuje
    #expect(m.handle(fnDown()) == .start)
}

@Test func toggleStartsAndStops() {
    var m = HotkeyMachine(hotkey: .fn, mode: .toggle)
    #expect(m.handle(fnDown()) == .start)
    #expect(m.handle(fnUp()) == nil)
    #expect(m.isListening)
    #expect(m.handle(fnDown()) == .stop)
    #expect(!m.isListening)
    #expect(m.handle(fnUp()) == nil)
}

@Test func plainHotkeyRequiresModifiers() {
    let key = DictationHotkey(keyCode: 2, flags: option, isModifierOnly: false)
    var m = HotkeyMachine(hotkey: key, mode: .hold)
    #expect(m.handle(.keyDown(keyCode: 2, flags: 0, isRepeat: false)) == nil)
    #expect(m.handle(.keyDown(keyCode: 2, flags: shift, isRepeat: false)) == nil)
    #expect(!m.isListening)
    #expect(m.handle(.keyDown(keyCode: 2, flags: option | shift, isRepeat: false)) == .start)
    #expect(m.handle(.keyUp(keyCode: 2)) == .stop)
    #expect(!m.isListening)
}

@Test func escapeCancelsOnlyWhileListening() {
    var m = HotkeyMachine(hotkey: .fn, mode: .hold)
    #expect(m.handle(.keyDown(keyCode: esc, flags: 0, isRepeat: false)) == nil)
    #expect(m.handle(fnDown()) == .start)
    #expect(m.handle(.keyDown(keyCode: esc, flags: 0, isRepeat: false)) == .cancel)
    #expect(!m.isListening)
}

@Test func otherModifierIgnored() {
    var m = HotkeyMachine(hotkey: .fn, mode: .hold)
    #expect(m.handle(.modifier(keyCode: 58, flags: option, isDown: true)) == nil)
    #expect(m.handle(.modifier(keyCode: 58, flags: 0, isDown: false)) == nil)
    #expect(!m.isListening)
}

@Test func externalListeningLetsEscapeCancel() {
    var m = HotkeyMachine(hotkey: .fn, mode: .toggle)
    m.setListening(true)   // start z launchera
    #expect(m.handle(.keyDown(keyCode: esc, flags: 0, isRepeat: false)) == .cancel)
    #expect(!m.isListening)
}

@Test func externalStopIgnoresReleaseAndAllowsRestart() {
    var m = HotkeyMachine(hotkey: .fn, mode: .hold)
    #expect(m.handle(fnDown()) == .start)
    m.setListening(false)  // silnik skończył sam (auto-stop)
    #expect(m.handle(fnUp()) == nil)
    #expect(m.handle(fnDown()) == .start)
}

@Test func suspendedMachineIgnoresEverythingAndResetsOnBothEdges() {
    for mode in [DictationTriggerMode.hold, .toggle] {
        var m = HotkeyMachine(hotkey: .fn, mode: mode)
        #expect(m.handle(fnDown()) == .start)
        m.setSuspended(true)
        #expect(!m.isListening)   // przejście zeruje stan
        #expect(m.handle(fnUp()) == nil)
        #expect(m.handle(fnDown()) == nil)
        #expect(m.handle(.keyDown(keyCode: esc, flags: 0, isRepeat: false)) == nil)
        m.setSuspended(false)
        #expect(m.handle(fnUp()) == nil)   // puszczenie klawisza trzymanego w trakcie przechwytywania nie kończy niczego
        #expect(m.handle(fnDown()) == .start)
    }
}
