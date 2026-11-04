import AppKit
import ApplicationServices
import Carbon.HIToolbox
import YascribeDictation

/// Wstawia tekst dyktowania: schowek + syntetyczne Cmd-V, a w razie wątpliwości tylko schowek.
/// Bezpieczna jako `@unchecked Sendable`: jedyny stan (PID aplikacji docelowej) jest pod `lock`.
final class TextInserter: TextInserting, @unchecked Sendable {
    static let passwordMessage = "A password field is focused."
    static let secureInputMessage = "Secure input is on (another app). Nothing was pasted."
    static let secureInputCopiedMessage = "Secure input is on (another app). The text was copied. Paste it with ⌘V."
    static let accessibilityMessage = "Allow Accessibility to paste automatically."
    static let appChangedMessage = "The active app changed. Text copied."
    static let noTextFieldMessage = "No text field is focused. Text copied."
    /// Konwencja menedżerów schowka (nspasteboard.org): wpis tymczasowy / poufny nie trafia do historii schowka.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = "org.nspasteboard.ConcealedType"

    enum Decision: Equatable { case paste, copy(String), block(String) }

    private let lock = NSLock()
    private var targetPID: pid_t?

    /// Silnik czyta tę nazwę przy starcie sesji; przy okazji zapamiętujemy PID, by przy wklejaniu wykryć zmianę aplikacji.
    var frontmostAppName: String? {
        let app = NSWorkspace.shared.frontmostApplication
        lock.lock(); targetPID = app?.processIdentifier; lock.unlock()
        return app?.localizedName
    }

    /// Poufnego zapisu (hasło z menedżera) nie przywracamy: po wklejeniu czyścimy schowek zamiast zostawiać tekst dyktowania.
    static func shouldRestore(snapshotTypes: [String]) -> Bool {
        !snapshotTypes.isEmpty && !snapshotTypes.contains(concealedType)
    }

    /// Czysta bramka: przy jakiejkolwiek niepewności nie wysyłamy Cmd-V.
    static func decide(secureInput: Bool, trusted: Bool, focusedRole: String?, focusedSubrole: String?,
                       focusIsText: Bool, sameApp: Bool) -> Decision {
        if focusedRole == "AXSecureTextField" || focusedSubrole == kAXSecureTextFieldSubrole { return .block(passwordMessage) }
        // Secure input bywa włączony przez inną aplikację (np. Secure Keyboard Entry w terminalu). Gdy zaufanie i fokus
        // są znane i to nie pole hasła, tekst jest bezpieczny w schowku; przy niepewności blokujemy.
        if secureInput {
            return trusted && focusedRole != nil ? .copy(secureInputCopiedMessage) : .block(secureInputMessage)
        }
        guard trusted else { return .copy(accessibilityMessage) }
        guard sameApp else { return .copy(appChangedMessage) }
        guard focusIsText else { return .copy(noTextFieldMessage) }
        return .paste
    }

    func insert(_ text: String) async -> InsertResult {
        let trusted = AXIsProcessTrusted()
        let focus = trusted ? Self.focusedElement() : nil
        let target = lock.withLock { targetPID }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let decision = Self.decide(secureInput: IsSecureEventInputEnabled(), trusted: trusted,
                                   focusedRole: focus.flatMap { Self.string($0, kAXRoleAttribute) },
                                   focusedSubrole: focus.flatMap { Self.string($0, kAXSubroleAttribute) },
                                   focusIsText: focus.map(Self.isText) ?? false,
                                   sameApp: target != nil && target == frontPID)
        switch decision {
        case let .block(reason): return .blocked(reason: reason)
        case let .copy(reason):
            await MainActor.run { Self.copy(text) }
            return .copiedOnly(reason: reason)
        case .paste:
            let (saved, written) = await MainActor.run { () -> ([[NSPasteboard.PasteboardType: Data]], Int) in
                let saved = Self.snapshot()
                Self.copy(text, transient: true)
                Self.sendPaste()
                return (saved, NSPasteboard.general.changeCount)
            }
            // Wolna aplikacja docelowa może obsłużyć syntetyczne Cmd-V dopiero po przywróceniu, więc zapas.
            try? await Task.sleep(for: .milliseconds(800))
            await MainActor.run {
                // Tylko gdy nikt (ani użytkownik) nie zapisał schowka po nas.
                guard NSPasteboard.general.changeCount == written, !saved.isEmpty else { return }
                NSPasteboard.general.clearContents()
                guard Self.shouldRestore(snapshotTypes: saved.flatMap { $0.keys.map(\.rawValue) }) else { return }
                let items = saved.map { types -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in types { item.setData(data, forType: type) }
                    return item
                }
                NSPasteboard.general.writeObjects(items)
            }
            return .inserted
        }
    }

    // MARK: - Wywołania systemu

    /// `transient` tylko przy wklejaniu (tymczasowy wpis); przy samym kopiowaniu tekst ma zostać w schowku i w jego historii.
    @MainActor private static func copy(_ text: String, transient: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if transient { NSPasteboard.general.setData(Data(), forType: transientType) }
    }

    /// Wszystkie typy wszystkich elementów schowka.
    @MainActor private static func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var out: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { out[type] = data } }
            return out
        }.filter { !$0.isEmpty }
    }

    private static func sendPaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            e?.flags = .maskCommand   // jawnie: fizycznie trzymane modyfikatory nie mogą się dołączyć
            e?.post(tap: .cghidEventTap)
        }
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    /// Pole tekstowe: znana rola albo zaznaczenie tekstu (pola w przeglądarkach i edytorach go wystawiają).
    private static func isText(_ el: AXUIElement) -> Bool {
        let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]
        if let role = string(el, kAXRoleAttribute), textRoles.contains(role) { return true }
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &v) == .success
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v as? String : nil
    }
}
