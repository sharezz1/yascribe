import AppKit
import Testing
@testable import YascribeApp

@Test func appearanceIncludesSystemAndBothExplicitModes() {
    #expect(AppAppearance.allCases == [.system, .light, .dark])
    #expect(AppAppearance.system.native == nil)
    #expect(AppAppearance.light.native?.name == .aqua)
    #expect(AppAppearance.dark.native?.name == .darkAqua)
}
