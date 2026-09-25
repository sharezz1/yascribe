import AVFoundation
import Foundation
import MeetNotesRecording
import MeetNotesSessionFormat

/// Narzędzie deweloperskie: sondy i testy odbiorcze bez interfejsu.
/// Uwaga: uruchomione z terminala dziedziczy uprawnienia TCC terminala
/// (albo aplikacji, w której terminal działa), nie aplikacji MeetNotes.
@main
struct CLI {
    static let usage = """
    meetnotes-cli <polecenie>
      record <katalog> [--seconds N] [--silence N] [--no-aec] [--no-system]   nagrywa sesję (Ctrl-C = Stop)
      summarize <katalog>                                         odtwarza session.json z dziennika
      fit <wzorzec> <nagranie.caf> [--max-lag-ms N]              T1/T3/T4: dopasowanie nagranie ≈ a·wzorzec
      check-system-audio                                          sprawdza, czy tap słyszy dźwięk systemowy
    """

    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { print(usage); exit(64) }
        let cmd = args.removeFirst()
        do {
            switch cmd {
            case "record": try await record(args)
            case "summarize": try summarize(args)
            case "fit": try fit(args)
            case "check-system-audio": print(await SystemAudioCheck.run())
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

    static func positional(_ args: [String], _ n: Int) throws -> String {
        let p = args.filter { !$0.hasPrefix("--") }
        guard n < p.count else { print(usage); exit(64) }
        return p[n]
    }

    static func record(_ args: [String]) async throws {
        let dir = URL(fileURLWithPath: try positional(args, 0))
        var sources: [any AudioSource] = []
        if !args.contains("--no-system") { sources.append(SystemTapSource()) }
        sources.append(RawMicrophoneSource())
        if !args.contains("--no-aec") { sources.append(VoiceProcessedMicrophoneSource()) }
        var conditions: [any EndCondition] = .standard
        if let s = option(args, "--seconds").flatMap(Double.init) { conditions.append(HardLimitCondition(seconds: s)) }
        // ⚠️ Po recenzji (R1): krótszy próg ciszy do sprzętowego T5. Pierwszy na liście wygrywa.
        if let s = option(args, "--silence").flatMap(Double.init) { conditions.insert(SilenceCondition(seconds: s), at: 0) }
        let recorder = SessionRecorder(directory: dir, sources: sources, conditions: conditions)
        let done = AsyncStream<EndReason> { cont in recorder.onEnded = { cont.yield($0); cont.finish() } }
        signal(SIGINT, SIG_IGN)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT)
        sigint.setEventHandler { recorder.stop(reason: .button) }
        sigint.resume()
        let ticker = Task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); recorder.tick() } }
        try recorder.start()
        print("nagrywam do \(dir.path) — Ctrl-C kończy")
        for await reason in done { print("koniec: \(reason.rawValue)") }
        ticker.cancel()
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
        let ref = try readAnyAudio(URL(fileURLWithPath: try positional(args, 0)))
        let rec = try CAFReader(url: URL(fileURLWithPath: try positional(args, 1)))
        let rate = 16_000.0
        let a = AudioFit.resample(AudioFit.mono(ref.samples, channels: ref.channels), from: ref.rate, to: rate)
        let b = AudioFit.resample(AudioFit.mono(rec.samples, channels: rec.channels), from: rec.sampleRate, to: rate)
        let lagMs = option(args, "--max-lag-ms").flatMap(Double.init) ?? 500
        let r = AudioFit.fit(reference: a, recorded: b, maxLagFrames: Int(lagMs / 1000 * rate))
        print(String(format: "a = %.4f  R² = %.4f  korelacja = %.4f  opóźnienie = %.1f ms",
                     r.gain, r.rSquared, r.correlation, Double(r.lagFrames) / rate * 1000))
    }

    /// Czyta dowolny plik audio jako Int16 przeplatany. W pętli: jedno `read(into:)`
    /// potrafi oddać mniej ramek niż pojemność bufora (📐 63 454 z 64 000).
    static func readAnyAudio(_ url: URL) throws -> (samples: [Int16], rate: Double, channels: Int) {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let ch = Int(f.processingFormat.channelCount)
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 8_192) else {
            throw AudioSourceError.coreAudio("AVAudioPCMBuffer", -1)
        }
        var out: [Int16] = []
        while f.framePosition < f.length {
            try f.read(into: buf)
            if buf.frameLength == 0 { break }
            guard let p = buf.int16ChannelData else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: p[0], count: Int(buf.frameLength) * ch))
        }
        return (out, f.processingFormat.sampleRate, ch)
    }
}
