import Foundation
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
@testable import MeetNotesTranscription

/// Prawdziwa sesja z dysku, zrobiona rejestratorem z próbek.
func makeSession(system: [Int16]? = nil, systemRate: Double = 16_000, systemChannels: Int = 1, mic: [Int16]? = nil,
                 micTrack: String = "mic_raw", micOffset: Double = 0) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mn-tr-\(UUID().uuidString)")
    var sources: [any AudioSource] = []
    if let system {
        sources.append(FileSource(trackID: "system", samples: system, sampleRate: systemRate, channels: systemChannels,
                                  startHostTime: 1_000_000_000, timebase: ns, chunkFrames: 1_600))
    }
    if let mic {
        sources.append(FileSource(trackID: micTrack, samples: mic, sampleRate: 16_000, channels: 1,
                                  startHostTime: 1_000_000_000 + ns.ticks(seconds: micOffset), timebase: ns, chunkFrames: 1_600))
    }
    try SessionRecorder(directory: dir, sources: sources, conditions: [], clock: ManualHostClock(), timebase: ns,
                        zeroWatch: [:]).start()
    return dir
}

/// ASR z ręki, który naprawdę „słucha": dekoduje WAV i zwraca jedno słowo na
/// każdy odcinek dźwięku, z czasem w oknie. Liczy wywołania.
final class ListeningASR: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests = 0
    let word: String
    let failWhen: @Sendable (Int) -> Bool

    init(word: String = "słowo", failWhen: @escaping @Sendable (Int) -> Bool = { _ in false }) {
        self.word = word
        self.failWhen = failWhen
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let n = lock.withLock { requests += 1; return requests }
        let url = request.url!
        if failWhen(n) {
            return (Data("{\"error\":\"boom\"}".utf8), HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let wav = Data(base64Encoded: (body["input_audio"] as! [String: Any])["data"] as! String)!
        let pcm = wav.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        var words: [[String: Any]] = []
        var runStart: Int?
        for (i, v) in pcm.enumerated() {
            if v != 0, runStart == nil { runStart = i }
            let endOfRun = runStart != nil && (i == pcm.count - 1 || (pcm[i] == 0 && pcm[min(i + 1, pcm.count - 1)] == 0 && isQuiet(pcm, from: i)))
            if endOfRun, let s = runStart {
                if i - s > 1_600 { words.append(["word": word, "start": Double(s) / 16_000, "end": Double(i) / 16_000]) }
                runStart = nil
            }
        }
        let text = words.map { $0["word"] as! String }.joined(separator: " ")
        let data = try JSONSerialization.data(withJSONObject: ["text": text, "words": words])
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func isQuiet(_ pcm: [Int16], from i: Int) -> Bool {
        let end = min(pcm.count, i + 160)
        return pcm[i..<end].allSatisfy { $0 == 0 }
    }
}

func snapshot(language: LanguageCode = .polish) throws -> RunSnapshot {
    let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    let preset = Preset(name: "Polish", language: language, asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2"))
    return try RunSnapshot(preset: preset, provider: provider, probe: nil)
}

func client(_ http: any HTTPClient) -> OpenAICompatibleClient {
    OpenAICompatibleClient(provider: Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!), key: "k", http: http)
}
