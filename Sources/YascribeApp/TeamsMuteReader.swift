import AppKit
import ApplicationServices
import YascribeMeetings

/// Czyta stan mute z przycisku w oknie spotkania Teams przez Accessibility (BACKLOG "Z rozmowy 2026-10-27"). Wyciszenie w Teams
/// nie zwalnia mikrofonu (pomiar T0), więc sygnałów audio nie użyjemy; API Teams na :8124 wymaga parowania i nowego Teams.
/// Wołać poza głównym wątkiem: przejście po drzewie WebView trwa.
enum TeamsMuteReader {
    private static let bundleID = "com.microsoft.teams2"
    /// Drzewo okna spotkania ma setki elementów; sufit chroni przed pełnym przejściem po całym czacie.
    private static let nodeLimit = 4000
    nonisolated(unsafe) private static var prompted = false

    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Systemowe okno zgody, raz na uruchomienie aplikacji i tylko gdy Teams działa; zgodę nadaje użytkownik.
    static func requestAccessIfNeeded() {
        guard !AXIsProcessTrusted(), isRunning, !prompted else { return }
        prompted = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// `nil` = brak zgody, Teams nie działa albo nie ma otwartego okna spotkania.
    static func read() -> CallMuteState? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        var queue: [AXUIElement] = elements(root, kAXWindowsAttribute)
        var i = 0
        while i < queue.count, i < nodeLimit {
            let el = queue[i]; i += 1
            if string(el, kAXRoleAttribute) == kAXButtonRole {
                for attr in [kAXDescriptionAttribute, kAXTitleAttribute] {
                    if let label = string(el, attr), let state = CallMuteState(buttonLabel: label) { return state }
                }
            }
            queue += elements(el, kAXChildrenAttribute)
        }
        return nil
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v as? String : nil
    }

    private static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? (v as? [AXUIElement] ?? []) : []
    }
}
