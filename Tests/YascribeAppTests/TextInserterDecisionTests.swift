import Testing
@testable import YascribeApp

private func decide(secure: Bool = false, trusted: Bool = true, role: String? = "AXTextField", subrole: String? = nil,
                    text: Bool = true, sameApp: Bool = true) -> TextInserter.Decision {
    TextInserter.decide(secureInput: secure, trusted: trusted, focusedRole: role, focusedSubrole: subrole,
                        focusIsText: text, sameApp: sameApp)
}

@Test func inserterPastesOnlyWhenSure() {
    #expect(decide() == .paste)
    #expect(decide(secure: true) == .copy(TextInserter.secureInputMessage))   // secure input z innej aplikacji
    #expect(decide(secure: true, text: false) == .copy(TextInserter.secureInputMessage))
    #expect(decide(secure: true, trusted: false) == .block(TextInserter.secureInputMessage))
    #expect(decide(secure: true, role: nil) == .block(TextInserter.secureInputMessage))
    #expect(decide(secure: true, role: "AXSecureTextField") == .block(TextInserter.passwordMessage))
    #expect(decide(secure: true, subrole: "AXSecureTextField") == .block(TextInserter.passwordMessage))
    #expect(decide(subrole: "AXSecureTextField") == .block(TextInserter.passwordMessage))
    #expect(decide(secure: true, trusted: false, role: nil, text: false) == .block(TextInserter.secureInputMessage))
    #expect(decide(trusted: false, role: nil, text: false) == .copy(TextInserter.accessibilityMessage))
    #expect(decide(sameApp: false) == .copy(TextInserter.appChangedMessage))
    #expect(decide(role: nil, text: false) == .copy(TextInserter.noTextFieldMessage))
}

@Test func inserterRestoresPasteboardOnlyWhenNotConcealed() {
    #expect(TextInserter.shouldRestore(snapshotTypes: ["public.utf8-plain-text"]))
    #expect(!TextInserter.shouldRestore(snapshotTypes: []))
    #expect(!TextInserter.shouldRestore(snapshotTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
}
