import AppKit
import SwiftUI
import Testing
@testable import YascribeApp

@Test @MainActor func fieldMenuBorderIsVisibleOnAllFourEdges() async throws {
    _ = NSApplication.shared
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let host = NSHostingView(rootView: FieldMenu(label: "Template", value: "Standard", width: 160) {
            Button("Standard") {}
        }.padding(12).background(Color.mnCard))
        host.frame = NSRect(x: 0, y: 0, width: 184, height: 52)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        func color(_ x: Int, _ y: Int) throws -> NSColor {
            try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        }
        let background = try color(Int(4 * scale), Int(4 * scale))
        func contrast(_ x: Int, _ y: Int) throws -> CGFloat {
            let sample = try color(x, y)
            return max(abs(sample.redComponent - background.redComponent),
                       abs(sample.greenComponent - background.greenComponent),
                       abs(sample.blueComponent - background.blueComponent))
        }
        let centerX = Int(92 * scale), centerY = Int(26 * scale)
        for edge in [12...14, 38...40] {
            let visible = try (Int(CGFloat(edge.lowerBound) * scale)...Int(CGFloat(edge.upperBound) * scale))
                .map { try contrast(centerX, $0) }.max() ?? 0
            #expect(visible > 0.06, "Horizontal border missing in \(appearance.rawValue)")
        }
        for edge in [12...14, 170...172] {
            let visible = try (Int(CGFloat(edge.lowerBound) * scale)...Int(CGFloat(edge.upperBound) * scale))
                .map { try contrast($0, centerY) }.max() ?? 0
            #expect(visible > 0.06, "Vertical border missing in \(appearance.rawValue)")
        }
    }
}
