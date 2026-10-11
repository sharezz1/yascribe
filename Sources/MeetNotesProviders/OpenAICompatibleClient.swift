import Foundation

/// Kształt wywołania ASR. ASR nie ma jednego kształtu (spec fazy 1, §4.1):
/// 47 modeli czatowych przyjmuje audio przez czat, a model transkrypcyjny
/// idzie osobnym endpointem, którego nie ma w liście modeli.
public enum ASRShape: String, Codable, Sendable, CaseIterable {
    case audioTranscriptions
    case chatAudio
}

public struct ModelInfo: Codable, Equatable, Sendable {
    public var id: String
    public var inputModalities: [String]?
    public var outputModalities: [String]?
}

public struct TranscribedWord: Codable, Equatable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double
}

public struct TranscriptionResult: Codable, Equatable, Sendable {
    public var text: String
    /// `nil`, gdy kształt nie daje znaczników słów (czat).
    public var words: [TranscribedWord]?
}

/// Dialekt zgodny z OpenAI — w fazie 1 jedyny. Ollama, oMLX i LM Studio wystawiają
/// `/v1/*`, więc natywny dialekt Ollamy nie jest potrzebny (odstępstwo od §3 speca,
/// YAGNI). Transkrypcja: ciało JSON z audio w base64 — tak, jak w wywołaniu
/// z rozdz. 11 dla OpenRoutera.
public struct OpenAICompatibleClient: Sendable {
    public let provider: Provider
    public let key: String?
    public let http: any HTTPClient

    public init(provider: Provider, key: String?, http: any HTTPClient = URLSessionHTTPClient()) {
        self.provider = provider
        self.key = key
        self.http = http
    }

    func request(_ path: String, method: String = "POST", body: [String: Any]? = nil, timeout: Double = 120) throws -> URLRequest {
        var r = URLRequest(url: provider.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = timeout
        if let key { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    func json(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await http.send(req)
        guard (200..<300).contains(resp.statusCode) else {
            throw ProviderError.http(resp.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("not a JSON object")
        }
        return obj
    }

    public func listModels() async throws -> [ModelInfo] {
        let obj = try await json(try request("models", method: "GET", timeout: 30))
        guard let data = obj["data"] as? [[String: Any]] else { throw ProviderError.badResponse("no data[]") }
        return data.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let arch = m["architecture"] as? [String: Any]
            return ModelInfo(id: id, inputModalities: arch?["input_modalities"] as? [String],
                             outputModalities: arch?["output_modalities"] as? [String])
        }
    }

    /// `language == nil` tylko w sondzie honorowania języka. Profil nagrania zawsze
    /// podaje język (P7).
    public func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        let audio: [String: Any] = ["data": wav.base64EncodedString(), "format": "wav"]
        switch shape {
        case .audioTranscriptions:
            var body: [String: Any] = ["model": model, "input_audio": audio, "response_format": "verbose_json",
                                       "timestamp_granularities": ["word"]]
            if let language { body["language"] = language.rawValue }
            let obj = try await json(try request("audio/transcriptions", body: body))
            guard let text = obj["text"] as? String else { throw ProviderError.badResponse("no text") }
            return TranscriptionResult(text: text, words: Self.words(obj))
        case .chatAudio:
            let instruction = language.map { "Transcribe this audio verbatim. The language is \($0.rawValue). Output only the transcript." }
                ?? "Transcribe this audio verbatim. Output only the transcript."
            let body: [String: Any] = ["model": model, "messages": [[
                "role": "user",
                "content": [["type": "text", "text": instruction], ["type": "input_audio", "input_audio": audio]],
            ]]]
            let obj = try await json(try request("chat/completions", body: body))
            return TranscriptionResult(text: try Self.chatContent(obj), words: nil)
        }
    }

    public func chat(model: String, system: String, user: String) async throws -> String {
        let body: [String: Any] = ["model": model, "messages": [["role": "system", "content": system],
                                                                ["role": "user", "content": user]]]
        return try Self.chatContent(try await json(try request("chat/completions", body: body)))
    }

    public func embed(model: String, text: String) async throws -> [Double] {
        let obj = try await json(try request("embeddings", body: ["model": model, "input": text], timeout: 30))
        guard let data = obj["data"] as? [[String: Any]], let v = data.first?["embedding"] as? [Double], !v.isEmpty else {
            throw ProviderError.badResponse("no embedding")
        }
        return v
    }

    static func chatContent(_ obj: [String: Any]) throws -> String {
        guard let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else { throw ProviderError.badResponse("no choices[0].message.content") }
        return content
    }

    static func words(_ obj: [String: Any]) -> [TranscribedWord]? {
        func parse(_ arr: [[String: Any]]) -> [TranscribedWord] {
            arr.compactMap { w in
                guard let word = w["word"] as? String, let s = (w["start"] as? NSNumber)?.doubleValue,
                      let e = (w["end"] as? NSNumber)?.doubleValue else { return nil }
                return TranscribedWord(word: word, start: s, end: e)
            }
        }
        if let top = obj["words"] as? [[String: Any]] { return parse(top) }
        if let segs = obj["segments"] as? [[String: Any]] {
            let all = segs.flatMap { ($0["words"] as? [[String: Any]]).map(parse) ?? [] }
            return all.isEmpty ? nil : all
        }
        return nil
    }
}
