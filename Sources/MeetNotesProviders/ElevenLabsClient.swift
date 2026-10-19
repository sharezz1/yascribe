import Foundation

/// Wybór klienta po `Provider.api` — jedno miejsce dla aplikacji (transkrypcja, sonda, test połączenia).
public extension Provider {
    func transcriptionClient(key: String?, http: any HTTPClient = URLSessionHTTPClient()) -> any TranscriptionClient {
        switch api {
        case .openAICompatible: OpenAICompatibleClient(provider: self, key: key, http: http)
        case .elevenLabs: ElevenLabsClient(provider: self, key: key, http: http)
        }
    }

    func verify(key: String?, http: any HTTPClient = URLSessionHTTPClient()) async -> ProviderCheck {
        switch api {
        case .openAICompatible: await OpenAICompatibleClient(provider: self, key: key, http: http).verify()
        case .elevenLabs: await ElevenLabsClient(provider: self, key: key, http: http).verify()
        }
    }
}

/// ElevenLabs bezpośrednio — tylko transkrypcja, Scribe v2 (decyzja użytkownika 2026-10-16, macos.md §11.5).
/// Źródła (oficjalna dokumentacja, odczyt 2026-10-16):
/// - https://elevenlabs.io/docs/api-reference/speech-to-text/convert — `POST /v1/speech-to-text`, `multipart/form-data`,
///   nagłówek `xi-api-key`; pola `model_id`, `file`, `language_code` (ISO-639-1 albo ISO-639-3; brak = autodetekcja),
///   `timestamps_granularity` (`word`), `tag_audio_events`; odpowiedź `text`, `language_code`, `words[]`
///   (`text`, `type`: word | spacing | audio_event, `start`, `end` — mogą być null, `speaker_id`, `logprob`).
///   Plik do 5 GB, co najmniej 100 ms dźwięku.
/// - https://elevenlabs.io/docs/overview/models — `scribe_v2` (wsadowy, znaczniki słów; `scribe_v1` przestarzały).
/// - https://elevenlabs.io/docs/api-reference/models/list — `GET /v1/models` (tu: tylko test klucza; lista to modele TTS).
/// - https://elevenlabs.io/docs/eleven-api/resources/errors — 401 zły klucz, 402 brak kredytów, 403 brak uprawnień, 429.
/// Bez czatu i embeddingów: korekta, podsumowanie i wyszukiwanie idą przez dostawcę OpenAI-compatible.
public struct ElevenLabsClient: TranscriptionClient {
    /// Adres dostawcy ElevenLabs w `providers.json` — z `/v1`, jak u OpenAI-compatible; ścieżki doklejamy do niego
    /// (regionalne hosty, np. `api.eu.residency.elevenlabs.io/v1`, działają tak samo).
    public static let baseURL = URL(string: "https://api.elevenlabs.io/v1")!
    public static let scribeV2 = "scribe_v2"

    public let provider: Provider
    public let key: String?
    public let http: any HTTPClient

    public init(provider: Provider, key: String?, http: any HTTPClient = URLSessionHTTPClient()) {
        self.provider = provider
        self.key = key
        self.http = http
    }

    /// Modele dla roli — stała lista, bez sieci (`/v1/models` nie wymienia modeli STT). Poza ASR pusto.
    public static func models(for role: Role) -> [ModelInfo] {
        role == .asr ? [ModelInfo(id: scribeV2, inputModalities: ["audio"], outputModalities: ["transcription"])] : []
    }

    /// Żądanie transkrypcji (czysta funkcja). Język presetu idzie wprost: `LanguageCode` to ISO-639-1, które API
    /// przyjmuje. `nil` (preset „Auto", W§2) = pole pominięte, czyli autodetekcja — jak w ścieżce OpenAI-compatible.
    public static func transcriptionRequest(baseURL: URL, key: String?, wav: Data, model: String, language: LanguageCode?,
                                            boundary: String = "MeetNotes-\(UUID().uuidString)") -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent("speech-to-text"))
        r.httpMethod = "POST"
        r.timeoutInterval = 120
        if let key { r.setValue(key, forHTTPHeaderField: "xi-api-key") }
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Mówcy są z kanałów (ja/oni), więc bez `diarize`; bez znaczników zdarzeń („(laughter)") w tekście.
        var fields = [("model_id", model), ("timestamps_granularity", "word"), ("tag_audio_events", "false")]
        if let language { fields.append(("language_code", language.rawValue)) }
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields { add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n") }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav)
        add("\r\n--\(boundary)--\r\n")
        r.httpBody = body
        return r
    }

    /// Odpowiedź → wynik jak z OpenAI-compatible. Słowa tylko `type == "word"` ze znacznikami; odstępy i zdarzenia
    /// odpadają. Bez słów → `nil` (Merger bierze wtedy tekst z przybliżonym czasem).
    public static func parse(_ data: Data) throws -> TranscriptionResult {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = obj["text"] as? String else {
            throw ProviderError.badResponse("no text")
        }
        let words: [TranscribedWord] = ((obj["words"] as? [[String: Any]]) ?? []).compactMap { w in
            guard (w["type"] as? String ?? "word") == "word", let t = w["text"] as? String,
                  let s = (w["start"] as? NSNumber)?.doubleValue, let e = (w["end"] as? NSNumber)?.doubleValue else { return nil }
            return TranscribedWord(word: t, start: s, end: e)
        }
        return TranscriptionResult(text: text, words: words.isEmpty ? nil : words)
    }

    /// Jeden kształt: multipart ze znacznikami słów. `chatAudio` odrzucamy bez sieci — sonda nie płaci drugi raz.
    public func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        guard shape == .audioTranscriptions else { throw ProviderError.badResponse("ElevenLabs has no chat audio shape") }
        let (data, resp) = try await http.send(Self.transcriptionRequest(baseURL: provider.baseURL, key: key, wav: wav,
                                                                         model: model, language: language))
        return try Self.parse(try checkedBody(data, resp, key: key))
    }

    /// Test klucza: `GET /v1/models` (2xx = klucz działa; 403 = `.limited`, klucz tylko do STT). „N models" = modele dla ról, które ElevenLabs obsługuje (1).
    public func verify() async -> ProviderCheck {
        guard let key else { return .failed(ProviderCheck.describe(ProviderError.missingKey)) }
        var r = URLRequest(url: provider.baseURL.appendingPathComponent("models"))
        r.timeoutInterval = 30
        r.setValue(key, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, resp) = try await http.send(r)
            _ = try checkedBody(data, resp, key: key)
            return .verified(models: Self.models(for: .asr).count)
        } catch ProviderError.http(403, _) {
            // Klucz z zakresem tylko speech-to-text nie czyta `/v1/models`, a transkrybuje (decyzja 2026-10-16).
            return .limited("Key works for transcription only")
        } catch ProviderError.http(404, _) {
            return .failed("Wrong address: use https://api.elevenlabs.io/v1.")
        } catch {
            return .failed(ProviderCheck.describe(error))
        }
    }
}
