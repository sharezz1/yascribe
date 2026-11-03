import Testing
import YascribeRecording
@testable import YascribeApp

@Test func micOnlyStreamEndingFailuresAreFatal() {
    #expect(!MicCapture.isFatal(.failed("convert failures: 3")))
    #expect(!MicCapture.isFatal(.failed("buffer list does not match")))
    #expect(MicCapture.isFatal(.failed("reopen: deviceUnavailable")))
    #expect(MicCapture.isFatal(.endOfStream))
}
