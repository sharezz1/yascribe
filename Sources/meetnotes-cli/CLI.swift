import AVFoundation
import Foundation
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat

/// Narzędzie deweloperskie: sondy i testy odbiorcze bez interfejsu.
/// Uwaga: uruchomione z terminala dziedziczy uprawnienia TCC terminala
/// (albo aplikacji, w której terminal działa), nie aplikacji MeetNotes.
@main
struct CLI {
    static let usage = """
    meetnotes-cli <polecenie>
      record <katalog> [--seconds N] [--silence N] [--aec] [--no-system]   nagrywa sesję (Ctrl-C = Stop)
      summarize <katalog>                                         odtwarza session.json z dziennika
      fit <wzorzec> <nagranie.caf> [--max-lag-ms N]              T1/T3/T4: dopasowanie nagranie ≈ a·wzorzec
      check-system-audio                                          sprawdza, czy tap słyszy dźwięk systemowy
      models <baseURL>                                            lista modeli (klucz: MEETNOTES_API_KEY)
      probe <baseURL> <model> <asr|correction|summary|embedding> [--language pl]
    """

    /// Opcje z wartością — także te z planów B4/C4. `positional` pomija ich wartości.
    static let valued: Set = ["--seconds", "--silence", "--max-lag-ms", "--language", "--shape", "--run"]
    static let known = valued.union(["--aec", "--no-aec", "--no-system"])

    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { print(usage); exit(64) }
        let cmd = args.removeFirst()
        if let bad = args.first(where: { $0.hasPrefix("--") && !known.contains($0) }) {
            FileHandle.standardError.write(Data("nieznana opcja: \(bad)\n".utf8))
            print(usage); exit(64)
        }
        do {
            switch cmd {
            case "record": try await record(args)
            case "summarize": try summarize(args)
            case "fit": try fit(args)
            case "check-system-audio": print(await SystemAudioCheck.run())
            case "models": try await models(args)
            case "probe": try await probe(args)
            default: print(usage); exit(64)
            }
        } catch {
            FileHandle.standardError.write(Data("błąd: \(error)\n".utf8))
            exit(1)
        }
    }

    static func option(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Opcja liczbowa: brak = `nil`, a podana bez wartości albo z wartością
    /// nieliczbową/niedodatnią to błąd użycia — nie cicha wartość domyślna (S3-3).
    static func number(_ args: [String], _ name: String) -> Double? {
        guard args.contains(name) else { return nil }
        guard let v = option(args, name).flatMap(Double.init), v.isFinite, v > 0 else {
            FileHandle.standardError.write(Data("\(name) wymaga liczby dodatniej\n".utf8))
            print(usage); exit(64)
        }
        return v
    }

    static func positional(_ args: [String], _ n: Int) throws -> String {
        let p = args.indices.filter { i in
            !args[i].hasPrefix("--") && !(i > 0 && valued.contains(args[i - 1]))
        }.map { args[$0] }
        guard n < p.count else { print(usage); exit(64) }
        return p[n]
    }

    static func record(_ args: [String]) async throws {
        let dir = URL(fileURLWithPath: try positional(args, 0))
        var sources: [any AudioSource] = []
        if !args.contains("--no-system") { sources.append(SystemTapSource()) }
        sources.append(RawMicrophoneSource())
        // Domyślnie bez VP: ścisza inne aplikacje (S5-ducking-konsultacja). `--no-aec` = domyślne, z planów.
        if args.contains("--aec") { sources.append(VoiceProcessedMicrophoneSource()) }
        var conditions: [any EndCondition] = .standard
        if let s = number(args, "--seconds") { // zastępuje 4 h ze standardu, inaczej > 4 h nie działa (S3-5)
            conditions.removeAll { $0 is HardLimitCondition }
            conditions.append(HardLimitCondition(seconds: s))
        }
        // ⚠️ Po recenzji (R1): krótszy próg ciszy do sprzętowego T5. Pierwszy na liście wygrywa.
        if let s = number(args, "--silence") { conditions.insert(SilenceCondition(seconds: s), at: 0) }
        let recorder = SessionRecorder(directory: dir, sources: sources, conditions: conditions)
        let done = AsyncStream<EndReason> { cont in recorder.onEnded = { cont.yield($0); cont.finish() } }
        signal(SIGINT, SIG_IGN)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT)
        sigint.setEventHandler { recorder.stop(reason: .button) }
        sigint.resume()
        // sleep rzuca po cancel(), więc po anulowaniu nie ma już ani jednego tick() (S3-7).
        let ticker = Task { while (try? await Task.sleep(for: .seconds(1))) != nil { recorder.tick() } }
        try recorder.start()
        print("nagrywam do \(dir.path) — Ctrl-C kończy")
        for await _ in done {} // „koniec:" wypisuje summarize (S3-8)
        ticker.cancel()
        await ticker.value
        sigint.cancel()
        signal(SIGINT, SIG_DFL)
        try summarize([dir.path])
    }

    static func summarize(_ args: [String]) throws {
        let s = try SessionDirectory(url: URL(fileURLWithPath: try positional(args, 0))).rebuildSummaryFile()
        print("koniec: \(s.endReason ?? "BRAK (awaria)")")
        for t in s.tracks {
            let off = t.offsetSeconds.map { String(format: "%+.3f s", $0) } ?? "—"
            let rate = t.effectiveSampleRate.map { String(format: "%.2f Hz", $0) } ?? "—"
            print("  \(t.id): \(Int(t.sampleRate)) Hz × \(t.channels), ramek \(t.frames ?? -1), przesunięcie \(off), "
                  + "efektywnie \(rate), luk \(t.gaps.count)"
                  + (t.permissionDenied.map { ", ODMOWA \($0)" } ?? "") + (t.failure.map { ", BŁĄD \($0)" } ?? ""))
        }
    }

    static func fit(_ args: [String]) throws {
        // Wzorzec w dowolnym formacie (np. aiff z `say`), nagranie — nasz CAF.
        // Oba argumenty przed otwarciem czegokolwiek: brak drugiego = kod 64, nie błąd CoreAudio (S3-4).
        let refURL = URL(fileURLWithPath: try positional(args, 0))
        let recURL = URL(fileURLWithPath: try positional(args, 1))
        let lagMs = number(args, "--max-lag-ms") ?? 500
        let r = try AudioFit.fitFiles(reference: refURL, recording: recURL, maxLagMs: lagMs)
        print(String(format: "a = %.4f  R² = %.4f  korelacja = %.4f  opóźnienie = %.1f ms",
                     r.gain, r.rSquared, r.correlation, Double(r.lagFrames) / AudioFit.analysisRate * 1000))
    }

    /// Czyta dowolny plik audio jako Int16 przeplatany — patrz `AudioFit.readAnyAudio`.
    static func readAnyAudio(_ url: URL) throws -> (samples: [Int16], rate: Double, channels: Int) {
        try AudioFit.readAnyAudio(url)
    }

    static func client(_ base: String) throws -> OpenAICompatibleClient {
        guard let url = URL(string: base) else { throw ProviderError.badResponse("zły adres \(base)") }
        return OpenAICompatibleClient(provider: Provider(name: "cli", baseURL: url),
                                      key: ProcessInfo.processInfo.environment["MEETNOTES_API_KEY"])
    }

    static func models(_ args: [String]) async throws {
        for m in try await client(try positional(args, 0)).listModels() {
            print(m.id + (m.inputModalities.map { "  [\($0.joined(separator: ","))]" } ?? ""))
        }
    }

    static func probe(_ args: [String]) async throws {
        guard let role = Role(rawValue: try positional(args, 2)) else { print(usage); exit(64) }
        let lang = try option(args, "--language").map { try LanguageCode($0) }
        let r = await ProbeRunner(client: try client(try positional(args, 0))).probe(model: try positional(args, 1), role: role, language: lang)
        print(r.works ? "DZIAŁA" : "NIE DZIAŁA", r.shape?.rawValue ?? "", r.languageHandling?.rawValue ?? "",
              r.embeddingDimension.map { "wymiar \($0)" } ?? "", r.failure ?? "")
    }
}
