import Foundation
import CryptoKit
import YascribeProviders
import YascribeTranscription

public enum Overview {
    public static func fingerprint(_ transcript: Transcript?) -> String? {
        guard let transcript else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(transcript) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func cached(_ meta: NoteMeta, runID: String?, transcript: Transcript?, correctedTranscript: Transcript? = nil) -> String? {
        guard let runID, meta.overviewRunID == runID, let fingerprint = fingerprint(transcript),
              meta.overviewTranscriptFingerprint == fingerprint,
              meta.overviewCorrectionFingerprint == Self.fingerprint(correctedTranscript) else { return nil }
        return meta.overview
    }

    public static func sourceIsCurrent(session: URL, runID: String, transcript: Transcript, correctedTranscript: Transcript?) -> Bool {
        RunSelection.shouldPostProcess(session: session, runID: runID)
            && RunSelection.of(session: session).transcript == transcript
            && CorrectedTranscript.load(session: session, runID: runID)?.transcript == correctedTranscript
    }

    public static func clean(_ reply: String) -> String? {
        let lines = ThinkingStripper.clean(reply).components(separatedBy: "\n")
        guard let line = lines.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("```") }) else { return nil }
        let text = NoteTitle.clean(line)
        return text.isEmpty ? nil : text
    }

    public static func prompt(transcript: Transcript, notesLanguage: LanguageCode?) -> NotePrompt? {
        let lines = NotePromptBuilder.transcriptLines(transcript)
        guard !lines.isEmpty else { return nil }
        let language = notesLanguage.map { "in \($0.englishName)" } ?? "in the language that predominates in the transcript"
        return NotePrompt(system: "Describe the meeting in one short sentence \(language). Reply only with that sentence.",
                          user: AutoTitle.sample(lines))
    }

    public static func generate(client: OpenAICompatibleClient, model: String, transcript: Transcript,
                                notesLanguage: LanguageCode?, store: NotesStore, runID: String, sourceTranscript: Transcript,
                                correctedTranscript: Transcript? = nil,
                                timeout: Double, chatTimeout: Double, maxTokens: Int?,
                                stillCurrent: @Sendable () -> Bool) async -> Bool {
        guard let fingerprint = fingerprint(sourceTranscript), let p = prompt(transcript: transcript, notesLanguage: notesLanguage),
              let reply = try? await withDeadline(timeout, {
                  try await client.chat(model: model, system: p.system, user: p.user, timeout: chatTimeout,
                                        maxTokens: maxTokens, thinking: false)
              }), let text = clean(reply), stillCurrent() else { return false }
        do {
            var stored = false
            try store.updateMeta { meta in
                guard stillCurrent() else { return }
                meta.overview = text
                meta.overviewRunID = runID
                meta.overviewTranscriptFingerprint = fingerprint
                meta.overviewCorrectionFingerprint = Self.fingerprint(correctedTranscript)
                stored = true
            }
            return stored
        } catch { return false }
    }
}
