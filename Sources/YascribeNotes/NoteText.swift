import AppKit

/// Typografia notatki (macos.md §11.2, makieta `ekrany-b.html` klasa `.note`). Domyślne wartości = makieta;
/// kolory podaje aplikacja (tokeny DesignSystem jako dynamiczne `NSColor`).
public struct NoteStyle {
    public var font = NSFont.systemFont(ofSize: 14)
    public var lineHeight: CGFloat = 22
    public var headingFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    public var headingLineHeight: CGFloat = 20
    public var paragraphSpacing: CGFloat = 16
    public var headingSpacingBefore: CGFloat = 20
    public var headingSpacingAfter: CGFloat = 6
    public var bulletIndent: CGFloat = 18
    /// Znacznik punktu w polu wcięcia, jak `li::marker` w CSS (makieta: ~6 pt od krawędzi).
    public var markerInset: CGFloat = 6
    public var bulletSpacing: CGFloat = 3
    public var text: NSColor = .labelColor
    public var secondary: NSColor = .secondaryLabelColor
    public var marker: NSColor = .tertiaryLabelColor
    public init() {}
}

extension MarkdownBlocks {
    /// Cała notatka jako JEDEN `NSAttributedString` do jednego `NSTextView` (D6, odbiór T13 uwaga 4: zaznaczanie przez akapity).
    /// Odstępy jak w CSS z zapadaniem marginesów: nagłówek ma `headingSpacingBefore`, a blok przed nim 0 „po”
    /// (NSParagraphStyle sumuje oba, CSS bierze większy). Punkt: znacznik + tabulator, wiszące wcięcie dla zawiniętych linii.
    /// W punkcie zaczynającym się pogrubieniem fragment od pierwszego „ — ” do końca jest w `secondary`
    /// (Next Steps: zadanie, (osoba) — uzasadnienie; reguła bez nazwy nagłówka, bo notatka bywa po polsku).
    public static func attributed(_ blocks: [MarkdownBlock], style: NoteStyle = NoteStyle()) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, b) in blocks.enumerated() {
            let next = i + 1 < blocks.count ? blocks[i + 1].kind : nil
            let p = NSMutableParagraphStyle()
            var font = style.font
            var lineHeight = style.lineHeight
            var prefix = ""
            var customBody: NSMutableAttributedString? = nil
            switch b.kind {
            case .heading:
                font = style.headingFont
                lineHeight = style.headingLineHeight
                p.paragraphSpacingBefore = i == 0 ? 0 : style.headingSpacingBefore
                p.paragraphSpacing = style.headingSpacingAfter
            case .paragraph:
                p.paragraphSpacing = style.paragraphSpacing
            case .bullet, .numbered:
                let level = CGFloat(b.depth)
                p.firstLineHeadIndent = style.bulletIndent * level + style.markerInset
                p.headIndent = style.bulletIndent * (level + 1)
                p.tabStops = [NSTextTab(textAlignment: .left, location: p.headIndent)]
                p.defaultTabInterval = style.bulletIndent
                if case .numbered(let n) = b.kind { prefix = "\(n).\t" } else { prefix = "•\t" }
                switch next {
                case .bullet?, .numbered?: p.paragraphSpacing = style.bulletSpacing
                default: p.paragraphSpacing = style.paragraphSpacing
                }
            case .codeBlock:
                p.paragraphSpacing = style.paragraphSpacing
                font = NSFont.monospacedSystemFont(ofSize: style.font.pointSize, weight: .regular)
                let code = String(b.text.characters).replacingOccurrences(of: "\n", with: "\u{2028}")
                let codeAttrs: [NSAttributedString.Key: Any] = [
                    .paragraphStyle: p,
                    .foregroundColor: style.text,
                    .font: font,
                    .backgroundColor: style.secondary.withAlphaComponent(0.12),
                    .baselineOffset: (lineHeight - (font.ascender - font.descender)) / 2
                ]
                customBody = NSMutableAttributedString(string: code, attributes: codeAttrs)
            case .table:
                p.paragraphSpacing = style.paragraphSpacing
                customBody = NSMutableAttributedString()
                let attrs: (NSFont) -> [NSAttributedString.Key: Any] = { f in
                    [.paragraphStyle: p, .foregroundColor: style.text, .font: f,
                     .baselineOffset: (lineHeight - (f.ascender - f.descender)) / 2]
                }
                var rowID: Int?
                var cellID: Int?
                var firstInRow = true
                var isHeaderRow = false
                for run in b.text.runs {
                    let comps = run.presentationIntent?.components ?? []
                    let rowComp = comps.first { comp in
                        switch comp.kind {
                        case .tableHeaderRow, .tableRow: return true
                        default: return false
                        }
                    }
                    let cellComp = comps.first { comp in
                        if case .tableCell = comp.kind { return true } else { return false }
                    }
                    if let rowComp = rowComp {
                        let currentRowID = rowComp.identity
                        if currentRowID != rowID {
                            if rowID != nil { customBody?.append(NSAttributedString(string: "\n", attributes: attrs(font))) }
                            rowID = currentRowID
                            cellID = nil
                            firstInRow = true
                            isHeaderRow = { if case .tableHeaderRow = rowComp.kind { return true } else { return false } }()
                        }
                    }
                    if let cellComp = cellComp {
                        let currentCellID = cellComp.identity
                        if currentCellID != cellID {
                            if !firstInRow { customBody?.append(NSAttributedString(string: " | ", attributes: attrs(font))) }
                            cellID = currentCellID
                            firstInRow = false
                        }
                    }
                    let s = String(b.text[run.range].characters).replacingOccurrences(of: "\n", with: "\u{2028}")
                    var f = font
                    if isHeaderRow { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
                    customBody?.append(NSAttributedString(string: s, attributes: attrs(f)))
                }
            }
            if case .heading? = next { p.paragraphSpacing = 0 }
            if next == nil { p.paragraphSpacing = 0 }
            p.minimumLineHeight = lineHeight
            p.maximumLineHeight = lineHeight
            // TextKit kładzie nadmiar interlinii nad tekstem; CSS dzieli go po równo — wyrównujemy linię bazową.
            let base: [NSAttributedString.Key: Any] = [.paragraphStyle: p, .foregroundColor: style.text,
                                                       .baselineOffset: (lineHeight - (font.ascender - font.descender)) / 2]

            let block: NSMutableAttributedString
            if let custom = customBody {
                block = custom
            } else {
                block = NSMutableAttributedString()
                if !prefix.isEmpty {
                    var a = base; a[.font] = style.font; a[.foregroundColor] = style.marker
                    block.append(NSAttributedString(string: prefix, attributes: a))
                }
                let bodyStart = block.length
                var leadingBoldEnd: Int?
                for run in b.text.runs {
                    // Twarde złamanie w bloku nie może zacząć nowego akapitu NSTextView (dostałby wcięcie i odstęp akapitu).
                    let s = String(b.text[run.range].characters).replacingOccurrences(of: "\n", with: "\u{2028}")
                    let intent = run.inlinePresentationIntent ?? []
                    var f = font
                    if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
                    if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
                    if block.length == bodyStart, intent.contains(.stronglyEmphasized) { leadingBoldEnd = bodyStart + (s as NSString).length }
                    var a = base; a[.font] = f
                    block.append(NSAttributedString(string: s, attributes: a))
                }
                if b.kind == .bullet, let from = leadingBoldEnd {
                    let r = (block.string as NSString).range(of: " — ", range: NSRange(location: from, length: block.length - from))
                    if r.location != NSNotFound {
                        block.addAttribute(.foregroundColor, value: style.secondary, range: NSRange(location: r.location, length: block.length - r.location))
                    }
                }
            }
            if next != nil { block.append(NSAttributedString(string: "\n", attributes: base.merging([.font: font]) { $1 })) }
            out.append(block)
        }
        return out
    }
}
