import Foundation
import YascribeProviders
import YascribeTranscription

/// Historia korekt przebiegu. „Improve again" nadpisuje `corrected.json`, więc przed zapisem obecna korekta razem ze śladami
/// (słownictwo i polecenie, które do niej poszły) jest kopiowana do `runs/<run>/corrections/<czas>-<model>/`.
public enum CorrectionHistory {
    /// Pliki jednej korekty: wynik i ślady zapisywane obok niego po udanym zapisie.
    public static let files = ["corrected.json", "vocabulary.txt", "correction-system.txt"]

    public static func directory(of run: RunDirectory) -> URL { run.url.appendingPathComponent("corrections") }

    /// Kopiuje (nie przenosi: stara korekta zostaje na miejscu do chwili nadpisania) bieżącą korektę do archiwum.
    /// `nil` = zarchiwizowano, nie było czego archiwizować albo ta korekta już tam jest; błąd = nie udało się (korekta idzie dalej).
    /// Nazwa katalogu: czas zapisu korekty (UTC) i model, więc ta sama korekta nie trafia do archiwum dwa razy.
    public static func archive(run: RunDirectory) -> Error? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: run.corrected.path) else { return nil }
        do {
            let when = (try fm.attributesOfItem(atPath: run.corrected.path)[.modificationDate] as? Date) ?? Date()
            let model = ((try? JSONFile.load(CorrectedTranscript?.self, from: run.corrected, default: nil)) ?? nil)?.model ?? "unknown"
            let target = directory(of: run).appendingPathComponent("\(stamp(when))-\(safe(model))")
            guard !fm.fileExists(atPath: target.path) else { return nil }
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for name in files {
                let source = run.url.appendingPathComponent(name)
                if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: target.appendingPathComponent(name)) }
            }
            return nil
        } catch {
            return error
        }
    }

    /// Zarchiwizowane korekty, od najstarszej (nazwa zaczyna się od czasu).
    public static func entries(of run: RunDirectory) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory(of: run), includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    /// Nazwa modelu jako jeden bezpieczny komponent ścieżki (`org/model:tag` → `org_model_tag`).
    static func safe(_ model: String) -> String {
        let s = String(model.map { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) ? $0 : "_" }.prefix(60))
        return s.isEmpty ? "unknown" : s
    }
}
