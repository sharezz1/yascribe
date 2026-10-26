import AppKit
import YascribeProviders
import SwiftUI

// Logo dostawców (docs/design/makiety/logo-dostawcow/, źródła i zasady w ZRODLA.md). SVG osadzone w kodzie:
// `scripts/bundle.sh` nie kopiuje zasobów SwiftPM, a `NSImage(data:)` czyta SVG natywnie.

private enum LogoSVG {
    /// OpenRouter „Glyph": ink na jasnym tle, cloud na ciemnym (warianty właściciela).
    static func openRouter(fill: String) -> String {
        "<svg width=\"1024\" height=\"730\" viewBox=\"0 0 1024 730\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M795.893 0C915.776 0 1012.95 97.9963 1012.95 218.88C1012.95 339.764 915.776 437.76 795.893 437.76L1011.2 654.869C1038.55 682.447 1019.18 729.6 980.504 729.6H361.77C161.97 729.6 0 566.273 0 364.8C0 163.327 161.97 0 361.77 0L795.893 0ZM361.77 145.92C241.89 145.92 144.708 243.916 144.708 364.8C144.708 485.684 241.89 583.68 361.77 583.68C481.649 583.68 578.831 485.684 578.831 364.8C578.831 243.916 481.649 145.92 361.77 145.92Z\" fill=\"\(fill)\"/></svg>"
    }
    static let openRouterInk = openRouter(fill: "#03080A")
    static let openRouterCloud = openRouter(fill: "#FCFCFE")
    /// ElevenLabs „Symbol"; rysowany jako template (kolor z `foregroundStyle`: czerń w jasnym, biel w ciemnym).
    static let elevenLabs = """
    <svg width="240" height="352" viewBox="318 262 240 352" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M468 292H528V584H468V292Z" fill="black"/><path d="M348 292H408V584H348V292Z" fill="black"/></svg>
    """
    /// Znak Yascribe (pióro między dwiema falami dźwięku) bez kafla, czarny; template (czerń w jasnym, biel w ciemnym). Geometria z
    /// `docs/design/marka/ksztalty.json` (jak `zloz-ikone.py`); plik: `docs/design/makiety/logo-dostawcow/yascribe-mark-mono.svg`.
    static let yascribe = """
    <svg width="591" height="591" viewBox="215.5 216.7 591.0 591.0" fill="black" xmlns="http://www.w3.org/2000/svg"><path d="M641.0,308.7 L603.0,340.7 L568.5,377.4 L542.4,411.4 L516.1,453.4 L494.7,495.4 L476.2,539.4 L447.2,623.4 L418.2,697.4 L412.0,715.4 L413.0,718.9 L414.0,717.4 L459.5,623.4 L510.4,503.4 L534.8,455.4 L574.7,391.4 L614.3,341.4 L643.5,309.4Z M723.7,229.4 L719.4,257.4 L707.7,303.4 L695.2,335.4 L683.4,357.4 L669.1,377.4 L655.9,391.4 L635.0,408.3 L604.9,427.4 L659.2,413.4 L649.5,443.4 L637.2,467.4 L619.0,494.3 L599.0,515.6 L573.0,533.8 L543.0,548.7 L526.6,559.4 L563.0,552.9 L573.0,552.7 L573.2,555.4 L549.0,584.8 L505.0,620.7 L476.2,649.4 L456.4,679.4 L431.9,729.4 L381.7,793.4 L379.0,795.8 L378.8,793.4 L404.3,709.4 L439.6,617.4 L445.7,595.4 L448.8,563.4 L444.4,511.4 L444.5,479.4 L452.3,441.4 L470.6,399.4 L490.4,369.4 L509.1,347.4 L537.0,321.0 L563.0,301.0 L595.0,280.9 L643.0,256.5 L693.0,236.6 L719.0,228.5Z" fill-rule="evenodd"/><rect x="215.5" y="503.0" width="31.0" height="58.8" rx="15.5"/><rect x="254.5" y="477.0" width="31.0" height="108.8" rx="15.5"/><rect x="299.5" y="445.0" width="31.0" height="168.8" rx="15.5"/><rect x="348.5" y="403.0" width="31.0" height="248.8" rx="15.5"/><rect x="396.5" y="463.0" width="31.0" height="130.8" rx="15.5"/><rect x="590.5" y="535.0" width="31.0" height="68.8" rx="15.5"/><rect x="634.5" y="493.0" width="31.0" height="134.8" rx="15.5"/><rect x="682.5" y="441.0" width="31.0" height="218.8" rx="15.5"/><rect x="729.5" y="475.0" width="31.0" height="132.8" rx="15.5"/><rect x="775.5" y="505.0" width="31.0" height="64.8" rx="15.5"/></svg>
    """
    /// llama.cpp (ggml-org/llama.cpp, `media/llama1-icon.svg`, MIT): sama lama bez ciemnego kafla, jednobarwna (template).
    static let llamaCpp = """
    <svg width="212" height="212" viewBox="20 13 212 212" fill="black" xmlns="http://www.w3.org/2000/svg"><g transform="translate(-995.51066,-129.70875)"><path d="m 1163.3,226.8 -13.5,24 c -17.8,-13.7 -44.2,-15.7 -62,-1 -28.7,23.7 -26.7,78.5 18,78.8 12.5,0 23.1,-5.9 34.5,-9.8 l 6,23.9 c -10.1,4.7 -20.4,9.5 -31.5,11 -101.2,13.8 -95.4,-132.3 -3.9,-139.9 19.2,-1.6 36.1,3.4 52.5,13 z" /> <path d="m 1093.4,203.8 c -15.4,4.6 -29.7,13.1 -40.5,25 -2,-24.2 3.4,-73.1 30.3,-82.7 4,-1.4 17.7,-4.9 17.3,2.2 -0.4,7.1 -9.9,19.3 -12.2,25.9 -4,11.6 -0.3,19.6 5.2,29.7 z" /> <polygon points="1131.4,307.8 1116.4,307.8 1116.4,290.8 1099.4,290.8 1099.4,276.8 1114.9,276.8 1116.4,275.3 1116.4,258.8 1131.4,258.8 1131.4,276.8 1147.4,276.8 1147.4,290.8 1131.4,290.8 " /> <polygon points="1186.4,290.8 1186.4,307.8 1171.4,307.8 1171.4,290.8 1155.4,290.8 1155.4,276.8 1171.4,276.8 1171.4,258.8 1186.4,258.8 1186.4,275.3 1187.9,276.8 1203.4,276.8 1203.4,290.8 " /> <path d="m 1142.3,156.9 c 2,3 -9.3,15.9 -11.1,19.2 -5.2,9.8 -1.7,15.4 2.2,24.7 -11.3,-1.7 -21.8,-0.3 -33,1 2.5,-21.5 14.6,-52.8 41.9,-44.9 z" /></g></svg>
    """
    /// oMLX (jundot/omlx, `menubar-filled.svg`, Apache-2.0): glif paska menu, już jednobarwny (template).
    static let omlx = """
    <svg width="480" height="480" viewBox="-6.5 31.4 480 480" xmlns="http://www.w3.org/2000/svg"><g transform="translate(0.000000,497.000000) scale(0.100000,-0.100000)" fill="#000000" stroke="none"> <path d="M2250 4483 c-99 -12 -288 -56 -381 -88 -225 -78 -410 -192 -591 -364 -131 -125 -215 -238 -292 -396 -133 -270 -175 -466 -211 -980 -32 -460 -133 -999 -267 -1430 -104 -333 -318 -823 -479 -1097 -19 -32 -29 -63 -29 -88 l0 -40 649 0 649 0 83 73 c234 205 408 493 482 797 47 194 59 305 55 540 -3 193 -1 219 15 243 40 61 102 77 167 45 68 -35 96 -99 111 -253 29 -312 -52 -727 -201 -1028 -54 -109 -152 -260 -229 -352 l-50 -60 1401 -3 c771 -1 1404 0 1407 4 12 11 18 244 10 384 -26 473 -154 873 -529 1650 -65 135 -128 274 -140 310 -31 91 -39 270 -15 360 61 234 231 401 647 634 182 102 214 141 167 200 -29 36 -40 40 -281 92 -391 84 -459 117 -673 324 -82 80 -181 168 -220 197 -201 148 -438 254 -681 304 -78 16 -144 21 -319 24 -121 2 -236 1 -255 -2z m951 -841 c142 -74 162 -269 39 -374 -94 -81 -226 -71 -317 24 -42 43 -63 96 -63 155 1 171 185 276 341 195z"/> </g></svg>
    """
    /// Ollama (@lobehub/icons-static-svg, MIT): `currentColor` i `1em` zastąpione stałymi — template.
    static let ollama = "<svg fill=\"black\" fill-rule=\"evenodd\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 7.905 1.09c .216 .085 .411 .225 .588 .41 .295 .306 .544 .744 .734 1.263 .191 .522 .315 1.1 .362 1.68a 5.054 5.054 0 0 1 2.049 -.636l .051 -.004c .87 -.07 1.73 .087 2.48 .474 .101 .053 .2 .11 .297 .17 .05 -.569 .172 -1.134 .36 -1.644 .19 -.52 .439 -.957 .733 -1.264a 1.67 1.67 0 0 1 .589 -.41c .257 -.1 .53 -.118 .796 -.042 .401 .114 .745 .368 1.016 .737 .248 .337 .434 .769 .561 1.287 .23 .934 .27 2.163 .115 3.645l .053 .04 .026 .019c .757 .576 1.284 1.397 1.563 2.35 .435 1.487 .216 3.155 -.534 4.088l -.018 .021 .002 .003c .417 .762 .67 1.567 .724 2.4l .002 .03c .064 1.065 -.2 2.137 -.814 3.19l -.007 .01 .01 .024c .472 1.157 .62 2.322 .438 3.486l -.006 .039a .651 .651 0 0 1 -.747 .536 .648 .648 0 0 1 -.54 -.742c .167 -1.033 .01 -2.069 -.48 -3.123a .643 .643 0 0 1 .04 -.617l .004 -.006c .604 -.924 .854 -1.83 .8 -2.72 -.046 -.779 -.325 -1.544 -.8 -2.273a .644 .644 0 0 1 .18 -.886l .009 -.006c .243 -.159 .467 -.565 .58 -1.12a 4.229 4.229 0 0 0 -.095 -1.974c -.205 -.7 -.58 -1.284 -1.105 -1.683 -.595 -.454 -1.383 -.673 -2.38 -.61a .653 .653 0 0 1 -.632 -.371c -.314 -.665 -.772 -1.141 -1.343 -1.436a 3.288 3.288 0 0 0 -1.772 -.332c -1.245 .099 -2.343 .801 -2.67 1.686a .652 .652 0 0 1 -.61 .425c -1.067 .002 -1.893 .252 -2.497 .703 -.522 .39 -.878 .935 -1.066 1.588a 4.07 4.07 0 0 0 -.068 1.886c .112 .558 .331 1.02 .582 1.269l .008 .007c .212 .207 .257 .53 .109 .785 -.36 .622 -.629 1.549 -.673 2.44 -.05 1.018 .186 1.902 .719 2.536l .016 .019a .643 .643 0 0 1 .095 .69c -.576 1.236 -.753 2.252 -.562 3.052a .652 .652 0 0 1 -1.269 .298c -.243 -1.018 -.078 -2.184 .473 -3.498l .014 -.035 -.008 -.012a 4.339 4.339 0 0 1 -.598 -1.309l -.005 -.019a 5.764 5.764 0 0 1 -.177 -1.785c .044 -.91 .278 -1.842 .622 -2.59l .012 -.026 -.002 -.002c -.293 -.418 -.51 -.953 -.63 -1.545l -.005 -.024a 5.352 5.352 0 0 1 .093 -2.49c .262 -.915 .777 -1.701 1.536 -2.269 .06 -.045 .123 -.09 .186 -.132 -.159 -1.493 -.119 -2.73 .112 -3.67 .127 -.518 .314 -.95 .562 -1.287 .27 -.368 .614 -.622 1.015 -.737 .266 -.076 .54 -.059 .797 .042zm 4.116 9.09c .936 0 1.8 .313 2.446 .855 .63 .527 1.005 1.235 1.005 1.94 0 .888 -.406 1.58 -1.133 2.022 -.62 .375 -1.451 .557 -2.403 .557 -1.009 0 -1.871 -.259 -2.493 -.734 -.617 -.47 -.963 -1.13 -.963 -1.845 0 -.707 .398 -1.417 1.056 -1.946 .668 -.537 1.55 -.849 2.485 -.849zm 0 .896a 3.07 3.07 0 0 0 -1.916 .65c -.461 .37 -.722 .835 -.722 1.25 0 .428 .21 .829 .61 1.134 .455 .347 1.124 .548 1.943 .548 .799 0 1.473 -.147 1.932 -.426 .463 -.28 .7 -.686 .7 -1.257 0 -.423 -.246 -.89 -.683 -1.256 -.484 -.405 -1.14 -.643 -1.864 -.643zm .662 1.21l .004 .004c .12 .151 .095 .37 -.056 .49l -.292 .23v .446a .375 .375 0 0 1 -.376 .373 .375 .375 0 0 1 -.376 -.373v -.46l -.271 -.218a .347 .347 0 0 1 -.052 -.49 .353 .353 0 0 1 .494 -.051l .215 .172 .22 -.174a .353 .353 0 0 1 .49 .051zm -5.04 -1.919c .478 0 .867 .39 .867 .871a .87 .87 0 0 1 -.868 .871 .87 .87 0 0 1 -.867 -.87 .87 .87 0 0 1 .867 -.872zm 8.706 0c .48 0 .868 .39 .868 .871a .87 .87 0 0 1 -.868 .871 .87 .87 0 0 1 -.867 -.87 .87 .87 0 0 1 .867 -.872zM 7.44 2.3l -.003 .002a .659 .659 0 0 0 -.285 .238l -.005 .006c -.138 .189 -.258 .467 -.348 .832 -.17 .692 -.216 1.631 -.124 2.782 .43 -.128 .899 -.208 1.404 -.237l .01 -.001 .019 -.034c .046 -.082 .095 -.161 .148 -.239 .123 -.771 .022 -1.692 -.253 -2.444 -.134 -.364 -.297 -.65 -.453 -.813a .628 .628 0 0 0 -.107 -.09L 7.44 2.3zm 9.174 .04l -.002 .001a .628 .628 0 0 0 -.107 .09c -.156 .163 -.32 .45 -.453 .814 -.29 .794 -.387 1.776 -.23 2.572l .058 .097 .008 .014h .03a 5.184 5.184 0 0 1 1.466 .212c .086 -1.124 .038 -2.043 -.128 -2.722 -.09 -.365 -.21 -.643 -.349 -.832l -.004 -.006a .659 .659 0 0 0 -.285 -.239h -.004z\"/></svg>"
}

