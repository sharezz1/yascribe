import Foundation
import MeetNotesProviders
import MeetNotesSessionFormat
@testable import MeetNotesTranscription

func utt(_ text: String, _ speaker: Speaker = .them, at start: Double = 0, flagged: Bool = false, echo: Bool = false) -> Utterance {
    Utterance(speaker: speaker, start: start, end: start + 2, text: text, words: [], approximateTiming: false,
              languageMismatch: flagged ? .english : nil, echoOfThem: echo ? true : nil)
}

func transcript(_ u: [Utterance]) -> Transcript { Transcript(utterances: u, failedChunks: []) }

func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
}

let testProvider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)

struct StubHTTPError: Error { let status: Int; let body: String }

/// Klient HTTP odpowiadający na czat z ręki; zapisuje, co poszło w sieć. Błąd HTTP: rzuć `StubHTTPError`.
final class ChatStub: HTTPClient, @unchecked Sendable {
    struct Call {
        let system: String; let user: String; var timeout: Double = 0; var maxTokens: Int?; var temperature: Double?
        /// `reasoning.enabled` z treści żądania (F20 P1); `nil` = pole nieobecne.
        var reasoningEnabled: Bool?
    }
    private let lock = NSLock()
    private var _calls: [Call] = []
    let handler: @Sendable (Call) throws -> String
    /// Sztuczne opóźnienie odpowiedzi (anulowalne) — do testów limitu czasu.
    let delay: Duration?
    /// `finish_reason` w każdej odpowiedzi (np. `"length"` = serwer uciął wyjście); `nil` = pole nieobecne.
    let finishReason: String?
    /// `finish_reason` zależny od wywołania (np. ucięta tylko jedna część mapy); ma pierwszeństwo przed `finishReason`.
    let finishReasonFor: (@Sendable (Call) -> String?)?
    /// `usage.prompt_tokens` w odpowiedzi (np. małe = serwer obciął wejście); `nil` = brak pola `usage`.
    let promptTokens: (@Sendable (Call) -> Int?)?
    var calls: [Call] { lock.withLock { _calls } }

    init(delay: Duration? = nil, finishReason: String? = nil, finishReasonFor: (@Sendable (Call) -> String?)? = nil,
         promptTokens: (@Sendable (Call) -> Int?)? = nil,
         _ handler: @escaping @Sendable (Call) throws -> String) {
        self.delay = delay
        self.finishReason = finishReason
        self.finishReasonFor = finishReasonFor
        self.promptTokens = promptTokens
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        let msgs = body["messages"] as? [[String: Any]] ?? []
        let call = Call(system: msgs.first?["content"] as? String ?? "", user: msgs.last?["content"] as? String ?? "",
                        timeout: request.timeoutInterval, maxTokens: body["max_tokens"] as? Int, temperature: body["temperature"] as? Double,
                        reasoningEnabled: (body["reasoning"] as? [String: Any])?["enabled"] as? Bool)
        lock.withLock { _calls.append(call) }
        if let delay { try await Task.sleep(for: delay) }
        let url = request.url!
        do {
            let text = try handler(call)
            var choice: [String: Any] = ["message": ["content": text]]
            if let reason = finishReasonFor?(call) ?? finishReason { choice["finish_reason"] = reason }
            var reply: [String: Any] = ["choices": [choice]]
            if let tokens = promptTokens?(call) { reply["usage"] = ["prompt_tokens": tokens] }
            let data = try JSONSerialization.data(withJSONObject: reply)
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        } catch let e as StubHTTPError {
            return (Data(e.body.utf8), HTTPURLResponse(url: url, statusCode: e.status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

let localTestProvider = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)

func chatClient(_ http: any HTTPClient) -> OpenAICompatibleClient {
    OpenAICompatibleClient(provider: testProvider, key: "k", http: http)
}


/// Klient lokalnego dostawcy (loopback) — jedyny, który dostaje budżet i map-reduce.
func localChatClient(_ http: any HTTPClient) -> OpenAICompatibleClient {
    OpenAICompatibleClient(provider: localTestProvider, key: nil, http: http)
}
