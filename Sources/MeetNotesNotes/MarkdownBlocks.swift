import Foundation

public struct MarkdownBlock: Equatable {
    public enum Kind: Equatable { case heading(Int), paragraph, bullet, numbered(Int) }
    public var kind: Kind
    public var depth: Int
    public var text: AttributedString
}

/// Markdown → bloki do narysowania w SwiftUI. `AttributedString(markdown:options:)` z `.full` daje `presentationIntent`
/// (nagłówki, listy zagnieżdżone i numerowane); SwiftUI `Text` sam bloków nie rysuje, więc grupujemy `runs` po
/// identyfikatorze bloku. Sprawdzone na Command Line Tools (2026-10-14).
public enum MarkdownBlocks {
    public static func group(_ markdown: String) -> [MarkdownBlock] {
        guard let a = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) else {
            return markdown.isEmpty ? [] : [MarkdownBlock(kind: .paragraph, depth: 0, text: AttributedString(markdown))]
        }
        var blocks: [MarkdownBlock] = []
        var currentID: Int?
        for run in a.runs {
            let comps = run.presentationIntent?.components ?? []
            let id = comps.first?.identity
            let piece = AttributedString(a[run.range])
            if let id, id == currentID, !blocks.isEmpty {
                blocks[blocks.count - 1].text.append(piece)
                continue
            }
            currentID = id
            blocks.append(MarkdownBlock(kind: kind(comps), depth: depth(comps), text: piece))
        }
        return blocks
    }

    static func kind(_ comps: [PresentationIntent.IntentType]) -> MarkdownBlock.Kind {
        if case .header(let level)? = comps.first?.kind { return .heading(level) }
        var ordinal = 0
        var found = false
        for c in comps {
            switch c.kind {
            case .listItem(let n) where !found: ordinal = n; found = true
            case .orderedList where found: return .numbered(ordinal)
            case .unorderedList where found: return .bullet
            default: break
            }
        }
        return .paragraph
    }

    static func depth(_ comps: [PresentationIntent.IntentType]) -> Int {
        max(0, comps.filter { if case .listItem = $0.kind { return true } else { return false } }.count - 1)
    }
}
