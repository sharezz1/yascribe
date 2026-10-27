import AppKit
import Testing
@testable import YascribeNotes

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

@Test func noteIsOneAttributedTextWithParagraphStyles() {
    // D6 / odbiór T13 uwaga 4: cała notatka to jeden tekst do jednego NSTextView; układ przez style akapitu, nie spacje.
    let blocks = MarkdownBlocks.group(sample)
    let note = MarkdownBlocks.attributed(blocks)
    let paragraphs = note.string.components(separatedBy: "\n")
    #expect(paragraphs.count == blocks.count)
    #expect(paragraphs[3] == "•\tBullet A")
    func style(_ i: Int) -> NSParagraphStyle {
        let at = paragraphs[..<i].reduce(0) { $0 + ($1 as NSString).length + 1 }
        return note.attribute(.paragraphStyle, at: at, effectiveRange: nil) as! NSParagraphStyle
    }
    func font(_ i: Int) -> NSFont {
        let at = paragraphs[..<i].reduce(0) { $0 + ($1 as NSString).length + 1 }
        return note.attribute(.font, at: at, effectiveRange: nil) as! NSFont
    }
    #expect(style(2).paragraphSpacing == 16)                                  // akapit przed punktem
    #expect(style(0).minimumLineHeight == 22 && style(0).maximumLineHeight == 22)
    #expect(style(3).headIndent == 18 && style(3).paragraphSpacing == 3)      // punkt: wiszące wcięcie, odstęp między punktami
    #expect(style(4).headIndent == 36)                                        // zagnieżdżony głębiej
    #expect(style(1).paragraphSpacingBefore == 20 && style(1).paragraphSpacing == 6)
    #expect(style(0).paragraphSpacing == 0)                                   // przed nagłówkiem liczy się tylko jego 20 (jak CSS)
    let weight = (font(1).fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat
    #expect(font(1).pointSize == 15 && weight == NSFont.Weight.semibold.rawValue)
    // Pogrubienie z treści zostaje; „— uzasadnienie” w punkcie z pogrubionym początkiem idzie w kolor drugorzędny.
    let last = (note.string as NSString).range(of: "Adrian")
    #expect(NSFontManager.shared.traits(of: note.attribute(.font, at: last.location, effectiveRange: nil) as! NSFont).contains(.boldFontMask))
    let dash = (note.string as NSString).range(of: " — send")
    #expect(note.attribute(.foregroundColor, at: dash.location, effectiveRange: nil) as? NSColor == NSColor.secondaryLabelColor)
    #expect(MarkdownBlocks.attributed([]).length == 0)
}

@Test func codeBlockGroupsAsSingleBlock() {
    let blocks = MarkdownBlocks.group("```swift\nlet x = 1\n```")
    #expect(blocks.map(\.kind) == [.codeBlock(language: "swift")])
    #expect(String(blocks[0].text.characters) == "let x = 1")
}

@Test func codeBlockWithoutLanguageIsStillOneBlock() {
    let blocks = MarkdownBlocks.group("```\nhello\n```")
    #expect(blocks.map(\.kind) == [.codeBlock(language: nil)])
    #expect(String(blocks[0].text.characters) == "hello")
}

@Test func tableGroupsAsSingleBlock() {
    let blocks = MarkdownBlocks.group("| A | B |\n|---|---|\n| 1 | 2 |")
    #expect(blocks.map(\.kind) == [.table])
    let text = String(blocks[0].text.characters)
    #expect(text.contains("A") && text.contains("B") && text.contains("1") && text.contains("2"))
}

@Test func tableRendersWithSeparatorsAndBoldHeader() {
    let note = MarkdownBlocks.attributed(MarkdownBlocks.group("| A | B |\n|---|---|\n| 1 | 2 |"))
    #expect(note.string.contains("A | B"))
    #expect(note.string.contains("1 | 2"))
    let headerRange = (note.string as NSString).range(of: "A | B")
    let headerFont = note.attribute(.font, at: headerRange.location, effectiveRange: nil) as! NSFont
    #expect(NSFontManager.shared.traits(of: headerFont).contains(.boldFontMask))
}

@Test func codeBlockUsesMonospacedFontAndBackground() {
    let note = MarkdownBlocks.attributed(MarkdownBlocks.group("```swift\nlet x = 1\n```"))
    let codeRange = (note.string as NSString).range(of: "let x = 1")
    let codeFont = note.attribute(.font, at: codeRange.location, effectiveRange: nil) as! NSFont
    #expect(codeFont.isFixedPitch)
    #expect(note.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) != nil)
}
