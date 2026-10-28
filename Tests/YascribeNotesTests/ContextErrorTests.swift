import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes

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

@Test func apiOverflowKeepsTheArrivesLaterSentence() {
    let e = ProviderError.http(400, "{\"error\":\"This model's maximum context length is 128000 tokens\"}")
    let cloud = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    for msg in [ContextError.describe(model: "m", e), ContextError.describe(model: "m", e, provider: cloud)] {
        #expect(msg.contains("Splitting long transcripts arrives later") && !msg.contains("Context window"))
    }
}

@Test func localOverflowPointsAtContextWindow() {
    let e = ProviderError.http(400, "{\"error\":\"request (6057 tokens) exceeds the available context size (4096 tokens)\"}")
    let local = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
    for msg in [ContextError.describe(model: "vendor/m", e, provider: local), ContextError.describe(model: "vendor/m", e, isLocal: true)] {
        #expect(msg.contains("vendor/m") && msg.contains("Context window") && msg.contains("longer context"))
        #expect(!msg.contains("arrives later"))
    }
}

@Test func localCutOffPointsAtContextWindow() {
    let local = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
    for msg in [ContextError.describe(model: "vendor/m", ProviderError.replyCutOff, provider: local),
                ContextError.describe(model: "vendor/m", ProviderError.replyCutOff, isLocal: true)] {
        #expect(msg.contains("cut off") && msg.contains("Context window") && msg.contains("server's context length"))
    }
}

@Test func truncatedInputMessageNamesTheModelAndTheFix() {
    let error = ProviderError.inputTruncated(sentChars: 7_500, readTokens: 100)
    #expect(ContextError.isInputTruncated(error) && !ContextError.isCutOff(error))
    let want = "vendor/m's server cut off the start of the input — the Context window setting is higher than what the server really uses. "
        + "Lower the field or raise the server's context (e.g. OLLAMA_CONTEXT_LENGTH=16384)."
    #expect(ContextError.describe(model: "vendor/m", error) == want)
    let local = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
    #expect(ContextError.describe(model: "vendor/m", error, provider: local) == want)
}

@Test func maxTokensOutputLimitIsNotContextOverflow() {
    // Fałszywy pozytyw z przeglądu T6/D6: limit WYJŚCIA nie jest przepełnieniem kontekstu.
    let e = ProviderError.http(400, "{\"error\":{\"message\":\"max_tokens (4096) exceeds maximum (2000)\",\"type\":\"invalid_request_error\"}}")
    #expect(!ContextError.isContextOverflow(e))
}

@Test func requestEntityTooLargeIsAlwaysContextOverflow() {
    // Spec §4.1: 413 to limit rozmiaru żądania, więc zawsze przepełnienie wejścia — nawet z domyślnym HTML nginx.
    let e = ProviderError.http(413, "<html>\n<head><title>413 Request Entity Too Large</title></head>\n<body>\n<center><h1>413 Request Entity Too Large</h1></center>\n</body>\n</html>")
    #expect(ContextError.isContextOverflow(e))
}

@Test func tooManyTokensIsContextOverflow() {
    let e = ProviderError.http(422, "{\"error\":\"too many tokens\"}")
    #expect(ContextError.isContextOverflow(e))
}

@Test func contextLengthExceededIsContextOverflow() {
    let e = ProviderError.http(400, "{\"error\":\"context length exceeded\"}")
    #expect(ContextError.isContextOverflow(e))
}

@Test func htmlErrorPageIsNotContextOverflow() {
    // Strona błędu serwera przy 400/422 nie jest komunikatem modelu, nawet gdyby zawierała słowo "context".
    let e = ProviderError.http(400, "<!DOCTYPE html><html><body><h1>Bad Request: context limit</h1></body></html>")
    #expect(!ContextError.isContextOverflow(e))
}

@Test func describeIncludesBodySnippetForOverflow() {
    let body = "{\"error\":{\"message\":\"This model's maximum context length is 128000 tokens. However, your messages resulted in 128001 tokens.\",\"type\":\"invalid_request_error\"}}"
    let e = ProviderError.http(400, body)
    let msg = ContextError.describe(model: "vendor/m", e)
    #expect(msg.contains("vendor/m") && msg.contains("longer context"))
    #expect(msg.contains("maximum context length is 128000 tokens. However, your messages resulted in 128001 tokens."))
}
