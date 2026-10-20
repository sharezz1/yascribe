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

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

public struct TranscriptionResult: Codable, Equatable, Sendable {
    public var text: String
    /// `nil`, gdy kształt nie daje znaczników słów (czat).
    public var words: [TranscribedWord]?

    public init(text: String, words: [TranscribedWord]?) {
        self.text = text
        self.words = words
    }
}

/// Granica ścieżki transkrypcji (runner, sonda ASR): tyle potrzebują od dostawcy. Klienta wybiera się po
/// `Provider.api` — `OpenAICompatibleClient` albo `ElevenLabsClient`. Czat i embeddingi zostają tylko
/// w `OpenAICompatibleClient`, bo ElevenLabs ich nie robi.
public protocol TranscriptionClient: Sendable {
    var provider: Provider { get }
    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult
}

/// Dialekt zgodny z OpenAI. Ollama, oMLX i LM Studio wystawiają
/// `/v1/*`, więc natywny dialekt Ollamy nie jest potrzebny (odstępstwo od §3 speca,
/// YAGNI). Transkrypcja: ciało JSON z audio w base64 — tak, jak w wywołaniu
/// z rozdz. 11 dla OpenRoutera. ElevenLabs bezpośrednio — `ElevenLabsClient`.
public struct OpenAICompatibleClient: TranscriptionClient {
    public let provider: Provider
    public let key: String?
    public let http: any HTTPClient

    public init(provider: Provider, key: String?, http: any HTTPClient = URLSessionHTTPClient()) {
        self.provider = provider
        self.key = key
        self.http = http
    }

    func request(_ path: String, method: String = "POST", query: [URLQueryItem] = [], body: [String: Any]? = nil,
                 timeout: Double = 120) throws -> URLRequest {
        var comps = URLComponents(url: provider.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var r = URLRequest(url: comps.url!)
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
        guard let obj = try JSONSerialization.jsonObject(with: try checkedBody(data, resp, key: key)) as? [String: Any] else {
            throw ProviderError.badResponse("not a JSON object")
        }
        return obj
    }

    /// `output` = modalność wyjścia (`"transcription"`, `"embeddings"`). OpenRouter filtruje po stronie serwera;
    /// dostawca, który parametru nie zna, odrzuci go (400/422 → ponawiamy RAZ bez niego) albo zignoruje (200 z pełną
    /// listą). Dlatego lokalny filtr działa zawsze, gdy odpowiedź niesie modalności; model bez modalności zostaje.
    public func listModels(output: String? = nil) async throws -> [ModelInfo] {
        let items = output.map { [URLQueryItem(name: "output_modalities", value: $0)] } ?? []
        let obj: [String: Any]
        do {
            obj = try await json(try request("models", method: "GET", query: items, timeout: 30))
        } catch ProviderError.http(let status, _) where output != nil && (status == 400 || status == 422) {
            obj = try await json(try request("models", method: "GET", timeout: 30))
        }
        guard let data = obj["data"] as? [[String: Any]] else { throw ProviderError.badResponse("no data[]") }
        let all: [ModelInfo] = data.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let arch = m["architecture"] as? [String: Any]
            return ModelInfo(id: id, inputModalities: arch?["input_modalities"] as? [String],
                             outputModalities: arch?["output_modalities"] as? [String])
        }
        guard let output else { return all }
        return all.filter { $0.outputModalities.map { $0.contains(output) } ?? true }
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

    /// Obrona przed cichym obcięciem wejścia przez lokalny serwer (Ollama + bonsai-2: prompt dłuższy niż kontekst → HTTP 200,
    /// zostaje 4 pierwsze tokeny i ogon). Znaki promptu na token zwrócony w `usage.prompt_tokens`: zmierzone normalnie 2,8–3,3,
    /// przy obcięciu 6,6–14,8. Powyżej tej granicy `chat` rzuca `.inputTruncated`.
    static let truncationRatio = 5.0
    /// Poniżej tylu znaków (system + user) nie sprawdzamy (np. sonda „ping"): stały narzut szablonu czatu zawyża iloraz.
    static let truncationMinChars = 4_000

    /// `timeout` = limit transportowy żądania (bezczynność łącza; bez streamu serwer milczy do końca generacji).
    /// Lokalny serwer dostaje `reasoning_effort: "none"` (model „thinking" zjada kontekst — S2); gdy go odrzuci
    /// (400/422 z „reasoning" albo „think"), jedno ponowienie bez pola. `finish_reason == "length"` = błąd (wyjście ucięte),
    /// nigdy sukces. Wspólny `chatContent` (ASR przez czat) zostaje bez zmian.
    public func chat(model: String, system: String, user: String, timeout: Double = 120, maxTokens: Int? = nil,
                     temperature: Double? = nil) async throws -> String {
        var body: [String: Any] = ["model": model, "messages": [["role": "system", "content": system],
                                                                ["role": "user", "content": user]]]
        if let maxTokens { body["max_tokens"] = maxTokens }
        if let temperature { body["temperature"] = temperature }
        let obj: [String: Any]
        if provider.isLocal {
            body["reasoning_effort"] = "none"
            do {
                obj = try await json(try request("chat/completions", body: body, timeout: timeout))
            } catch ProviderError.http(let status, let text) where (status == 400 || status == 422) && ["reasoning", "think"].contains(where: text.lowercased().contains) {
                body["reasoning_effort"] = nil
                obj = try await json(try request("chat/completions", body: body, timeout: timeout))
            }
        } else {
            obj = try await json(try request("chat/completions", body: body, timeout: timeout))
        }
        // Tylko lokalnie i tylko gdy `usage.prompt_tokens` jest liczbą > 0 (brak/zero = nic nie wiemy, bez fałszywych alarmów).
        if provider.isLocal, let read = ((obj["usage"] as? [String: Any])?["prompt_tokens"] as? NSNumber)?.intValue, read > 0 {
            let sent = system.count + user.count
            if sent >= Self.truncationMinChars, Double(sent) / Double(read) > Self.truncationRatio {
                throw ProviderError.inputTruncated(sentChars: sent, readTokens: read)
            }
        }
        if ((obj["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String) == "length" { throw ProviderError.replyCutOff }
        let reply = ThinkingStripper.clean(try Self.chatContent(obj), orphanClosers: provider.isLocal)
        guard !reply.isEmpty else { throw ProviderError.badResponse("empty reply") }
        return reply
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
