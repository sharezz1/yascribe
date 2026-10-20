import Testing
@testable import MeetNotesProviders

@Test func removesClosedBlocks() {
    #expect(ThinkingStripper.clean("<think>muszę policzyć</think>\n\n# Tytuł\nTreść") == "# Tytuł\nTreść")
}

@Test func removesMultipleBlocksAndKeepsTheAnswer() {
    let reply = "<think>a\nb</think>Pierwsza.<think>c</think> Druga."
    #expect(ThinkingStripper.clean(reply) == "Pierwsza. Druga.")
}

@Test func unterminatedThinkBlockIsAnEmptyReply() {
    #expect(ThinkingStripper.clean("<think>zaczynam") == "")
    #expect(ThinkingStripper.clean("[THINK]zaczynam i się urywa") == "")
    #expect(ThinkingStripper.clean("Odpowiedź.<think>zaczynam") == "Odpowiedź.")
}

@Test func removesBracketThinkTags() {
    #expect(ThinkingStripper.clean("[THINK]x[/THINK]Tytuł") == "Tytuł")
}

@Test func leavesPlainTextUntouched() {
    #expect(ThinkingStripper.clean("  Zwykły tekst z <b>tagiem</b> i [1] numerem.\n") == "Zwykły tekst z <b>tagiem</b> i [1] numerem.")
}
