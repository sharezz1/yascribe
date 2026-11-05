import AppKit
import SwiftUI
import Testing
@testable import YascribeApp

@Test @MainActor func hiddenScrollPageIndicatorRetainsScrolling() async throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    let host = NSHostingView(rootView: ScrollPage(500, showsIndicators: false) {
        VStack { ForEach(0..<100) { Text("Meeting \($0)").frame(height: 35) } }
    })
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil); window.contentView = nil }

    func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView($0) }.first
    }
    for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        if let scroll = findScrollView(host), (scroll.documentView?.frame.height ?? 0) > 300 { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    let scroll = try #require(findScrollView(host))
    #expect(try #require(scroll.documentView).frame.height > scroll.contentSize.height)
    #expect(!scroll.hasVerticalScroller)
    #expect(scroll.verticalScroller == nil || scroll.verticalScroller!.isHiddenOrHasHiddenAncestor)
    let initialY = scroll.contentView.bounds.origin.y
    scroll.contentView.scroll(to: NSPoint(x: 0, y: initialY + 200))
    scroll.reflectScrolledClipView(scroll.contentView)
    #expect(scroll.contentView.bounds.origin.y != initialY)
}

/// TASK-90: belka zostaje przy górnej krawędzi widoku po przewinięciu długiej listy w `ScrollPage`
/// (zewnętrzna kolumna + `contentColumn`, jak w widoku spotkania).
final class BarProbe: ObservableObject { @Published var minY: CGFloat = .nan }

@Test @MainActor func pinnedBarStaysAtTopAfterScrolling() async throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    let probe = BarProbe()
    let host = NSHostingView(rootView: ScrollPage(500) {
        VStack(alignment: .leading, spacing: 0) {
            Text("Title").frame(height: 80)
            PinnedBarPage {
                Text("Improving…").frame(height: 20)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { probe.minY = $0 }
            } content: {
                LazyVStack(spacing: 0) { ForEach(0..<100) { Text("Line \($0)").frame(height: 35) } }
            }
        }
    })
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil); window.contentView = nil }

    func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView($0) }.first
    }
    for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        if let scroll = findScrollView(host), (scroll.documentView?.frame.height ?? 0) > 300, !probe.minY.isNaN { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    let scroll = try #require(findScrollView(host))
    let before = probe.minY
    #expect(before >= 80)  // nieprzewinięta: pod tytułem
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 1500))
    scroll.reflectScrolledClipView(scroll.contentView)
    for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        if probe.minY < 40 { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(probe.minY < 40)  // przypięta u góry mimo przewinięcia o 1500 pt
}
