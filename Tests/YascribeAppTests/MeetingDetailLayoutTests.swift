import AppKit
import SwiftUI
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

@Test @MainActor func meetingHeaderAndTranscriptActionsStayAboveScrollingContent() async throws {
    _ = NSApplication.shared
    let data = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", data.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    defer { try? FileManager.default.removeItem(at: data) }
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let preset = Preset(name: "Test", language: .polish, asr: nil,
                        correction: RoleAssignment(providerID: provider.id, model: "test"))
    model.notes.presetFor = { _ in preset }
    let text = Transcript(utterances: (0..<100).map {
        Utterance(speaker: .them, start: Double($0), end: Double($0 + 1), text: "Line \($0)", words: [], approximateTiming: false)
    }, failedChunks: [])

    func scrollView(_ view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap { scrollView($0) }.first
    }

    func titleField(_ view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.placeholderString == "Untitled meeting" { return field }
        return view.subviews.lazy.compactMap { titleField($0) }.first
    }

    var headerHeights: [CGFloat] = []
    for width in [468.0, 720.0] {
    for corrected in [false, true] {
        let item = SessionItem(url: data.appendingPathComponent("session"), startedAt: Date(), transcript: text, runID: "run",
            corrected: corrected ? CorrectedTranscript(transcript: text, model: "test", batches: 1, failedBatches: 0, rejectedLines: 0) : nil)
        let state = MeetingViewState(); state.tab = .transcript
        let host = NSHostingView(rootView: MeetingDetailView(item: item, state: state).environment(model).frame(width: width, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        for _ in 0..<40 {
            host.layoutSubtreeIfNeeded()
            if let scroll = scrollView(host), (scroll.documentView?.frame.height ?? 0) > 400 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let title = try #require(titleField(host))
        #expect(title.bounds.height >= title.intrinsicContentSize.height)
        window.contentView = NSView()
        window.contentView = host
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        #expect(title.bounds.height >= title.intrinsicContentSize.height)
        let scroll = try #require(scrollView(host))
        let scrollFrame = host.convert(scroll.bounds, from: scroll)
        let headerHeight = host.isFlipped ? scrollFrame.minY : host.bounds.maxY - scrollFrame.maxY
        #expect(headerHeight > 100)
        #expect(headerHeight < 200)
        headerHeights.append(headerHeight)
        #expect(!scroll.hasVerticalScroller)
        let windowFrame = window.frame
        let initialY = scroll.contentView.bounds.origin.y
        scroll.contentView.scroll(to: NSPoint(x: 0, y: initialY + 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        host.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.origin.y != initialY)
        #expect(host.convert(scroll.bounds, from: scroll) == scrollFrame)
        for selection in [MeetingTab.myNotes, .summary, .transcript] {
            state.tab = selection
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            #expect(window.frame == windowFrame)
            let current = try #require(scrollView(host))
            #expect(host.convert(current.bounds, from: current) == scrollFrame)
        }
    }
    }
    #expect(headerHeights.allSatisfy { abs($0 - headerHeights[0]) < 1 })
}
