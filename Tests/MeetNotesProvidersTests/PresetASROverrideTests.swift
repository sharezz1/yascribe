import Foundation
import Testing
@testable import MeetNotesProviders

@Suite struct PresetASROverrideTests {
    private let oldASR = RoleAssignment(providerID: UUID(), model: "microsoft/mai-transcribe-2", prompt: "stary")
    private let newASR = RoleAssignment(providerID: UUID(), model: "scribe_v2")

    private func original() -> Preset {
        Preset(name: "Polish", language: .polish, asr: oldASR,
               correction: RoleAssignment(providerID: UUID(), model: "c", prompt: "korekta"),
               summary: RoleAssignment(providerID: UUID(), model: "s"), notesLanguage: .english)
    }

    @Test func withASRReplacesOnlyASRAndLanguage() throws {
        let p = original()
        let q = p.withASR(newASR, language: .english)
        #expect(q.asr == newASR)
        #expect(q.language == .english)
        #expect(q.languageAuto == nil)
        #expect(q.id == p.id && q.name == p.name)
        #expect(q.correction == p.correction && q.summary == p.summary && q.notesLanguage == p.notesLanguage)
        // Auto tylko na wyraźne życzenie (nil), z flagą zamiast języka.
        let a = p.withASR(newASR, language: nil)
        #expect(a.language == nil && a.isAutoLanguage && a.asr == newASR)
        // Powrót z Auto do jawnego języka czyści flagę.
        #expect(a.withASR(newASR, language: .polish).languageAuto == nil)
    }

    @Test func withASRResultStillValidates() throws {
        try original().withASR(newASR, language: .english).validate()
        try original().withASR(newASR, language: nil).validate()
        #expect(throws: PresetError.missingASR) {
            try original().withASR(RoleAssignment(providerID: UUID(), model: " "), language: .english).validate()
        }
    }
}
