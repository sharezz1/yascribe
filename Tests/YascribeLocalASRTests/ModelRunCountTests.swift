import Testing
@testable import YascribeLocalASR

@Test func runCountStaysBusyUntilEveryRunEnds() {
    var runs = ModelRunCount()
    #expect(runs.isIdle)
    runs.begin()   // spotkanie
    runs.begin()   // dyktowanie
    runs.end()     // dyktowanie kończy się pierwsze
    #expect(!runs.isIdle)
    runs.end()
    #expect(runs.isIdle)
}

@Test func runCountEndWithoutBeginDoesNotGoNegative() {
    var runs = ModelRunCount()
    runs.end()
    runs.begin()
    #expect(!runs.isIdle)
    runs.end()
    #expect(runs.isIdle)
}
