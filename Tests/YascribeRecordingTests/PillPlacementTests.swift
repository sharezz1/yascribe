import CoreGraphics
import Testing
@testable import YascribeRecording

private let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)
private let side = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

@Test func pillKeepsBottomCenterWhenResizing() {
    let anchor = CGPoint(x: 700, y: 100)
    let small = PillPlacement.frame(size: CGSize(width: 236, height: 44), bottomCenter: anchor, screens: [screen])
    let big = PillPlacement.frame(size: CGSize(width: 320, height: 250), bottomCenter: anchor, screens: [screen])
    #expect(small.midX == 700 && small.minY == 100)
    #expect(big.midX == 700 && big.minY == 100) // R5: rozwinięta rośnie na boki i w górę, środek dołu stoi
}

@Test func pillIsSlidIntoTheVisibleFrame() {
    let size = CGSize(width: 320, height: 250)
    let left = PillPlacement.frame(size: size, bottomCenter: CGPoint(x: 50, y: 100), screens: [screen])
    #expect(left.minX == 0 && left.minY == 100)
    let top = PillPlacement.frame(size: size, bottomCenter: CGPoint(x: 700, y: 800), screens: [screen])
    #expect(top.maxY == screen.maxY)
    let under = PillPlacement.frame(size: size, bottomCenter: CGPoint(x: 700, y: 0), screens: [screen])
    #expect(under.minY == screen.minY) // nie pod dokiem
}

@Test func pillPicksTheScreenWithTheLargestOverlap() {
    let f = PillPlacement.frame(size: CGSize(width: 320, height: 250), bottomCenter: CGPoint(x: 1500, y: 100), screens: [screen, side])
    #expect(f.minX == 1440 && f.minY == 100) // większość na drugim ekranie → wsunięta w niego
    let gone = PillPlacement.frame(size: CGSize(width: 320, height: 250), bottomCenter: CGPoint(x: 5000, y: 100), screens: [screen])
    #expect(screen.contains(gone)) // monitor odpięty → główny
}
