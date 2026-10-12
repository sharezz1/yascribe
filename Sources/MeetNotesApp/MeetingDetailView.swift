import AVFoundation
import MeetNotesProviders
import MeetNotesTranscription
import SwiftUI

/// Zalążek widoku spotkania w fazie 1: transkrypt i skok w nagraniu (W§1).
/// Odsłuch = ścieżka systemowa bit w bit (spec rdzenia §5); mikrofon osobno.
final class PlaybackState: ObservableObject {
    var player: AVAudioPlayer?
    var track: String?
}

struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    @StateObject private var playback = PlaybackState()
    private var player: AVAudioPlayer? { playback.player }
    private var busy: Bool { model.isTranscribing(item) }

    var body: some View {
        Group {
            if let t = item.transcript {
                List {
                    if !t.failedChunks.isEmpty {
                        Button(busy ? "Transcribing…" : "Retry Failed Parts") { model.resume(item) }
                            .disabled(busy)
                            .help("Sends only the parts that failed; finished parts aren't paid for again")
                    }
                    ForEach(Array(t.utterances.enumerated()), id: \.offset) { _, u in
                        UtteranceRow(utterance: u) { play(u) }
                    }
                    if !t.failedChunks.isEmpty {
                        SwiftUI.Section("Gaps") {
                            ForEach(Array(t.failedChunks.enumerated()), id: \.offset) { _, f in
                                Label("Couldn't transcribe \(Self.time(f.start))–\(Self.time(f.end))", systemImage: "exclamationmark.circle")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No transcript yet", systemImage: "text.alignleft")
                } actions: {
                    if busy {
                        ProgressView("Transcribing…")
                    } else {
                        // Preset zamrożony przy nagraniu, nie bieżący (spec §1.5); Resume bierze migawkę z input.json przebiegu.
                        if let p = model.presetFor(sessionURL: item.url) {
                            Button("Transcribe with \(p.name)") { model.transcribe(sessionURL: item.url, preset: p) }
                        }
                        if item.runID != nil { Button("Resume Transcription") { model.resume(item) } }
                    }
                }
            }
        }
        .navigationTitle(item.startedAt.formatted(date: .abbreviated, time: .shortened))
        .toolbar {
            Button {
                if player?.isPlaying == true { player?.pause() } else if player != nil || load("system") { player?.play() }
            } label: {
                Label("Play", systemImage: "playpause")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play or pause")
        }
    }

    /// ChatGPT #8: „Me" nie ma w pliku odsłuchu (to tap systemowy) — gramy tor mikrofonu,
    /// przeliczając czas sesji na czas tej ścieżki.
    private func play(_ u: Utterance) {
        let aecOK = item.summary?.tracks.first { $0.id == "mic_aec" }.map { $0.failure == nil && $0.channels > 0 } ?? false
        let track = u.speaker == .them ? "system" : (aecOK ? "mic_aec" : "mic_raw")
        let offset = item.summary?.tracks.first { $0.id == track }?.offsetSeconds ?? 0
        guard playback.track == track || load(track) else { return }
        playback.player?.currentTime = max(0, u.start - offset)
        playback.player?.play()
    }

    /// Nieudane wczytanie nie zostaje zapamiętane jako wczytana ścieżka (check S15 #4).
    private func load(_ track: String) -> Bool {
        do {
            playback.player = try AVAudioPlayer(contentsOf: item.url.appendingPathComponent("\(track).caf"))
            playback.track = track
            return true
        } catch {
            playback.player = nil
            playback.track = nil
            model.lastError = "Couldn't open the \(track) recording: \(error.localizedDescription)"
            return false
        }
    }

    static func time(_ s: Double) -> String {
        let i = Int(s)
        return String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60)
    }
}

struct UtteranceRow: View {
    let utterance: Utterance
    let onJump: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(MeetingDetailView.time(utterance.start), action: onJump)
                .buttonStyle(.link)
                .monospacedDigit()
                .help("Play from here")
            Text(utterance.speaker == .me ? "Me" : "Them")
                .font(.caption.weight(.semibold))
                .frame(width: 40, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(utterance.text).textSelection(.enabled)
                if let lang = utterance.languageMismatch {
                    // P11: widoczne, nie ukryte — i wyłączone z notatek.
                    Label("Looks like \(lang.rawValue.uppercased()), not the preset's language — excluded from notes",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if utterance.approximateTiming {
                    Text("Approximate timing").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
