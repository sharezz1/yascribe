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
    struct Call { let system: String; let user: String }
    private let lock = NSLock()
    private var _calls: [Call] = []
    let handler: @Sendable (Call) throws -> String
    /// Sztuczne opóźnienie odpowiedzi (anulowalne) — do testów limitu czasu.
    let delay: Duration?
    var calls: [Call] { lock.withLock { _calls } }

    init(delay: Duration? = nil, _ handler: @escaping @Sendable (Call) throws -> String) {
        self.delay = delay
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        let msgs = body["messages"] as? [[String: Any]] ?? []
        let call = Call(system: msgs.first?["content"] as? String ?? "", user: msgs.last?["content"] as? String ?? "")
        lock.withLock { _calls.append(call) }
        if let delay { try await Task.sleep(for: delay) }
        let url = request.url!
        do {
            let text = try handler(call)
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text]]]])
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        } catch let e as StubHTTPError {
            return (Data(e.body.utf8), HTTPURLResponse(url: url, statusCode: e.status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

func chatClient(_ http: any HTTPClient) -> OpenAICompatibleClient {
    OpenAICompatibleClient(provider: testProvider, key: "k", http: http)
}
