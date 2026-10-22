import AVFoundation
import Foundation
import MeetNotesLocalASR
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
import MeetNotesTranscription

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
      tap-rate [--seconds N] [--with-mic] [--tap-only]                         mierzy częstotliwości tapa i rzeczywiste dostarczanie (faza 2.0.2)
      models <baseURL>                                            lista modeli (klucz: MEETNOTES_API_KEY)
      probe <baseURL> <model> <asr|correction|summary|embedding> [--language pl]
      transcribe <katalog> <baseURL> <model> --language pl [--shape audioTranscriptions] [--run ID] [--model-store <korzeń>]
                                                                  <baseURL> = local://fluidaudio: lokalny Parakeet (bez sieci i klucza)
      session-from-file <plik audio> <katalog>                     TYLKO TESTY: sesja z pliku (korpus)
    Czasy z transcribe są na osi sesji; czas w pliku ścieżki = czas na osi − przesunięcie z summarize.
    """

    /// Opcje z wartością — także te z planów B4/C4. `positional` pomija ich wartości.
    static let valued: Set = ["--seconds", "--silence", "--max-lag-ms", "--language", "--shape", "--run", "--model-store"]
    static let known = valued.union(["--aec", "--no-aec", "--no-system", "--with-mic", "--tap-only"])

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
            case "tap-rate": try await tapRate(args)
            case "models": try await models(args)
            case "probe": try await probe(args)
            case "transcribe": try await transcribe(args)
            case "session-from-file": try await sessionFromFile(args)
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

    /// Opcja tekstowa: brak = `nil`, a podana bez wartości to błąd użycia (S3-3, check S12 #4).
    static func value(_ args: [String], _ name: String) -> String? {
        guard args.contains(name) else { return nil }
        guard let v = option(args, name), !v.hasPrefix("--") else {
            FileHandle.standardError.write(Data("\(name) wymaga wartości\n".utf8)); exit(64)
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

    /// Suma klatek i energia porcji toru `system` w jednym oknie pomiarowym.
    final class TapStats: @unchecked Sendable {
        private let lock = NSLock()
        private var frames = 0, lastFrames = 0
        private var first: UInt64?, last: UInt64 = 0
        private var sumSquares = 0.0, samples = 0

        func add(_ c: AudioChunk, channels: Int) {
            lock.lock(); defer { lock.unlock() }
            let f = c.samples.count / max(channels, 1)
            if first == nil { first = c.hostTime }
            frames += f; lastFrames = f; last = c.hostTime
            for v in c.samples { sumSquares += Double(v) * Double(v) }
            samples += c.samples.count
        }

        /// Zmierzona częstotliwość: klatki bez ostatniej porcji / czas między pierwszą a ostatnią (czas porcji = jej pierwsza próbka).
        func takeLine() -> String {
            lock.lock(); defer { lock.unlock() }
            defer { frames = 0; lastFrames = 0; first = nil; sumSquares = 0; samples = 0 }
            guard let first, last > first else { return "zmierzone=brak porcji (0 klatek)" }
            let secs = Timebase.current.secondsBetween(last, first)
            let rate = Double(frames - lastFrames) / secs
            let rms = samples > 0 ? 20 * log10(max((sumSquares / Double(samples)).squareRoot(), 1) / 32768) : -160
            return String(format: "zmierzone=%.0f Hz (ramek %d w %.1f s) rms=%.1f dBFS", rate, frames, secs, rms)
        }
    }

    /// Faza 2.0.2, bramka M1: trzy częstotliwości tapa kontra to, co naprawdę dociera do IOProc.
    static func tapRate(_ args: [String]) async throws {
        let seconds = number(args, "--seconds") ?? 10
        let tap = SystemTapSource(layout: args.contains("--tap-only") ? .tapOnly : .withOutputSubdevice)
        let format = try tap.prepare()
        let stats = TapStats()
        try tap.start { if case .chunk(let c) = $0 { stats.add(c, channels: format.channels) } }
        func report(_ label: String) {
            let r = tap.rates()
            print("[\(label)] tapFormat=\(r.map { String(Int($0.tapFormat)) } ?? "?") aggregateNominal=\(r.map { String(Int($0.aggregateNominal)) } ?? "?") "
                  + "outputNominal=\(r.map { String(Int($0.outputNominal)) } ?? "?") deklarowane=\(Int(format.sampleRate)) \(stats.takeLine())")
        }
        let half = args.contains("--with-mic") ? seconds / 2 : seconds
        try await Task.sleep(for: .seconds(half))
        report(args.contains("--with-mic") ? "bez mikrofonu" : "tap")
        if args.contains("--with-mic") {
            // Jak w aplikacji: mikrofon dochodzi po tapie; słuchawki mogą wtedy przełączyć profil (hipoteza S0b).
            let mic = RawMicrophoneSource()
            _ = try mic.prepare()
            try mic.start { _ in }
            try await Task.sleep(for: .seconds(seconds - half))
            report("po otwarciu mikrofonu")
            mic.stop()
        }
        tap.stop()
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
        // Bez schematu każde żądanie pada na `unsupported URL`, a w transcribe widać to tylko w transcript.json (S13).
        guard let url = URL(string: base), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil else {
            FileHandle.standardError.write(Data("zły adres \(base): podaj pełny adres z http:// albo https://\n".utf8)); exit(64)
        }
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
        let lang = try value(args, "--language").map { try LanguageCode($0) }
        let r = await ProbeRunner(client: try client(try positional(args, 0))).probe(model: try positional(args, 1), role: role, language: lang)
        print(r.works ? "DZIAŁA" : "NIE DZIAŁA", r.shape?.rawValue ?? "", r.languageHandling?.rawValue ?? "",
              r.embeddingDimension.map { "wymiar \($0)" } ?? "", r.failure ?? "")
    }

    static func transcribe(_ args: [String]) async throws {
        // Wszystkie błędy użycia przed budową klienta — kolejność komunikatów nie zależy od tego, który argument jest zły.
        let dir = URL(fileURLWithPath: try positional(args, 0))
        guard FileManager.default.fileExists(atPath: SessionDirectory(url: dir).journalURL.path) else {
            FileHandle.standardError.write(Data("\(dir.path): to nie katalog sesji (brak journal.jsonl)\n".utf8)); exit(64)
        }
        guard let langRaw = value(args, "--language") else {
            FileHandle.standardError.write(Data("--language jest obowiązkowe (pl, en… albo auto — tylko do pomiarów)\n".utf8)); exit(64)
        }
        let language: LanguageCode? = langRaw.lowercased() == "auto" ? nil : try LanguageCode(langRaw)
        let runOption = value(args, "--run")
        if let s = value(args, "--shape"), s != ASRShape.audioTranscriptions.rawValue {
            FileHandle.standardError.write(Data("--shape \(s): w transcribe dozwolone tylko audioTranscriptions\n".utf8)); exit(64)
        }
        let localStore = value(args, "--model-store").map { ModelStore(directory: URL(fileURLWithPath: $0, isDirectory: true)) } ?? ModelStore()
        let c: any TranscriptionClient
        if try positional(args, 1) == Provider.fluidAudioBaseURL.absoluteString {
            // Lokalny ASR (F20 S1): ten sam runner co aplikacja. Odmowa = komunikat i kod 1, bez fallbacku do API.
            // Magazyn: --model-store (korzeń); MEETNOTES_MODEL_STORE działa tylko w DEBUG, a S1 mierzy build release.
            switch LocalASRFactory.client(provider: Provider(name: "cli", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio), store: localStore) {
            case .success(let local): c = local
            case .failure(let refusal):
                FileHandle.standardError.write(Data("\(refusal.message)\n".utf8)); exit(1)
            }
        } else {
            c = try client(try positional(args, 1))
        }
        let preset = Preset(name: "cli", language: language,
                            asr: RoleAssignment(providerID: c.provider.id, model: try positional(args, 2)),
                            languageAuto: language == nil ? true : nil)
        let shape = ASRShape.audioTranscriptions
        let probe = ProbeResult(providerID: c.provider.id, model: try positional(args, 2), role: .asr, works: true,
                                shape: shape, languageHandling: .unknown)
        let runID = runOption ?? ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") // E3: runID bez ':'
        print("runID: \(runID)")
        var snapshot = try RunSnapshot(preset: preset, provider: c.provider, probe: probe,
                                       modelFingerprint: RunGate.fingerprintForSnapshot(provider: c.provider, store: localStore))
        // Wznowienie (check S11 #2): CLI tworzy preset i dostawcę z nowymi UUID przy każdym uruchomieniu,
        // więc przy tych samych parametrach bierzemy migawkę z pierwszego przebiegu. Inny model, język,
        // adres albo kształt → runner rzuci inputMismatch, tak jak powinien.
        if RunDirectory.isValid(runID: runID),
           let saved = try JSONFile.load(RunInput?.self, from: RunDirectory(session: dir, runID: runID).input, default: nil),
           (saved.snapshot.model, saved.snapshot.language, saved.snapshot.providerBaseURL, saved.snapshot.shape)
               == (snapshot.model, snapshot.language, snapshot.providerBaseURL, snapshot.shape) {
            snapshot = saved.snapshot
            if let refusal = RunGate.checkResume(snapshot: snapshot, provider: c.provider, currentFingerprint: localStore.fingerprint()) {
                FileHandle.standardError.write(Data("\(refusal.message)\n".utf8)); exit(1)
            }
        }
        let t = try await TranscriptionRunner(session: dir, runID: runID, snapshot: snapshot, client: c).run { p in
            // Licznik okien od razu: pierwsze okno trwa ~25 s, a samo „0%" wygląda na zawieszenie (S13).
            print(String(format: "\r%3.0f%% (okna %d/%d)", p.fraction * 100, p.done, p.total), terminator: "")
            fflush(stdout)
        }
        print()
        await (c as? ReleasableClient)?.release()
        for u in t.utterances {
            let flag = u.languageMismatch.map { " [JĘZYK: \($0)]" } ?? ""
            print(String(format: "[%7.1f] %@: ", u.start, u.speaker == .me ? "Me" : "Them") + u.text + flag)
        }
        if !t.failedChunks.isEmpty { print("nieudanych okien: \(t.failedChunks.count)") }
    }

    /// Tylko do testów (spec fazy 1, §1.0): sesja z istniejącego pliku, np. z korpusu
    /// z rozdz. 13, 14 i 17. Import plików nie jest funkcją produktu.
    static func sessionFromFile(_ args: [String]) async throws {
        let audio = URL(fileURLWithPath: try positional(args, 0))
        let dir = URL(fileURLWithPath: try positional(args, 1))
        if FileManager.default.fileExists(atPath: SessionDirectory(url: dir).journalURL.path) { // jak dotąd: odmowa, kod 1
            FileHandle.standardError.write(Data(("błąd: \(dir.path) już zawiera sesję (journal.jsonl) — "
                                                 + "session-from-file wymaga świeżego katalogu, np. osobnego dla każdego pliku korpusu\n").utf8))
            exit(1)
        }
        let src = try readAnyAudio(audio)
        let tb = Timebase.current
        let source = FileSource(trackID: "system", samples: src.samples, sampleRate: src.rate, channels: src.channels,
                                startHostTime: mach_absolute_time(), timebase: tb, chunkFrames: 4_800)
        try SessionRecorder(directory: dir, sources: [source], conditions: [], timebase: tb, zeroWatch: [:]).start()
        try summarize([dir.path])
    }
}
