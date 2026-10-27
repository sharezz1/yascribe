import Foundation

public struct MarkdownBlock: Equatable {
    public enum Kind: Equatable { case heading(Int), paragraph, bullet, numbered(Int), codeBlock(language: String?), table }
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
            let id = blockID(comps)
            let piece = AttributedString(a[run.range])
            if let id, id == currentID, !blocks.isEmpty {
                blocks[blocks.count - 1].text.append(piece)
                continue
            }
            currentID = id
            blocks.append(MarkdownBlock(kind: kind(comps), depth: depth(comps), text: piece))
        }
        // Fenced code blocks carry a trailing newline before the closing fence.
        if let last = blocks.last, case .codeBlock = last.kind {
            let trimmed = String(last.text.characters).trimmingCharacters(in: .newlines)
            blocks[blocks.count - 1].text = AttributedString(trimmed)
        }
        return blocks
    }

    static func blockID(_ comps: [PresentationIntent.IntentType]) -> Int? {
        if let table = comps.first(where: { if case .table = $0.kind { return true } else { return false } }) { return table.identity }
        if let code = comps.first(where: { if case .codeBlock = $0.kind { return true } else { return false } }) { return code.identity }
        return comps.first?.identity
    }

    static func kind(_ comps: [PresentationIntent.IntentType]) -> MarkdownBlock.Kind {
        if case .header(let level)? = comps.first?.kind { return .heading(level) }
        if let code = comps.first(where: { if case .codeBlock = $0.kind { return true } else { return false } }) {
            if case .codeBlock(let language) = code.kind { return .codeBlock(language: language) }
        }
        if comps.contains(where: { if case .table = $0.kind { return true } else { return false } }) { return .table }
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
