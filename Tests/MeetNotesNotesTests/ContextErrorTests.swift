import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes

@Test func contextOverflowNamesTheModel() {
    let e = ProviderError.http(400, "{\"error\":\"This model's maximum context length is 128000 tokens\"}")
    #expect(ContextError.isContextOverflow(e))
    let msg = ContextError.describe(model: "vendor/small-model", e)
    #expect(msg.contains("vendor/small-model") && msg.contains("longer context"))
}

@Test func otherErrorsKeepTheirTextAndNameTheModel() {
    let e = ProviderError.http(500, "{\"error\":\"boom\"}")
    #expect(!ContextError.isContextOverflow(e))
    let msg = ContextError.describe(model: "vendor/m", e)
    #expect(!msg.contains("longer context") && msg.contains("vendor/m") && msg.contains("500"))
}
