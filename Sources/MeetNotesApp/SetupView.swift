import AppKit
import AVFoundation
import MeetNotesRecording
import SwiftUI

final class SetupState: ObservableObject {
    @Published var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var systemAudio: SystemAudioCheckResult?
    @Published var checking = false
}

/// Setup (spec fazy 1, §1.3): pogrupowany po funkcjach. Faza 1 prosi tylko
/// o mikrofon i dźwięk systemowy. O ekran nie prosimy nigdy.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = SetupState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up recording").font(.title2)
            Text("MeetNotes records the other side of the call from system audio and your voice from the microphone, into separate files. It never asks to record your screen.")
                .foregroundStyle(.secondary)
            row(title: "Microphone", detail: "Your side of the conversation.", ok: state.mic == .authorized) {
                Button("Allow") {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async { state.mic = AVCaptureDevice.authorizationStatus(for: .audio) }
                    }
                }
            }
            row(title: "System audio", detail: systemAudioDetail, ok: isWorking) {
                Button(state.checking ? "Checking…" : "Test") {
                    state.checking = true
                    Task { @MainActor in
                        let result = await SystemAudioCheck.run()
                        state.systemAudio = result
                        if case .works = result { UserDefaults.standard.set(true, forKey: "systemAudioVerified") }
                        state.checking = false
                    }
                }
                .disabled(state.checking || model.recording.isRecording)
                .help("Plays a short tone and checks that it's captured")
            }
            if case .silent = state.systemAudio {
                Button("Open System Audio Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                }
            }
            HStack {
                Spacer()
                Button("Done") { model.showSetup = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var isWorking: Bool {
        if case .works = state.systemAudio { return true }
        return false
    }

    private var systemAudioDetail: String {
        switch state.systemAudio {
        case .works: "Working — the test tone was captured."
        case .silent: "The test tone wasn't captured. Allow MeetNotes under System Audio Recording Only."
        case .failed(let e): "Couldn't start capture: \(e)"
        case nil: "The other side of the call. Test plays a short tone."
        }
    }

    private func row(title: String, detail: String, ok: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top) {
            Image(systemName: ok ? "checkmark.circle" : "circle").foregroundStyle(ok ? .green : .secondary).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok { action() } else { Text("Ready").foregroundStyle(.secondary) }
        }
    }
}
