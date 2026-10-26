import Foundation
import Testing
@testable import YascribeLocalASR

@Test func throttleAdmitsFirstEventThenAtMostOnePerInterval() {
    let t = ProgressThrottle(minInterval: 0.1)
    let t0 = Date(timeIntervalSince1970: 1_000)
    #expect(t.admit(now: t0))
    #expect(!t.admit(now: t0 + 0.05))
    #expect(!t.admit(now: t0 + 0.099))
    #expect(t.admit(now: t0 + 0.1))
    #expect(!t.admit(now: t0 + 0.15)) // okno liczy się od ostatniego PRZYJĘTEGO zdarzenia
    // 7,5 tys. zdarzeń w 30 s (co 4 ms) daje najwyżej ~10/s
    let burst = ProgressThrottle(minInterval: 0.1)
    let admitted = (0..<7_500).filter { burst.admit(now: t0 + Double($0) * 0.004) }.count
    #expect(admitted <= 301)
}
