@preconcurrency import AVFoundation
import Foundation

public enum SystemAudioCheckResult: Equatable, Sendable {
    /// Tap usłyszał dźwięk testowy.
    case works(peakDBFS: Double)
    /// Tap działa, ale dźwięku nie usłyszał — odmowa uprawnienia albo wyciszenie.
    case silent(peakDBFS: Double)
    case failed(String)
}

/// Sprawdzenie **działania**, a nie flagi uprawnienia (spec fazy 1, §1.3, O5):
/// uruchamia tap, odtwarza krótki ton i mierzy, czy wrócił. Publicznego API do
/// odczytu stanu uprawnienia dźwięku systemowego nie ma; to sprawdzenie nie
/// potrzebuje prywatnego TCC i działa bez względu na to, czy system przy odmowie
/// zwraca błąd, czy zera.
public enum SystemAudioCheck {
    public static func evaluate(levelsDBFS: [Double], threshold: Double = -45) -> SystemAudioCheckResult {
        let peak = levelsDBFS.max() ?? -160
        return peak > threshold ? .works(peakDBFS: peak) : .silent(peakDBFS: peak)
    }

    /// Ton 880 Hz, 300 ms, -20 dBFS. Słyszalny — interfejs uprzedza o nim.
    public static func run(timeout: Double = 1.5, tap: any AudioSource = SystemTapSource()) async -> SystemAudioCheckResult {
        let levels = LevelCollector()
        // `defer` PRZED startem: przy błędzie `prepare`/`start` tap i urządzenie zbiorcze też są sprzątane (S18 §2.2).
        defer { tap.stop() }
        do {
            _ = try tap.prepare()
            try tap.start { event in
                if case .chunk(let c) = event { levels.add(Levels.rmsDBFS(c.samples)) }
            }
        } catch {
            return .failed("\(error)")
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        guard let tone = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fmt.sampleRate * 0.3)) else {
            return .failed("tone buffer")
        }
        tone.frameLength = tone.frameCapacity
        for c in 0..<Int(fmt.channelCount) {
            for i in 0..<Int(tone.frameLength) {
                tone.floatChannelData![c][i] = Float(0.1 * sin(2 * .pi * 880 * Double(i) / fmt.sampleRate))
            }
        }
        do { try engine.start() } catch { return .failed("\(error)") }
        player.scheduleBuffer(tone, at: nil, options: [], completionHandler: nil)
        player.play()
        try? await Task.sleep(for: .seconds(timeout))
        engine.stop()
        return evaluate(levelsDBFS: levels.values)
    }
}

final class LevelCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [Double] = []
    func add(_ x: Double) { lock.lock(); v.append(x); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return v }
}
