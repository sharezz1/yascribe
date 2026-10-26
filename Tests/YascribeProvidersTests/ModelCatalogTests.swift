import Foundation
import Testing
@testable import YascribeProviders

private let chat = ModelInfo(id: "anthropic/claude-sonnet", inputModalities: ["text", "audio"], outputModalities: ["text"])
private let stt = ModelInfo(id: "microsoft/mai-transcribe-2", inputModalities: ["audio"], outputModalities: ["transcription"])
private let emb = ModelInfo(id: "openai/text-embedding-x", inputModalities: ["text"], outputModalities: ["embeddings"])
private let bare = ModelInfo(id: "llama3") // Ollama: lista bez modalności

@Test func eachRoleSeesOnlyItsOwnKindOfModel() {
    let all = [chat, stt, emb]
    #expect(ModelCatalog.visible(all, role: .asr, query: "").map(\.id) == [stt.id])
    #expect(ModelCatalog.visible(all, role: .embedding, query: "").map(\.id) == [emb.id])
    #expect(ModelCatalog.visible(all, role: .summary, query: "").map(\.id) == [chat.id])
    #expect(ModelCatalog.visible(all, role: .correction, query: "").map(\.id) == [chat.id])
    #expect(ModelCatalog.outputFilter(for: .asr) == "transcription")
    #expect(ModelCatalog.outputFilter(for: .embedding) == "embeddings")
    #expect(ModelCatalog.outputFilter(for: .summary) == nil)
}

@Test func searchMatchesAnyPartOfTheIdIgnoringCase() {
    let all = [chat, stt, emb]
    #expect(ModelCatalog.visible(all, role: .asr, query: "MAI").map(\.id) == [stt.id])
    #expect(ModelCatalog.visible(all, role: .asr, query: "transcribe-2").map(\.id) == [stt.id])
    #expect(ModelCatalog.visible(all, role: .asr, query: "  ").map(\.id) == [stt.id]) // same spacje = brak zapytania
    #expect(ModelCatalog.visible(all, role: .asr, query: "claude").isEmpty)
}

@Test func modelsWithoutModalitiesAreKeptForEveryRole() {
    for role in Role.allCases {
        #expect(ModelCatalog.visible([bare], role: role, query: "").map(\.id) == ["llama3"])
    }
}
