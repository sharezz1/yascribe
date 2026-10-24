import Foundation
import Testing
@testable import MeetNotesProviders

@Test func displayStripsVendorPrefixFromApiName() {
    #expect(ModelName.display(id: "deepseek/deepseek-v4.1-flash", apiName: "DeepSeek: V4.1 Flash") == "V4.1 Flash")
}

@Test func displayKeepsOnlyFirstPrefix() {
    #expect(ModelName.display(id: "qwen/qwen3-8b", apiName: "Qwen: Qwen3: 8B") == "Qwen3: 8B")
}

@Test func displayUsesWholeApiNameWithoutColon() {
    #expect(ModelName.display(id: "nvidia/parakeet-tdt", apiName: "Parakeet TDT") == "Parakeet TDT")
}

@Test func displayFallsBackToIdTail() {
    #expect(ModelName.display(id: "nvidia/parakeet-tdt-0.6b-v3", apiName: nil) == "parakeet-tdt-0.6b-v3")
    #expect(ModelName.display(id: "nvidia/parakeet-tdt-0.6b-v3", apiName: "  ") == "parakeet-tdt-0.6b-v3")
}

@Test func displayKeepsLocalIds() {
    #expect(ModelName.display(id: "qwen3:8b", apiName: nil) == "qwen3:8b")
    #expect(ModelName.display(id: "hf.co/org/model:Q4", apiName: nil) == "model:Q4")
}

@Test func cacheRecordsNamesAndReportsChange() {
    var cache = ModelNameCache()
    #expect(cache.record([ModelInfo(id: "a/b", name: "A: B")]) == true)
    #expect(cache.record([ModelInfo(id: "a/b", name: "A: B")]) == false)
    #expect(cache.display("a/b") == "B")
    #expect(cache.display("x/y") == "y")
}

@Test func cacheIgnoresModelsWithoutName() {
    var cache = ModelNameCache()
    #expect(cache.record([ModelInfo(id: "a/b")]) == false)
}

@Test func modelInfoDecodesOldFileWithoutName() throws {
    let info = try JSONDecoder().decode(ModelInfo.self, from: Data(#"{"id":"a/b"}"#.utf8))
    #expect(info.name == nil)
}
