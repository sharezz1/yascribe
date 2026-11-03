import CoreGraphics
import Foundation
import os
import YascribeDictation
import YascribeProviders

/// Globalny skrót dyktowania: `CGEventTap` tylko do odczytu (Input Monitoring) karmi `HotkeyMachine`.
///
/// Zakończenie sesji przez silnik (auto-stop, awaria mikrofonu, odmowa) zgłasza się przez `setListening(false)`:
/// gasi tylko „słucham”, więc puszczenie wciąż trzymanego klawisza zostaje zjedzone. `reset()` zeruje całą maszynę
/// (zmiana konfiguracji, ponowne włączenie tapu, `stop()`); po nim maszyna nie słucha, kontroler musi to uwzględnić.
@MainActor final class GlobalHotkeyMonitor {
    private static let log = Logger(subsystem: "io.github.sharezz1.yascribe", category: "dictation-hotkey")

    private let onAction: @MainActor (HotkeyAction) -> Void
    private var machine = HotkeyMachine(hotkey: .fn, mode: .hold)
    private var mode: DictationTriggerMode = .hold
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(onAction: @escaping @MainActor (HotkeyAction) -> Void) {
        self.onAction = onAction
    }

    isolated deinit { stop() }

    var permissionGranted: Bool { CGPreflightListenEventAccess() }

    /// Systemowe okno Input Monitoring; zgodę nadaje użytkownik.
    func requestPermission() { _ = CGRequestListenEventAccess() }

    var isRunning: Bool { tap != nil }

    func configure(hotkey: DictationHotkey, mode: DictationTriggerMode) {
        machine = HotkeyMachine(hotkey: hotkey, mode: mode)
        self.mode = mode
    }

    func setListening(_ on: Bool) { machine.setListening(on) }

    func reset() { machine.reset() }

    /// `false` bez uprawnienia albo gdy system nie utworzył tapu.
    func start() -> Bool {
        if tap != nil { return true }
        guard permissionGranted else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                           eventsOfInterest: CGEventMask(mask), callback: hotkeyTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Self.log.error("tapCreate failed")
            return false
        }
        let src = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        machine.reset()
    }

    fileprivate func receive(_ event: HotkeyEvent) {
        guard tap != nil else { return }   // zdarzenie z kolejki po `stop()`
        #if DEBUG
        // Tylko modyfikatory (spike Fn); zwykłych klawiszy nie logujemy, to byłby keylogger w Console.
        if case let .modifier(keyCode, flags, isDown) = event {
            Self.log.debug("flagsChanged keyCode=\(keyCode) flags=\(String(flags, radix: 16)) down=\(isDown)")
        }
        #endif
        if let action = machine.handle(event) { onAction(action) }
    }

    /// System wyłącza tap po przekroczeniu czasu albo na życzenie użytkownika; puszczenie klawisza mogło wtedy zginąć.
    fileprivate func reenable() {
        guard let tap else { return }
        Self.log.notice("event tap re-enabled")
        let wasListening = machine.isListening
        machine.reset()
        if wasListening {
            // Hold: brak zdarzenia puszczenia, kończymy sami. Toggle: sesja trwa do kolejnego naciśnięcia.
            if mode == .hold { onAction(.stop) } else { machine.setListening(true) }
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

/// Wolna funkcja C: tylko mapuje zdarzenie i przekazuje je na główny aktor.
private func hotkeyTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                               _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let kind: HotkeyEventMapping.Kind
    switch type {
    case .flagsChanged: kind = .flagsChanged
    case .keyDown: kind = .keyDown
    case .keyUp: kind = .keyUp
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        Task { @MainActor in monitor.reenable() }
        return Unmanaged.passUnretained(event)
    default: return Unmanaged.passUnretained(event)
    }
    let mapped = HotkeyEventMapping.event(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                          flags: event.flags.rawValue, type: kind,
                                          isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    Task { @MainActor in monitor.receive(mapped) }
    return Unmanaged.passUnretained(event)
}