private func image(_ svg: String, template: Bool) -> NSImage? {
    let i = NSImage(data: Data(svg.utf8))
    i?.isTemplate = template
    return i
}

/// Logo w kafelku 32 pt (promień 8, obwódka `line`); Custom endpoint to SF Symbol. `size` = bok kafelka.
struct ProviderLogo: View {
    @Environment(\.colorScheme) private var scheme
    /// `nil` = własny adres (SF Symbol serwera); `.custom` = wiersz „Custom endpoint" (plus).
    let preset: ProviderPreset?
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(.mnField)
            .overlay(RoundedRectangle(cornerRadius: size / 4, style: .continuous).strokeBorder(.mnLine, lineWidth: 0.5))
            .frame(width: size, height: size)
            .overlay { glyph }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        switch preset?.id {
        case "openrouter": mark(image(scheme == .dark ? LogoSVG.openRouterCloud : LogoSVG.openRouterInk, template: false), template: false, scale: 0.5)
        case "elevenlabs": mark(image(LogoSVG.elevenLabs, template: true), template: true, scale: 0.56)
        case "ollama": mark(image(LogoSVG.ollama, template: true), template: true, scale: 0.56)
        case "llamacpp": mark(image(LogoSVG.llamaCpp, template: true), template: true, scale: 0.56)
        case "omlx": mark(image(LogoSVG.omlx, template: true), template: true, scale: 0.5)
        // Model Yascribe (Parakeet w procesie) to nie dostawca: znak aplikacji, czarno-biały (F20 P3). Używa go karta „Yascribe model".
        case "on-this-mac": mark(image(LogoSVG.yascribe, template: true), template: true, scale: 0.6)
        case "custom": Image(systemName: "plus").font(.system(size: size * 0.4)).foregroundStyle(.mnText2)
        default: Image(systemName: "server.rack").font(.system(size: size * 0.4)).foregroundStyle(.mnText2)
        }
    }

    @ViewBuilder private func mark(_ img: NSImage?, template: Bool, scale: CGFloat) -> some View {
        if let img {
            Image(nsImage: img).renderingMode(template ? .template : .original).resizable().scaledToFit()
                .foregroundStyle(.mnText).frame(width: size * scale, height: size * scale)
        }
    }
}
