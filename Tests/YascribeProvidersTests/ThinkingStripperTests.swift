import Testing
@testable import YascribeProviders

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
}

@Test func unterminatedTagInTheMiddleOfAnAnswerIsLeftUntouched() {
    let note = "# Tytuł\n- Model wypisał literalny tag <think> w odpowiedzi\n- Kolejny punkt notatki"
    #expect(ThinkingStripper.clean(note) == note)
    #expect(ThinkingStripper.clean("Odpowiedź.<think>zaczynam") == "Odpowiedź.<think>zaczynam")
    #expect(ThinkingStripper.clean("Tekst [THINK] dalej") == "Tekst [THINK] dalej")
    // zamknięty blok dalej znika, nawet gdy wcześniej stoi niedomknięty literalny tag innego rodzaju
    #expect(ThinkingStripper.clean("A [THINK] b <think>ukryte</think> c") == "A [THINK] b  c")
}

@Test func unterminatedOpenerAfterWhitespaceOrAClosedBlockIsReasoning() {
    #expect(ThinkingStripper.clean("\n  <think>zaczynam") == "")
    #expect(ThinkingStripper.clean("<think>a</think>\n<think>urwane") == "")
}

@Test func earliestOpenerWinsAndFindsItsOwnCloser() {
    #expect(ThinkingStripper.clean("[THINK]I won't write <think> here[/THINK]# Title\nBody") == "# Title\nBody")
    #expect(ThinkingStripper.clean("<think>mention [/THINK] inside</think>Reply") == "Reply")
}

@Test func orphanCloserRemovesEverythingBeforeIt() {
    #expect(ThinkingStripper.clean("rozumuję bez otwarcia\n</think>\n# Tytuł\nTreść", orphanClosers: true) == "# Tytuł\nTreść")
    #expect(ThinkingStripper.clean("hm[/THINK]Tak.", orphanClosers: true) == "Tak.")
    #expect(ThinkingStripper.clean("hm</think>", orphanClosers: true) == "")
}

@Test func orphanCloserIsIgnoredUnlessAskedFor() {
    // API (domyślnie): notatka cytująca `</think>` w środku zostaje cała — nic przed zamknięciem nie jest „rozumowaniem".
    let note = "# Notatka\n- Dodać tag </think> do filtra odpowiedzi\n- Reszta"
    #expect(ThinkingStripper.clean(note) == note)
    #expect(ThinkingStripper.clean("hm[/THINK]Tak.") == "hm[/THINK]Tak.")
    // Zamknięty blok znika zawsze, także bez `orphanClosers`.
    #expect(ThinkingStripper.clean("<think>x</think>Tak. </think> Nie.") == "Tak. </think> Nie.")
}

@Test func tagsAreCaseInsensitiveAndThinkingVariantsAreSupported() {
    #expect(ThinkingStripper.clean("<THINK>x</Think>Tak.") == "Tak.")
    #expect(ThinkingStripper.clean("[think]x[/think]Tak.") == "Tak.")
    #expect(ThinkingStripper.clean("<thinking>x</thinking>Tak.") == "Tak.")
    #expect(ThinkingStripper.clean("<thinking>urwane") == "")
}

@Test func removesBracketThinkTags() {
    #expect(ThinkingStripper.clean("[THINK]x[/THINK]Tytuł") == "Tytuł")
}

@Test func leavesPlainTextUntouched() {
    #expect(ThinkingStripper.clean("  Zwykły tekst z <b>tagiem</b> i [1] numerem.\n") == "Zwykły tekst z <b>tagiem</b> i [1] numerem.")
}
