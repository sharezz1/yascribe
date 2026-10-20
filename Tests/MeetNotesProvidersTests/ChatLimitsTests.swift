import Foundation
import Testing
@testable import MeetNotesProviders

private let local = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
private let allCalls: [ChatCall] = [.note, .correctionBatch, .title, .mapPart]

@Test func localProvidersGetLongerLimitsThanRemote() {
    for call in allCalls {
        let l = ChatLimits.for(local, call: call), r = ChatLimits.for(openRouter, call: call)
        #expect(l.soft > r.soft && l.transport > r.transport)
    }
}

@Test func localTransportIsAtLeastSoftPlus30() {
    for call in allCalls {
        let l = ChatLimits.for(local, call: call)
        #expect(l.transport >= l.soft + 30)
    }
}

@Test func localValuesMatchTheDecidedTable() {
    #expect(ChatLimits.for(local, call: .note) == ChatLimits(soft: 600, transport: 660, maxTokens: 2048, temperature: nil))
    #expect(ChatLimits.for(local, call: .correctionBatch) == ChatLimits(soft: 300, transport: 330, maxTokens: nil, temperature: 0.2))
    #expect(ChatLimits.for(local, call: .title) == ChatLimits(soft: 120, transport: 150, maxTokens: 64, temperature: nil))
    #expect(ChatLimits.for(local, call: .mapPart) == ChatLimits(soft: 300, transport: 330, maxTokens: nil, temperature: 0.2))
    #expect(ChatLimits.localNoteMaxTokens == 2048)
}

@Test func apiValuesAreUnchanged() {
    // Także LAN i tunel to „API": tylko loopback dostaje lokalne wartości.
    let lan = Provider(name: "Box", baseURL: URL(string: "http://192.168.1.5:11434/v1")!)
    for p in [openRouter, lan] {
        #expect(ChatLimits.for(p, call: .note) == ChatLimits(soft: 180, transport: 120, maxTokens: nil, temperature: nil))
        #expect(ChatLimits.for(p, call: .correctionBatch) == ChatLimits(soft: 120, transport: 120, maxTokens: nil, temperature: nil))
        #expect(ChatLimits.for(p, call: .title) == ChatLimits(soft: 60, transport: 120, maxTokens: nil, temperature: nil))
        #expect(ChatLimits.for(p, call: .mapPart) == ChatLimits(soft: 120, transport: 120, maxTokens: nil, temperature: nil))
    }
}

@Test func autoTitleGetsLocalLimitsToo() {
    let l = ChatLimits.for(local, call: .title)
    #expect(l.soft == 120 && l.transport == 150 && l.maxTokens == 64)
}
