import Testing
import YascribeProviders

@Test func speakerSensitivityHasExpectedFaAndFb() {
    #expect(SpeakerSensitivity.allCases == [.low, .medium, .high])
    #expect(SpeakerSensitivity.low.fa == 0.07 && SpeakerSensitivity.low.fb == 0.8)
    #expect(SpeakerSensitivity.medium.fa == 0.15 && SpeakerSensitivity.medium.fb == 0.4)
    #expect(SpeakerSensitivity.high.fa == 0.30 && SpeakerSensitivity.high.fb == 0.8)
    #expect(SpeakerSensitivity.defaultValue == .medium)
}
