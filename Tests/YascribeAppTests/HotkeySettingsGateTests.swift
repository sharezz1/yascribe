import Testing
import YascribeDictation
import YascribeProviders
@testable import YascribeApp

@Test func hotkeyChangesWaitUntilListeningFinishes() {
    var gate = HotkeySettingsGate()
    let requestDuringListening = gate.request(listening: true)
    #expect(!requestDuringListening)
    let stillListening = gate.phaseChanged(listening: true)
    #expect(!stillListening)
    let finishedListening = gate.phaseChanged(listening: false)
    #expect(finishedListening)
    let alreadyApplied = gate.phaseChanged(listening: false)
    #expect(!alreadyApplied)
    let requestWhileIdle = gate.request(listening: false)
    #expect(requestWhileIdle)
}

@Test func heldShortcutStopsBeforeNewShortcutIsApplied() {
    var gate = HotkeySettingsGate()
    var machine = HotkeyMachine(hotkey: .fn, mode: .hold)
    let down = HotkeyEvent.modifier(keyCode: 63, flags: 1 << 23, isDown: true)
    let up = HotkeyEvent.modifier(keyCode: 63, flags: 0, isDown: false)
    let start = machine.handle(down)
    #expect(start == .start)
    let applyDuringListening = gate.request(listening: true)
    #expect(!applyDuringListening)
    let stop = machine.handle(up)
    #expect(stop == .stop)
    let applyAfterListening = gate.phaseChanged(listening: false)
    #expect(applyAfterListening)
    let newKey = DictationHotkey(keyCode: 2, isModifierOnly: false)
    machine = HotkeyMachine(hotkey: newKey, mode: .hold)
    let startWithNewKey = machine.handle(.keyDown(keyCode: 2, flags: 0, isRepeat: false))
    #expect(startWithNewKey == .start)
}
