import Foundation
import Testing
@testable import YascribeProviders

private let orFixture = #"{"words":[{"word":"w1","start":2.12,"end":2.24,"speaker":0,"speaker_label":"speaker_0"},{"word":"w2","start":2.28,"end":2.4,"speaker":0,"speaker_label":"speaker_0"},{"word":"w3","start":9.42,"end":9.5,"speaker":1,"speaker_label":"speaker_1"},{"word":"w4","start":9.54,"end":9.76,"speaker":1,"speaker_label":"speaker_1"},{"word":"w5","start":9.86,"end":10.1,"speaker":1,"speaker_label":"speaker_1"}]}"#
private let elFixture = #"{"words":[{"text":"w1","start":0.0,"end":0.62,"type":"word","speaker_id":"speaker_0"},{"text":" ","start":0.62,"end":0.62,"type":"spacing","speaker_id":"speaker_0"},{"text":"w2","start":0.66,"end":0.74,"type":"word","speaker_id":"speaker_1"},{"text":"w3","start":1.24,"end":1.28,"type":"word","speaker_id":"speaker_2"},{"text":"w4","start":1.3,"end":1.4,"type":"word","speaker_id":"speaker_2"},{"text":"w5","start":1.5,"end":1.6,"type":"word","speaker_id":"speaker_2"},{"text":"event","type":"audio_event"}]}"#

@Suite struct SpeakerCapabilityTests {
 @Test func supportsOnlyScribeV2() {
  #expect(SpeakerCapability.supports(api: .openAICompatible, model: "elevenlabs/scribe-v2"))
  #expect(!SpeakerCapability.supports(api: .openAICompatible, model: "openai/whisper-1"))
  #expect(SpeakerCapability.supports(api: .elevenLabs, model: "scribe_v2"))
  #expect(!SpeakerCapability.supports(api: .fluidAudio, model: "scribe_v2"))
 }
 @Test func openRouterDiarizeRequestShape() async throws {
  let http = StubHTTP { _, _ in (200, orFixture) }
  _ = try await OpenAICompatibleClient(provider: openRouter, key: "fake", http: http).diarize(m4a: Data([1, 2]), model: "elevenlabs/scribe-v2", language: .polish)
  let body = try #require(http.calls.first?.body)
  #expect(body["diarize"] as? Bool == true)
  #expect((body["input_audio"] as? [String: String])?["format"] == "m4a")
  #expect(body["timestamp_granularities"] as? [String] == ["word"])
 }
 @Test func elevenLabsDiarizeRequestShape() async throws {
  let http = StubHTTP { _, _ in (200, elFixture) }
  let p = Provider(name: "eleven", baseURL: ElevenLabsClient.baseURL, kind: .elevenLabs)
  _ = try await ElevenLabsClient(provider: p, key: "fake", http: http).diarize(m4a: Data([1]), model: "scribe_v2", language: .polish)
  let call = try #require(http.calls.first)
  let body = String(decoding: call.raw, as: UTF8.self)
  #expect(body.contains("name=\"diarize\"\r\n\r\ntrue"))
  #expect(body.contains("Content-Type: audio/mp4") && body.contains("filename=\"audio.m4a\""))
  #expect(call.timeout == 600)
 }
 @Test func parsesOpenRouterSpeakers() async throws {
  let http = StubHTTP { _, _ in (200, orFixture) }
  let words = try await OpenAICompatibleClient(provider: openRouter, key: nil, http: http).diarize(m4a: Data(), model: "m", language: nil)
  #expect(words.count == 5 && words[0] == DiarizedWord(speaker: "speaker_0", start: 2.12, end: 2.24) && words[2].speaker == "speaker_1")
 }
 @Test func parsesElevenLabsSkippingSpacing() async throws {
  let http = StubHTTP { _, _ in (200, elFixture) }
  let p = Provider(name: "eleven", baseURL: ElevenLabsClient.baseURL, kind: .elevenLabs)
  let words = try await ElevenLabsClient(provider: p, key: nil, http: http).diarize(m4a: Data(), model: "m", language: nil)
  #expect(words.count == 5 && words[1] == DiarizedWord(speaker: "speaker_1", start: 0.66, end: 0.74))
 }
 @Test func missingSpeakerIsBadResponse() async throws {
  let http = StubHTTP { _, _ in (200, #"{"words":[{"start":0,"end":1}]}"#) }
  await #expect(throws: ProviderError.badResponse("no speakers")) { try await OpenAICompatibleClient(provider: openRouter, key: nil, http: http).diarize(m4a: Data(), model: "m", language: nil) }
 }
 @Test func keyRedactedInError() async throws {
  let key = "secret-fake-key"
  let http = StubHTTP { _, _ in (401, "secret-fake-key") }
  do { _ = try await OpenAICompatibleClient(provider: openRouter, key: key, http: http).diarize(m4a: Data(), model: "m", language: nil); Issue.record("expected error") }
  catch { #expect(!error.localizedDescription.contains(key)) }
 }
}
