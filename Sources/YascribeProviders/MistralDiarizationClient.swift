import Foundation

public struct MistralDiarizationResponse: Decodable, Sendable {
    public struct Segment: Decodable, Sendable {
        public let start: Double
        public let end: Double
        public let speakerID: String
        enum CodingKeys: String, CodingKey { case start, end; case speakerID = "speaker_id" }
        public init(start: Double, end: Double, speakerID: String) { self.start = start; self.end = end; self.speakerID = speakerID }
    }
    public let segments: [Segment]
    public let totalTokens: Int
    public let promptAudioSeconds: Double?
    private struct Usage: Decodable { let total_tokens: Int; let prompt_audio_seconds: Double? }
    private enum CodingKeys: String, CodingKey { case segments, usage }
    public init(segments: [Segment], totalTokens: Int, promptAudioSeconds: Double? = nil) {
        self.segments = segments; self.totalTokens = totalTokens; self.promptAudioSeconds = promptAudioSeconds
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segments = try c.decode([Segment].self, forKey: .segments)
        let usage = try c.decode(Usage.self, forKey: .usage)
        totalTokens = usage.total_tokens; promptAudioSeconds = usage.prompt_audio_seconds
    }
}

public enum MistralDiarizationError: LocalizedError, Equatable {
    case rejectedKey, rateLimit, server(String), invalidAnswer, cutShort, network
    public var errorDescription: String? {
        switch self {
        case .rejectedKey: "Mistral rejected the API key."
        case .rateLimit: "Mistral rate limit reached. Try again later."
        case .server(let message): "Mistral: \(message)"
        case .invalidAnswer: "Mistral returned an invalid answer."
        case .cutShort: "Mistral cut the answer short."
        case .network: "Can't connect to Mistral."
        }
    }
}

public protocol MistralDiarizationService: Sendable {
    func diarize(wav: Data, model: String, language: LanguageCode?, references: [String: Data]) async throws -> MistralDiarizationResponse
}

public struct MistralDiarizationClient: MistralDiarizationService {
    public static let baseURL = URL(string: "https://api.mistral.ai/v1")!
    public let baseURL: URL
    public let key: String?
    public let http: any HTTPClient
    public init(baseURL: URL = Self.baseURL, key: String?, http: any HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL; self.key = key; self.http = http
    }
    public static func request(baseURL: URL, key: String?, wav: Data, model: String, language: LanguageCode?, references: [String: Data], boundary: String = "Yascribe-\(UUID().uuidString)") throws -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        r.httpMethod = "POST"; r.timeoutInterval = 600
        if let key { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var fields = [("model", model), ("diarize", "true"), ("timestamp_granularities", "segment")]
        if let language { fields.append(("language", language.rawValue)) }
        if !references.isEmpty {
            let json = try JSONSerialization.data(withJSONObject: references.mapValues { $0.base64EncodedString() }, options: [.sortedKeys])
            fields.append(("speaker_references", String(decoding: json, as: UTF8.self)))
        }
        var body = Data()
        func add(_ s: String) { body.append(contentsOf: s.utf8) }
        for (name, value) in fields { add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n") }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav); add("\r\n--\(boundary)--\r\n"); r.httpBody = body
        return r
    }
    public static func parse(_ data: Data) throws -> MistralDiarizationResponse {
        do { return try JSONDecoder().decode(MistralDiarizationResponse.self, from: data) }
        catch { throw MistralDiarizationError.invalidAnswer }
    }
    private func checked(_ data: Data, _ response: HTTPURLResponse) throws -> Data {
        do { return try checkedBody(data, response, key: key) }
        catch ProviderError.http(let status, let body) {
            switch status {
            case 401, 403: throw MistralDiarizationError.rejectedKey
            case 429: throw MistralDiarizationError.rateLimit
            default: throw MistralDiarizationError.server(body)
            }
        }
    }
    public func diarize(wav: Data, model: String, language: LanguageCode?, references: [String: Data]) async throws -> MistralDiarizationResponse {
        do {
            let (data, response) = try await http.send(Self.request(baseURL: baseURL, key: key, wav: wav, model: model, language: language, references: references))
            return try Self.parse(checked(data, response))
        } catch is CancellationError { throw CancellationError() }
        catch let error as MistralDiarizationError { throw error }
        catch { throw MistralDiarizationError.network }
    }
    public func verify() async -> ProviderCheck {
        guard let key, !key.isEmpty else { return .failed("No API key.") }
        var r = URLRequest(url: baseURL.appendingPathComponent("models")); r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do { let (data, response) = try await http.send(r); _ = try checked(data, response); return .verified(models: 0) }
        catch { return .failed((error as? LocalizedError)?.errorDescription ?? MistralDiarizationError.network.localizedDescription) }
    }
}
