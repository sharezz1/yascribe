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
    /// Nazwa czytelna dla człowieka z `/models` (`name`); opcjonalna, bo stare pliki jej nie mają.
    public var name: String?
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
    /// true = `words` zawiera segmenty (kilka sekund, mogą przechodzić przez sklejenie fragmentów okna), więc czasy są przybliżone.
    public var segmentTiming: Bool?

    public init(text: String, words: [TranscribedWord]?, segmentTiming: Bool? = nil) {
        self.text = text
        self.words = words
        self.segmentTiming = segmentTiming
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

    /// `POST audio/transcriptions` w kształcie OpenAI: multipart z plikiem i znacznikami słów (czysta funkcja).
    func multipartTranscription(wav: Data, model: String, language: LanguageCode?, wordTimestamps: Bool = true,
                                boundary: String = "Yascribe-\(UUID().uuidString)") throws -> URLRequest {
        var r = try request("audio/transcriptions")
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var fields = [("model", model), ("response_format", "verbose_json"), ("timestamp_granularities[]", "word")]
        if let language { fields.append(("language", language.rawValue)) }
        // Rozszerzenie oMLX: bez niego Whisper oddaje same segmenty. Tylko lokalnie — API OpenAI nie zna pola.
        if provider.isLocal && wordTimestamps { fields.append(("word_timestamps", "true")) }
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields { add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n") }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav)
        add("\r\n--\(boundary)--\r\n")
        r.httpBody = body
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
                             outputModalities: arch?["output_modalities"] as? [String], name: m["name"] as? String)
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
            let shapeRejection: Set<Int> = [400, 415, 422]
            let obj: [String: Any]
            do {
                obj = try await json(try request("audio/transcriptions", body: body))
            } catch ProviderError.http(let status, let message) where shapeRejection.contains(status) {
                if status == 415 && (provider.isLocal || Self.mentionsAudioField(message)) {
                    // 415 = serwer nie przyjmuje JSON w ogóle: drugi JSON też dostałby 415, od razu multipart.
                    obj = try await multipartAfterJSONRejection(wav: wav, model: model, language: language, message: message)
                } else {
                    // Voxtral odrzuca `word` kodem 400 bez treści, więc nie da się go poznać po komunikacie: jedno ponowienie
                    // bez pola. Zostają same `segments` (bez czasów słów) — `timedUnits(obj)` bierze je jako jednostki.
                    body["timestamp_granularities"] = nil
                    do {
                        obj = try await json(try request("audio/transcriptions", body: body))
                    } catch ProviderError.http(let retryStatus, let retryMessage) where shapeRejection.contains(retryStatus)
                                && (provider.isLocal || Self.mentionsAudioField(message) || Self.mentionsAudioField(retryMessage)) {
                        // Oryginalne API OpenAI i serwery lokalne (oMLX, mlx-audio) przyjmują tylko multipart/form-data, a JSON
                        // z `input_audio` odrzucają jako brak pól. Dostawca JSON-owy (OpenRouter) z innym 400 multipartu nie dostaje.
                        obj = try await multipartAfterJSONRejection(wav: wav, model: model, language: language, message: retryMessage)
                    }
                }
            }
            guard let text = obj["text"] as? String else { throw ProviderError.badResponse("no text") }
            let timing = Self.timedUnits(obj)
            return TranscriptionResult(text: text, words: timing.units, segmentTiming: timing.segments ? true : nil)
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

    /// Komunikat odrzucenia JSON wskazuje na kształt żądania (brak pliku / nieznane `input_audio`), nie na treść.
    static func mentionsAudioField(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("file") || m.contains("input_audio")
    }

    /// Multipart po odrzuceniu JSON. Odrzucony też kształtem (400/415/422) → błąd ze statusem multipart i oboma komunikatami
    /// (sonda języka patrzy na status; komunikat multipart to zwykle prawdziwa przyczyna). 401/404/429/5xx/timeout z multipart
    /// idą dalej bez zmian, do ponowień i sondy.
    func multipartAfterJSONRejection(wav: Data, model: String, language: LanguageCode?, message: String) async throws -> [String: Any] {
        func combined(_ s: Int, _ m: String) -> ProviderError { .http(s, "\(message) | multipart \(s): \(m)") }
        do { return try await json(multipartTranscription(wav: wav, model: model, language: language)) }
        catch ProviderError.http(let s, let m) where provider.isLocal && (s == 400 || s == 422) {
            // Inny lokalny serwer może nie znać rozszerzenia oMLX `word_timestamps`: jedno ponowienie bez niego.
            do { return try await json(multipartTranscription(wav: wav, model: model, language: language, wordTimestamps: false)) }
            catch ProviderError.http(let s2, let m2) where s2 == 400 || s2 == 415 || s2 == 422 {
                throw combined(s2, m2 == m ? m2 : "\(m2) (with word_timestamps: \(m))")
            }
        } catch ProviderError.http(let s, let m) where s == 400 || s == 415 || s == 422 { throw combined(s, m) }
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
    ///
    /// `thinking: false` — dla API (nie lokalnych) wysyła `reasoning: {"enabled": false}` (OpenRouter): model „hybrydowy"
    /// (np. DeepSeek V4.1 Flash) myśli domyślnie i potrafi milczeć ponad 120 s, a keep-alive odświeża `timeoutInterval`.
    /// Dostawca, który tego pola nie przyjmuje (400/422 z „reasoning" albo „think"), dostaje jedno ponowienie bez niego.
    /// Lokalny serwer ma `reasoning_effort: "none"` zawsze (S2), więc `thinking` go nie dotyczy.
    public func chat(model: String, system: String, user: String, timeout: Double = 120, maxTokens: Int? = nil,
                     temperature: Double? = nil, thinking: Bool = true) async throws -> String {
        var body: [String: Any] = ["model": model, "messages": [["role": "system", "content": system],
                                                                ["role": "user", "content": user]]]
        if let maxTokens { body["max_tokens"] = maxTokens }
        if let temperature { body["temperature"] = temperature }
        let obj: [String: Any]
        if provider.isLocal {
            body["reasoning_effort"] = "none"
            // oMLX z modelem „thinking" (Ornith) ignoruje `reasoning_effort` i zjada cały `max_tokens` na myślenie; to pole je wyłącza.
            body["chat_template_kwargs"] = ["enable_thinking": false]
            do {
                obj = try await json(try request("chat/completions", body: body, timeout: timeout))
            } catch ProviderError.http(let status, let text) where (status == 400 || status == 422) && ["reasoning", "think"].contains(where: text.lowercased().contains) {
                body["reasoning_effort"] = nil
                body["chat_template_kwargs"] = nil
                obj = try await json(try request("chat/completions", body: body, timeout: timeout))
            }
        } else if !thinking {
            body["reasoning"] = ["enabled": false]
            do {
                obj = try await json(try request("chat/completions", body: body, timeout: timeout))
            } catch ProviderError.http(let status, let text) where (status == 400 || status == 422) && ["reasoning", "think"].contains(where: text.lowercased().contains) {
                body["reasoning"] = nil
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

    static func words(_ obj: [String: Any]) -> [TranscribedWord]? { timedUnits(obj).units }

    static func timedUnits(_ obj: [String: Any]) -> (units: [TranscribedWord]?, segments: Bool) {
        func parse(_ arr: [[String: Any]]) -> [TranscribedWord] {
            arr.compactMap { w in
                guard let word = w["word"] as? String, let s = (w["start"] as? NSNumber)?.doubleValue,
                      let e = (w["end"] as? NSNumber)?.doubleValue else { return nil }
                return TranscribedWord(word: word, start: s, end: e)
            }
        }
        if let top = obj["words"] as? [[String: Any]], case let ws = parse(top), !ws.isEmpty { return (ws, false) }
        guard let segs = obj["segments"] as? [[String: Any]] else { return (nil, false) }
        // Bez czasów słów (Voxtral, Whisper bez `word_timestamps`) segment z czasami jest jedną jednostką: Merger dzieli
        // okno na wypowiedzi po przerwach między segmentami, zamiast wrzucać całe okno do jednego wiersza. Segment ze
        // słowami daje słowa, segment bez nich — siebie (nic nie znika przy mieszanej odpowiedzi).
        // Segment z tekstem bez czasów → cały tekst okna z czasem przybliżonym, żeby nic nie zginęło.
        var units: [TranscribedWord] = []
        var fromSegments = false
        for seg in segs {
            let ws = (seg["words"] as? [[String: Any]]).map(parse) ?? []
            if !ws.isEmpty { units += ws; continue }
            guard let text = seg["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let unit = parse([["word": text, "start": seg["start"] ?? "", "end": seg["end"] ?? ""]]).first else { return (nil, false) }
            units.append(unit)
            fromSegments = true
        }
        return units.isEmpty ? (nil, false) : (units, fromSegments)
    }
}
