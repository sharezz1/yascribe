import Foundation
import Testing
@testable import YascribeProviders

private func probe(works: Bool, languageHandling: LanguageHandling? = nil) -> ProbeResult {
    ProbeResult(providerID: UUID(), model: "m", role: .asr, works: works, languageHandling: languageHandling)
}

@Test func collapsedWithoutProbeAndPrompt() {
    #expect(RoleAdvanced.startsExpanded(probe: nil, prompt: nil) == false)
}

@Test func collapsedForWorkingProbeAndBlankPrompt() {
    #expect(RoleAdvanced.startsExpanded(probe: probe(works: true, languageHandling: .enforced), prompt: "  ") == false)
}

@Test func expandedForFailedProbe() {
    #expect(RoleAdvanced.startsExpanded(probe: probe(works: false), prompt: nil) == true)
}

@Test func expandedForUnknownLanguageHandling() {
    #expect(RoleAdvanced.startsExpanded(probe: probe(works: true, languageHandling: .unknown), prompt: nil) == true)
}

@Test func expandedForAutomaticLanguageHandling() {
    #expect(RoleAdvanced.startsExpanded(probe: probe(works: true, languageHandling: .automatic), prompt: nil) == true)
}

@Test func expandedForNonEmptyPrompt() {
    #expect(RoleAdvanced.startsExpanded(probe: nil, prompt: "Keep product names") == true)
}
