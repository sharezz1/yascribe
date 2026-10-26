import Foundation

/// Kod `OSStatus` → zdanie dla człowieka. Czteroznakowe kody (`'wht?'`) rozpoznajemy po bajtach; resztę podajemy liczbą.
public enum OSStatusText {
    public static func fourCC(_ code: Int) -> String? {
        let u = UInt32(truncatingIfNeeded: code)
        let bytes = [24, 16, 8, 0].map { UInt8((u >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func describe(_ code: Int) -> String {
        switch fourCC(code) {
        case "wht?": "unspecified audio file error — the file is missing or unreadable"
        case "typ?": "unsupported audio file type"
        case "fmt?": "unsupported audio data format"
        case "dta?": "invalid audio data"
        case let c?: "audio error '\(c)' (\(code))"
        case nil: "audio error \(code)"
        }
    }
}
