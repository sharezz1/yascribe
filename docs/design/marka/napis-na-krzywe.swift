// Zamienia napis na kontury SVG (New York, krój systemowy macOS) przez CoreText.
// Użycie: swiftc -o /tmp/napis napis-na-krzywe.swift && /tmp/napis "Yascribe" 200 -2 [italic]
// Wypisuje JSON: {"d": "<ścieżka>", "w": szerokość, "asc": wysokość kapitalika, "desc": ...}. Oś Y w dół (SVG).
import AppKit
let a = CommandLine.arguments
let text = a[1], size = CGFloat(Double(a[2])!), track = CGFloat(Double(a[3])!)
var desc = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)!
if a.count > 4 && a[4] == "italic" { desc = desc.withSymbolicTraits(.italic) }
let font = NSFont(descriptor: desc, size: size)!
let attr = NSAttributedString(string: text, attributes: [.font: font, .kern: track])
let line = CTLineCreateWithAttributedString(attr)
var d = ""
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var g = [CGGlyph](repeating: 0, count: n), p = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &g); CTRunGetPositions(run, CFRange(location: 0, length: 0), &p)
    let f = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    for i in 0..<n {
        guard let path = CTFontCreatePathForGlyph(f, g[i], nil) else { continue }
        var t = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: p[i].x, y: -p[i].y)
        guard let q = path.copy(using: &t) else { continue }
        q.applyWithBlock { e in
            let pt = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: d += String(format: "M%.1f %.1f", pt[0].x, pt[0].y)
            case .addLineToPoint: d += String(format: "L%.1f %.1f", pt[0].x, pt[0].y)
            case .addQuadCurveToPoint: d += String(format: "Q%.1f %.1f %.1f %.1f", pt[0].x, pt[0].y, pt[1].x, pt[1].y)
            case .addCurveToPoint: d += String(format: "C%.1f %.1f %.1f %.1f %.1f %.1f", pt[0].x, pt[0].y, pt[1].x, pt[1].y, pt[2].x, pt[2].y)
            case .closeSubpath: d += "Z"
            @unknown default: break
            }
        }
    }
}
let w = CTLineGetTypographicBounds(line, nil, nil, nil)
print("{\"d\": \"\(d)\", \"w\": \(w), \"cap\": \(font.capHeight), \"x\": \(font.xHeight), \"font\": \"\(font.fontName)\"}")
