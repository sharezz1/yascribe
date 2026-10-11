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

    public init(providerID: UUID, model: String, role: Role, works: Bool = false, failure: String? = nil,
                shape: ASRShape? = nil, languageHandling: LanguageHandling? = nil, embeddingDimension: Int? = nil,
                checkedAt: Date = Date()) {
        self.providerID = providerID
        self.model = model
        self.role = role
        self.works = works
        self.failure = failure
        self.shape = shape
        self.languageHandling = languageHandling
        self.embeddingDimension = embeddingDimension
        self.checkedAt = checkedAt
    }
}

/// Sonda: lista to wygoda, **sonda to autorytet**, wpisanie z ręki to wyjście
/// awaryjne (spec fazy 1, §4). Nie wiemy z góry, który model co potrafi —
/// sprawdzamy żądaniem. Ollama nie przejdzie sondy ASR, bo nie umie, a nie
/// dlatego, że ktoś to wpisał w kod.
public struct ProbeRunner: Sendable {
    public let client: OpenAICompatibleClient

    public init(client: OpenAICompatibleClient) { self.client = client }

    public func probe(model: String, role: Role, language: LanguageCode?, now: Date = Date()) async -> ProbeResult {
        var r = ProbeResult(providerID: client.provider.id, model: model, role: role, checkedAt: now)
        switch role {
        case .asr:
            let lang = language ?? .english
            let clip = ProbeClips.clip(for: lang) ?? ProbeClips.english
            let langParam: LanguageCode? = clip.language == lang ? lang : nil
            var failures: [String] = []
            for shape in ASRShape.allCases {
                do {
                    let t = try await client.transcribe(wav: clip.wav, model: model, language: langParam, shape: shape)
                    if ProbeClips.matches(t.text, clip) {
                        r.works = true
                        r.shape = shape
                        r.languageHandling = shape == .chatAudio ? .unknown : await classifyLanguage(model: model, language: lang)
                        return r
                    }
                    failures.append("\(shape.rawValue): unexpected text \"\(t.text.prefix(60))\"")
                } catch {
                    failures.append("\(shape.rawValue): \(error)")
                }
            }
            r.failure = failures.joined(separator: "; ")
        case .correction, .summary:
            do {
                let reply = try await client.chat(model: model, system: "You are a connectivity probe. Reply with OK.", user: "ping")
                r.works = !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !r.works { r.failure = "empty reply" }
            } catch { r.failure = "\(error)" }
        case .embedding:
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
        guard let b1 = try? await client.transcribe(wav: clip.wav, model: model, language: nil, shape: .audioTranscriptions),
              let b2 = try? await client.transcribe(wav: clip.wav, model: model, language: nil, shape: .audioTranscriptions) else {
            return .unknown
        }
        guard ProbeClips.normalize(b1.text) == ProbeClips.normalize(b2.text) else { return .unknown }
        guard let a = try? await client.transcribe(wav: clip.wav, model: model, language: language, shape: .audioTranscriptions) else {
            return .automatic // parametr języka odrzucony: ustawienia nie da się wymusić
        }
        return ProbeClips.normalize(a.text) == ProbeClips.normalize(b1.text) ? .automatic : .enforced
    }
}
