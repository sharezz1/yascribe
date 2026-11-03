import SwiftUI
import Testing
@testable import YascribeApp

@Suite("EditorSheetFooter")
struct EditorSheetFooterTests {
    @Test func saveCancelFooterKeepsLegacyButtonsAndShortcuts() {
        let buttons = EditorSheetFooter.saveCancel.buttons
        #expect(buttons == [
            FooterButton(title: "Cancel", role: .cancel, shortcuts: [.escape]),
            FooterButton(title: "Save", role: .save, shortcuts: [.commandReturn, .commandS]),
        ])
    }

    @Test func closeOnlyFooterHasOnlyCloseWithEscape() {
        #expect(EditorSheetFooter.closeOnly.buttons == [
            FooterButton(title: "Close", role: .close, shortcuts: [.escape]),
        ])
    }

    @Test @MainActor func convenienceInitWithoutLeadingBuilds() {
        let sheet = EditorSheet(title: "Title", dirty: false, error: nil, onCancel: {}, footer: .closeOnly) {
            Text("x")
        }
        #expect(sheet.footer == .closeOnly)
    }
}
