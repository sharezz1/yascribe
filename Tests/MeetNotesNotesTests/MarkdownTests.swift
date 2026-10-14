import Foundation
import Testing
@testable import MeetNotesNotes

private let sample = """
Intro line.

## Topic one
Para with **bold**.

- Bullet A
  - Nested A1
- Bullet B

1. First
2. Second

## Next Steps
- **Adrian** — send forecast
"""

@Test func markdownBlocksGroupHeadingsParagraphsAndLists() {
    let blocks = MarkdownBlocks.group(sample)
    #expect(blocks.map(\.kind) == [.paragraph, .heading(2), .paragraph, .bullet, .bullet, .bullet,
                                   .numbered(1), .numbered(2), .heading(2), .bullet])
    #expect(String(blocks[9].text.characters) == "Adrian — send forecast") // pogrubienie nie dzieli bloku
}

@Test func nestedListKeepsDepth() {
    #expect(MarkdownBlocks.group(sample).map(\.depth) == [0, 0, 0, 0, 1, 0, 0, 0, 0, 0])
}

@Test func orderedListKeepsNumbers() {
    let blocks = MarkdownBlocks.group("1. First\n2. Second\n3. Third")
    #expect(blocks.map(\.kind) == [.numbered(1), .numbered(2), .numbered(3)])
}
