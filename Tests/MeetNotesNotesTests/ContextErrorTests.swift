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

@Test func cutOffNamesTheModelAndTheFix() {
    #expect(ContextError.isCutOff(ProviderError.replyCutOff))
    #expect(!ContextError.isCutOff(ProviderError.http(500, "boom")))
    let msg = ContextError.describe(model: "vendor/m", ProviderError.replyCutOff)
    #expect(msg.contains("vendor/m") && msg.contains("cut off") && msg.contains("longer context"))
}
