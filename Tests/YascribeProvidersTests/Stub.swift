import Foundation
@testable import YascribeProviders

/// Klient HTTP z odpowiedziami z ręki. Zapisuje żądania, żeby testy mogły
/// sprawdzić, co poszło w sieć.
final class StubHTTP: HTTPClient, @unchecked Sendable {
    struct Call { let path: String; let body: [String: Any]; let headers: [String: String]; let timeout: TimeInterval }
    private let lock = NSLock()
    private(set) var calls: [Call] = []
    let respond: @Sendable (String, [String: Any]) -> (Int, Any)

    init(_ respond: @escaping @Sendable (String, [String: Any]) -> (Int, Any)) { self.respond = respond }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path + (url.query.map { "?\($0)" } ?? "") // zapytanie jest częścią „ścieżki" w testach
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        lock.withLock { calls.append(Call(path: path, body: body, headers: request.allHTTPHeaderFields ?? [:], timeout: request.timeoutInterval)) }
        let (status, obj) = respond(path, body)
        let data = try (obj as? String).map { Data($0.utf8) } ?? JSONSerialization.data(withJSONObject: obj)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

let openRouter = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)

/// Czy wysłane nagranie to polskie „raz, dwa, trzy".
func isPolishClip(_ body: [String: Any]) -> Bool {
    let audio = (body["input_audio"] as? [String: Any]) ?? (((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?
        .first { $0["type"] as? String == "input_audio" }?["input_audio"] as? [String: Any])
    return (audio?["data"] as? String) == ProbeClips.polish.wav.base64EncodedString()
}

/// Odpowiedzi stuba. Jawne typy: przy wyrażeniu warunkowym mieszającym słownik
/// i napis kompilator Swift 6.4 gubi się we wnioskowaniu typów.
func ok(_ obj: [String: Any]) -> (Int, Any) { (200, obj) }
func fail(_ status: Int, _ text: String = "{}") -> (Int, Any) { (status, text) }
func transcript(_ text: String) -> (Int, Any) { ok(["text": text]) }
func chatReply(_ text: String) -> (Int, Any) { ok(["choices": [["message": ["content": text]]]]) }
/// Odpowiedź czatu z `finish_reason` (`"length"` = serwer uciął wyjście) i opcjonalnymi dodatkowymi polami wiadomości.
func chatReply(_ text: String, finish: String?, extra: [String: Any] = [:]) -> (Int, Any) {
    var message: [String: Any] = ["content": text]
    message.merge(extra) { $1 }
    var choice: [String: Any] = ["message": message]
    choice["finish_reason"] = finish ?? NSNull()
    return ok(["choices": [choice]])
}
