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
    let msg = ContextError.describe(model: "vendor/m", ProviderError.replyCutOff, isLocal: true)
    #expect(msg.contains("vendor/m") && msg.contains("cut off") && msg.contains("longer context") && msg.contains("server's context length"))
}

@Test func cutOffAdviceForRemoteProvidersDoesNotMentionTheServer() {
    let msg = ContextError.describe(model: "vendor/m", ProviderError.replyCutOff)
    #expect(msg.contains("vendor/m") && msg.contains("cut off") && msg.contains("longer output limit"))
    #expect(!msg.contains("server") && !msg.contains("context length"))
}

@Test func cutOffAdviceFollowsTheProvider() {
    let local = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
    let cloud = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    #expect(ContextError.describe(model: "m", ProviderError.replyCutOff, provider: local).contains("server's context length"))
    #expect(ContextError.describe(model: "m", ProviderError.replyCutOff, provider: cloud).contains("longer output limit"))
    #expect(ContextError.describe(model: "m", ProviderError.badResponse("empty reply"), provider: local) == "m returned an empty reply.")
}

@Test func emptyReplyIsReadableForEveryProviderKind() {
    let e = ProviderError.badResponse("empty reply")
    #expect(ContextError.isEmptyReply(e) && !ContextError.isEmptyReply(ProviderError.badResponse("no text")))
    for local in [true, false] {
        #expect(ContextError.describe(model: "vendor/m", e, isLocal: local) == "vendor/m returned an empty reply.")
    }
}

@Test func localServerErrorsGetTheServerHintInsteadOfTheRawError() {
    let ollama = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
    let down = ContextError.describe(model: "m", URLError(.cannotConnectToHost), provider: ollama)
    #expect(down.contains("Ollama") && down.contains("Start it"))
    // Miękki limit czasu (`withDeadline`) to „nie odpowiedział w czasie", nigdy „serwer nie działa".
    let slow = ContextError.describe(model: "m", DeadlineExceeded(seconds: 300), provider: ollama)
    #expect(slow.contains("300 s") && !slow.contains("Start it"))
    let cloud = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    #expect(ContextError.describe(model: "m", URLError(.cannotConnectToHost), provider: cloud).contains("m failed"))
}
