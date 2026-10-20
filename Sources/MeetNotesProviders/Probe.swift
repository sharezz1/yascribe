import Foundation

public enum Role: String, Codable, CaseIterable, Sendable {
    case asr, correction, summary, embedding
}

/// Co znaczy „język" w presecie dla danego modelu (spec fazy 1, §1.5).
public enum LanguageHandling: String, Codable, Sendable {
    /// Model przyjmuje język i się do niego stosuje (np. MAI-Transcribe-2).
    case enforced
    /// Model wykrywa język sam, dekoder przycina wynik (Parakeet przez FluidAudio — faza 2).
    case filtered
    /// Model wykrywa język sam i nic go nie przycina — ustawienie nie działa.
    case automatic
    /// Nie da się rozstrzygnąć: model niedeterministyczny albo kształt czatowy.
    case unknown
}

public struct ProbeResult: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var model: String
    public var role: Role
    public var works: Bool
    public var failure: String?
    public var shape: ASRShape?
    public var languageHandling: LanguageHandling?
    public var embeddingDimension: Int?
    public var checkedAt: Date
    /// Język, dla którego sonda ASR klasyfikowała obsługę języka. Część klucza cache.
    public var language: LanguageCode?

    public init(providerID: UUID, model: String, role: Role, works: Bool = false, failure: String? = nil,
                shape: ASRShape? = nil, languageHandling: LanguageHandling? = nil, embeddingDimension: Int? = nil,
                checkedAt: Date = Date(), language: LanguageCode? = nil) {
        self.providerID = providerID
        self.model = model
        self.role = role
        self.works = works
        self.failure = failure
        self.shape = shape
        self.languageHandling = languageHandling
        self.embeddingDimension = embeddingDimension
        self.checkedAt = checkedAt
        self.language = language
    }
}

/// Sonda: lista to wygoda, **sonda to autorytet**, wpisanie z ręki to wyjście
/// awaryjne (spec fazy 1, §4). Nie wiemy z góry, który model co potrafi —
/// sprawdzamy żądaniem. Ollama nie przejdzie sondy ASR, bo nie umie, a nie
/// dlatego, że ktoś to wpisał w kod.
public struct ProbeRunner: Sendable {
    public let client: any TranscriptionClient

    public init(client: any TranscriptionClient) { self.client = client }

    /// Czat i embeddingi ma tylko OpenAI-compatible; ElevenLabs (sam ASR) odpada bez żądania.
    private var textClient: OpenAICompatibleClient? { client as? OpenAICompatibleClient }
    private var asrOnly: String { "\(client.provider.name) does only speech-to-text." }

    public func probe(model: String, role: Role, language: LanguageCode?, now: Date = Date()) async -> ProbeResult {
        var r = ProbeResult(providerID: client.provider.id, model: model, role: role, checkedAt: now)
        switch role {
        case .asr:
            let lang = language ?? .english
            r.language = language
            let clip = ProbeClips.clip(for: lang) ?? ProbeClips.english
            let langParam: LanguageCode? = clip.language == lang ? lang : nil
            var failures: [String] = []
            for shape in ASRShape.allCases {
                do {
                    let t = try await client.transcribe(wav: clip.wav, model: model, language: langParam, shape: shape)
                    if ProbeClips.matches(t.text, clip) {
                        r.works = true
                        r.shape = shape
                        if shape == .chatAudio {
                            r.languageHandling = .unknown
                        } else if client.provider.kind == .fluidAudio {
                            r.languageHandling = .filtered // Parakeet: język tylko skryptowy; classifyLanguage nigdy nie zwraca .filtered (spec §4.2)
                        } else if let language {
                            r.languageHandling = await classifyLanguage(model: model, language: language)
                        } // bez języka (CLI bez --language) nie klasyfikujemy — wynik byłby dla angielskiego, a klucz cache to nil
                        return r
                    }
                    failures.append("\(shape.rawValue): unexpected text \"\(t.text.prefix(60))\"")
                } catch {
                    failures.append("\(shape.rawValue): \(error)")
                }
            }
            r.failure = failures.joined(separator: "; ")
        case .correction, .summary:
            guard let client = textClient else { r.failure = asrOnly; break }
            do {
                let reply = try await client.chat(model: model, system: "You are a connectivity probe. Reply with OK.", user: "ping")
                r.works = !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !r.works { r.failure = "empty reply" }
            } catch { r.failure = "\(error)" }
        case .embedding:
            guard let client = textClient else { r.failure = asrOnly; break }
            do {
                let v = try await client.embed(model: model, text: "probe")
                r.works = true
                r.embeddingDimension = v.count
            } catch { r.failure = "\(error)" }
        }
        return r
    }

    /// Sonda honorowania języka (P10). Nagranie w **innym** języku niż preset:
    /// A — z językiem presetu, B1 i B2 — bez. Na nagraniu w języku presetu wszystkie
    /// trzy dałyby to samo i model z działającym parametrem wyglądałby na
    /// „automatyczny". B1 ≠ B2 → model niedeterministyczny → nie rozstrzygamy.
    public func classifyLanguage(model: String, language: LanguageCode) async -> LanguageHandling {
        let clip = ProbeClips.mismatched(for: language)
        func run(_ lang: LanguageCode?) async -> Result<String, any Error> {
            do {
                let t = try await client.transcribe(wav: clip.wav, model: model, language: lang, shape: .audioTranscriptions)
                return .success(ProbeClips.normalize(t.text))
            } catch {
                return .failure(error)
            }
        }
        guard case .success(let b1) = await run(nil), case .success(let b2) = await run(nil), b1 == b2 else {
            return .unknown // model niedeterministyczny albo błąd bez języka
        }
        let a1 = await run(language)
        if case .failure(let e) = a1 {
            // „Automatyczny" tylko wtedy, gdy API odrzuciło sam parametr (400/422).
            // 401, 429, 500, przekroczony czas → nie wiemy (ChatGPT #5).
            if case ProviderError.http(let status, _)? = e as? ProviderError, status == 400 || status == 422 { return .automatic }
            return .unknown
        }
        guard case .success(let x1) = a1, case .success(let x2) = await run(language), x1 == x2 else {
            return .unknown // różne odpowiedzi z językiem — wymuszania nie da się stwierdzić
        }
        return x1 == b1 ? .automatic : .enforced
    }
}
