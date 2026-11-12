import AppKit
import SwiftUI
import Testing
@testable import YascribeApp

/// Pole polecenia (`EditorPromptField`, TextEditor = natywny NSScrollView): pasek przewijania ma być ukryty, gdy tekst się mieści
/// (użytkownik: „boczny pasek, który mi się nie podoba"), a pojawiać się dopiero przy przepełnieniu.
@MainActor private func mountedScrollView(text: String) async throws -> NSScrollView {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 260), styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    let host = NSHostingView(rootView: EditorPromptField(text: .constant(text), minHeight: 120).frame(width: 460, height: 200).padding(10))
    window.contentView = host
    window.orderFrontRegardless()
    func findText(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView is NSTextView { return scroll }
        return view.subviews.lazy.compactMap { findText($0) }.first
    }
    for _ in 0..<60 {
        host.layoutSubtreeIfNeeded()
        if let scroll = findText(host), scroll.autohidesScrollers { return scroll }
        try await Task.sleep(for: .milliseconds(50))
    }
    host.layoutSubtreeIfNeeded()
    return try #require(findText(host))
}

@Test @MainActor func promptFieldHidesTheScrollerWhenTheTextFits() async throws {
    let scroll = try await mountedScrollView(text: "- Be brief.")
    #expect(scroll.autohidesScrollers)
    #expect(try #require(scroll.documentView).frame.height <= scroll.contentSize.height + 1) // mieści się
    #expect(scroll.verticalScroller == nil || scroll.verticalScroller!.isHiddenOrHasHiddenAncestor)
    scroll.window?.orderOut(nil)
}

@Test @MainActor func promptFieldShowsTheScrollerWhenTheTextOverflows() async throws {
    let scroll = try await mountedScrollView(text: (0..<80).map { "- Rule \($0) of the prompt." }.joined(separator: "\n"))
    #expect(try #require(scroll.documentView).frame.height > scroll.contentSize.height) // przepełnienie
    #expect(scroll.hasVerticalScroller && !(scroll.verticalScroller?.isHiddenOrHasHiddenAncestor ?? true))
    scroll.window?.orderOut(nil)
}
