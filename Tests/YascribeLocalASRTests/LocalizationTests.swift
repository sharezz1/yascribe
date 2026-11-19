import Foundation
import Testing
@testable import YascribeLocalASR
import YascribeTranscription
import YascribeProviders

@Test func asrMessagesKeepCanonicalEnglishAndPolishFormats() throws {
    let refusal = try #require(RunGate.check(status: .invalid(reason: "config.json is missing")))
    #expect(refusal.message == "The on-device speech model failed its check: config.json is missing. Download it again.")
    #expect(ModelStatus.displayReason("config.json is missing") == "config.json is missing")
    #expect(ModelStatus.displayReason("external error") == "external error")
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/pl.lproj")))
    let reason = bundle.localizedString(forKey: "%@ is missing", value: nil, table: nil)
    #expect(String(format: reason, "config.json") == "brakuje config.json")
    let outer = bundle.localizedString(forKey: "The on-device speech model failed its check: %@. Download it again.", value: nil, table: nil)
    #expect(String(format: outer, String(format: reason, "config.json")) == "Sprawdzenie modelu mowy na tym Macu nie powiodło się: brakuje config.json. Pobierz go ponownie.")
    #expect(CloudDiarizationError.tooLong.errorDescription == "Recording too long for speaker detection.")
    do { _ = try SpeakerSensitivity.parse("bad"); Issue.record("Expected invalid sensitivity") }
    catch { #expect(error.localizedDescription == "--sensitivity bad: use low|medium|high") }
}

@Test func modelStoreDiagnosticsKeepTheOriginalCLIRepresentation() {
    let message = "Missing \"config.json\"\nTry again."
    let asr: any Error = ModelStoreError(message: message, displayMessage: "Brakuje pliku modelu.")
    let diarizer: any Error = DiarizerModelStoreError(message: message, displayMessage: "Brakuje pliku modelu mówców.")
    #expect("błąd: \(asr)\n" == "błąd: ModelStoreError(message: \"Missing \\\"config.json\\\"\\nTry again.\")\n")
    #expect("błąd: \(diarizer)\n" == "błąd: DiarizerModelStoreError(message: \"Missing \\\"config.json\\\"\\nTry again.\")\n")
    #expect(asr.localizedDescription == message && diarizer.localizedDescription == message)
}
