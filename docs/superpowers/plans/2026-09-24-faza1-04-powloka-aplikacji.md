# Plan D — powłoka aplikacji

> **Dla wykonawcy (Hermes):** najpierw przegląd §0 „Instrukcja dla Hermesa". Jedno zadanie = jedna sesja. Kroki używają pól `- [ ]`.

**Cel:** aplikacja MeetNotes: nawigacja z sześcioma zakładkami, strona główna w wariancie B (oś nagrań po dniach), widok spotkania ze skokiem w nagraniu, presety, ustawienia dostawców, setup uprawnień i pływające okno nagrywania — złożona w podpisany `.app` bez Xcode.

**Architektura:** `AppModel` (`@Observable`, `@MainActor`) spina magazyny z planu B, rejestrator z planu A i wykonawcę z planu C. Widoki SwiftUI biorą model przez `@Environment`, a stan lokalny trzymają w `ObservableObject` pod `@StateObject` — bez `@State` (przegląd §4). Pływające okno to `NSPanel` z `.nonactivatingPanel`. `.app` składa skrypt z pliku wykonywalnego SwiftPM.

**Stos:** SwiftUI, AppKit (`NSPanel`, `NSHostingView`, `NSWorkspace`), AVFoundation (`AVAudioPlayer`), Observation, `codesign`.

**Specyfikacje:** `docs/superpowers/specs/2026-09-24-faza1-warstwa-dostawcow-design.md` §1.2–§1.5, §9; `docs/design/macos.md` (cały); spec rdzenia §8. Przegląd: `docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md`.

## Wspólne ograniczenia

Obowiązują w całości: przegląd §4. Najważniejsze dla tego planu:

- 🔴 Bez `@State`, `@Entry`, `@Animatable`, `#Preview`. Model aplikacji jest stałą struktury `App`.
- Interfejs po angielsku; słowo „window", nie „panel/view/scene" (`macos.md` §2).
- Zakładki: Meetings, Tasks, Dictation, Dictionary, Presets, Settings. Tasks, Dictation i Dictionary w fazie 1 pokazują pusty stan z informacją, kiedy przyjdą.
- Settings to zakładka (odstępstwo 3 w `macos.md` §10); pozycja **Settings…** w menu aplikacji i **Cmd-,** prowadzą do niej.
- Pływające okno: `level = .floating`, `hidesOnDeactivate = false`, `.nonactivatingPanel` (odstępstwa 1 i 2).
- 🔴 Stan nagrywania nigdy samym kolorem: napis „Recording" i licznik. Pulsowanie wyłączone przy Reduce Motion.
- 🔴 Preset z językiem widoczny przy przycisku nagrywania przed startem. Wybór języka w presecie bez wartości domyślnej i bez „Automatic".
- `CFBundleIdentifier` = `io.github.sharezz1.meetnotes`, `LSMinimumSystemVersion` = 27.0, `CFBundleDevelopmentRegion` = en.
- Brak testów automatycznych interfejsu: XCUITest wymaga Xcode. Weryfikacja: budowa + D3 ręcznie.

## Na co patrzeć przy przeglądzie

Testy ręczne w D3 — każde z tych wejść ma tam osobny krok:

1. **Pierwsze uruchomienie bez zgody na mikrofon** → setup pokazuje się sam; odmowa → nagranie rusza z samym dźwiękiem systemowym, a dziennik to odnotowuje.
2. **Przebudowa aplikacji** → z certyfikatem „MeetNotes Dev" uprawnienia TCC zostają; z podpisem ad-hoc system pyta od nowa.
3. **Preset bez języka** → Save pokazuje „Choose a language…" i nic nie zapisuje.
4. **Teams na pierwszym planie w trakcie nagrywania** → pływające okno widoczne, klik w Stop nie przełącza fokusu z Teamsa.
5. **458 modeli w liście OpenRoutera** → menu pokazuje pierwsze 300; model spoza tej puli (jak MAI-Transcribe-2, którego w liście nie ma wcale) wpisuje się z ręki. To znane ograniczenie fazy 1.

---

### Zadanie D1: Stały podpis i składanie `.app`

Status: ✅ zweryfikowane (2026-10-12, S14 + S14fix): `bundle.sh` składa i podpisuje „MeetNotes Dev" (`Authority=MeetNotes Dev`). O tym, że TCC nie resetuje uprawnień, decyduje wymaganie wyznaczone (DR), nie `codesign --verify --strict` (ten sprawdza tylko integralność i przechodzi też dla ad-hoc): `codesign -d -r-` daje `identifier "io.github.sharezz1.meetnotes" and certificate leaf = H"7c8ca11f…"`, identyczne przed i po `touch Sources/MeetNotesApp/main.swift` + przebudowie (S14fix). Samego zachowania TCC nie da się sprawdzić na zaślepce; sprawdzi je D3. `run.sh` uruchomiony na zaślepce (S14fix). Poprawka po STOP — warunek `security find-identity` bez `-v` (samopodpisany certyfikat ma `CSSMERR_TP_NOT_TRUSTED`), raport `reports/S14.md`. Krok 1 wykonuje **użytkownik**: to zmiana w jego pęku kluczy.

**Pliki:**
- Utwórz: `Resources/Info.plist`, `scripts/bundle.sh`, `scripts/run.sh`

**Interfejsy:**
- Dostarcza: `scripts/bundle.sh` → na stdout wypisuje wyłącznie ścieżkę `.build/MeetNotes.app`, logi budowy idą na stderr (zmienne: `MEETNOTES_SIGN_IDENTITY`, `-` = ad-hoc; `CONFIG=release`). `scripts/run.sh` → buduje i uruchamia z `MEETNOTES_DATA_DIR=.devdata`; kod 1, gdy `MeetNotesApp` już działa (przed budową) albo gdy proces nie pojawi się w ciągu 5 s od `open`.

- [x] **Krok 1 (użytkownik): certyfikat „MeetNotes Dev".** Dostęp do pęku kluczy → menu *Dostęp do pęku kluczy → Asystent certyfikatów → Utwórz certyfikat…*. Nazwa: `MeetNotes Dev`, Typ tożsamości: *Samopodpisany główny*, Typ certyfikatu: *Podpisywanie kodu*. Sprawdzenie: `security find-identity -p codesigning | grep "MeetNotes Dev"` (bez `-v`) wypisuje jedną linię, np. `1) 7C8C… "MeetNotes Dev" (CSSMERR_TP_NOT_TRUSTED)`. Dla certyfikatu samopodpisanego `CSSMERR_TP_NOT_TRUSTED` jest normalne, a `-v` pokazuje „0 valid identities" — to nie błąd; `codesign -s "MeetNotes Dev"` mimo to podpisuje (sprawdził użytkownik, S14).

- [x] **Krok 2: `Resources/Info.plist`.**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.sharezz1.meetnotes</string>
    <key>CFBundleName</key>
    <string>MeetNotes</string>
    <key>CFBundleDisplayName</key>
    <string>MeetNotes</string>
    <key>CFBundleExecutable</key>
    <string>MeetNotesApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>MeetNotes records your side of the meeting from the microphone.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>MeetNotes records the other side of the meeting from system audio. It never records your screen.</string>
</dict>
</plist>
```

- [x] **Krok 3: `scripts/bundle.sh`** (`chmod +x`).

```bash
#!/bin/bash
# Składa MeetNotes.app z pliku wykonywalnego SwiftPM — bez Xcode.
#
# Podpis: stały certyfikat "MeetNotes Dev" (plan D, zadanie D1). Bez niego podpis
# ad-hoc zmienia cdhash przy każdej przebudowie i TCC resetuje uprawnienia do
# mikrofonu i dźwięku systemowego (spec rdzenia §8).
#   MEETNOTES_SIGN_IDENTITY=-   wymusza ad-hoc (np. w CI, bez pęku kluczy)
#   CONFIG=release              budowa w trybie release
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-debug}"
# Logi budowy na stderr: stdout to wyłącznie ścieżka paczki (kontrakt z run.sh).
swift build -c "$CONFIG" --product MeetNotesApp >&2
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MeetNotesApp"
APP=".build/MeetNotes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeetNotesApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

IDENTITY="${MEETNOTES_SIGN_IDENTITY:-MeetNotes Dev}"
# Pełny odczyt do zmiennej zamiast `| grep -q`: grep kończy na pierwszym trafieniu,
# security dostaje SIGPIPE, a pipefail zamienia to w fałsz → cichy podpis ad-hoc.
CERTS=""
[ "$IDENTITY" = "-" ] || CERTS="$(security find-identity -p codesigning || true)"
case "$CERTS" in
    *"\"$IDENTITY\""*)
        codesign --force --sign "$IDENTITY" "$APP" ;;
    *)
        [ "$IDENTITY" != "-" ] && echo "UWAGA: brak certyfikatu \"$IDENTITY\" — podpis ad-hoc; TCC zresetuje uprawnienia po każdej przebudowie" >&2
        codesign --force --sign - "$APP" ;;
esac
codesign --verify --strict "$APP"
echo "$APP"
```

- [x] **Krok 4: `scripts/run.sh`** (`chmod +x`).

```bash
#!/bin/bash
# Buduje i uruchamia aplikację z danymi w .devdata/ (czysto na dysku, spec rdzenia §8).
set -euo pipefail
cd "$(dirname "$0")/.."
# Druga instancja nagrywałaby do tego samego .devdata, a bundle.sh skasowałby
# paczkę spod działającej — przerywamy przed budową.
if pgrep -x MeetNotesApp >/dev/null; then
    echo "run.sh: MeetNotesApp już działa (PID $(pgrep -x MeetNotesApp | xargs)) — zamknij ją i uruchom ponownie" >&2
    exit 1
fi
APP="$(scripts/bundle.sh)"
[ -d "$APP" ] || { echo "run.sh: bundle.sh nie zwrócił katalogu paczki: \"$APP\"" >&2; exit 1; }
mkdir -p .devdata
open -n --env MEETNOTES_DATA_DIR="$PWD/.devdata" "$APP"
# open oddaje zlecenie LaunchServices i wychodzi z 0 — sprawdzamy, czy proces wstał.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x MeetNotesApp >/dev/null && exit 0
    sleep 0.5
done
echo "run.sh: MeetNotesApp nie działa 5 s po open (nie wystartowała albo od razu się zakończyła)" >&2
exit 1
```

- [x] **Krok 5: Sprawdź składanie na zaślepce.** Cel `MeetNotesApp` ma jeszcze `main.swift` z A1, więc paczka zawiera program bez okna — to wystarcza do sprawdzenia skryptu. `scripts/bundle.sh 2>/dev/null` — oczekiwane: jedna linia `.build/MeetNotes.app`, a na stderr bez komunikatu `UWAGA`, jeśli certyfikat z kroku 1 istnieje. `codesign -dvv .build/MeetNotes.app 2>&1 | grep -E 'Identifier|Authority'` — oczekiwane: `Identifier=io.github.sharezz1.meetnotes` i `Authority=MeetNotes Dev`. `plutil -extract LSMinimumSystemVersion raw .build/MeetNotes.app/Contents/Info.plist` — `27.0`. Stabilność podpisu: `codesign -d -r- .build/MeetNotes.app` przed i po `touch Sources/MeetNotesApp/main.swift` + `scripts/bundle.sh` — DR identyczne (`… and certificate leaf = H"…"`, nie `cdhash`).

- [x] **Krok 6: Commit.**

```bash
git add Resources/Info.plist scripts/bundle.sh scripts/run.sh docs/superpowers/plans/2026-09-24-faza1-04-powloka-aplikacji.md docs/superpowers/reports/S14.md
git commit -m "Skladanie MeetNotes.app bez Xcode, staly podpis" -m "Staly certyfikat MeetNotes Dev, zeby TCC nie resetowal uprawnien po kazdej przebudowie. Info.plist: tylko mikrofon i dzwiek systemowy, nigdy ekran."
```

---

### Zadanie D2: Aplikacja

Status: ✅ wykonane (2026-10-12, S15 `a835dcc` + E4 `6915a71` + S15fix): kroki 1–8 odhaczone, `Build complete!`, `scripts/test.sh` 109/109 (bramka nie obejmuje `MeetNotesApp` — brak targetu testowego, BACKLOG), paczka podpisana „MeetNotes Dev". Aplikacja jeszcze nieuruchomiona — sprawdza D3 (użytkownik). Filtr po modalnościach z kroku 4 skompilowany przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet). Jedno zadanie, bo `ContentView` odwołuje się do wszystkich ekranów — osobne zadania wymagałyby zaślepek widoków, których w spike'u nie ma.

**Pliki:**
- Usuń: `Sources/MeetNotesApp/main.swift`
- Utwórz: `Sources/MeetNotesApp/AppModel.swift`, `RecordingController.swift`, `MeetNotesApp.swift`, `MeetingsView.swift`, `MeetingDetailView.swift`, `PresetsView.swift`, `SettingsView.swift`, `SetupView.swift`

**Interfejsy:**
- Pobiera: `SessionRecorder`, `SystemTapSource`, `RawMicrophoneSource`, `VoiceProcessedMicrophoneSource`, `SystemAudioCheck`, `EndReason` (A); `MeetNotesPaths`, `JSONFile`, `KeychainSecretStore`, `OpenAICompatibleClient`, `ProbeRunner`, `Preset`, `PresetsFile`, `ProvidersFile`, `GlobalSettings`, `ProbeCache`, `maskedKey`, `LanguageCode.selectable` (B); `TranscriptionRunner`, `RunSnapshot`, `RunDirectory`, `Transcript`, `Utterance` (C).
- Dostarcza: aplikację. `AppModel`: `section`, `providers`, `presets`, `settings`, `probeCache`, `models`, `sessions: [SessionItem]`, `activePreset`, `startRecording()`, `transcribe(sessionURL:preset:)`, `savePreset(_:) -> String?`, `addProvider(name:baseURL:key:)`, `refreshModels(_:)`, `probe(providerID:model:role:language:)`. Po zakończeniu nagrania transkrypcja rusza sama z aktywnym presetem.

- [x] **Krok 1: Model i sterowanie nagraniem.** Usuń `Sources/MeetNotesApp/main.swift`.

`Sources/MeetNotesApp/AppModel.swift`:

```swift
import AVFoundation
import Foundation
import MeetNotesProviders
import MeetNotesRecording
import MeetNotesSessionFormat
import MeetNotesTranscription
import Observation

enum Section: String, CaseIterable, Identifiable {
    case meetings = "Meetings", tasks = "Tasks", dictation = "Dictation", dictionary = "Dictionary"
    case presets = "Presets", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .meetings: "waveform"
        case .tasks: "checklist"
        case .dictation: "keyboard"
        case .dictionary: "book"
        case .presets: "slider.horizontal.3"
        case .settings: "gearshape"
        }
    }
}

/// Jedna sesja na osi czasu strony głównej.
struct SessionItem: Identifiable, Equatable {
    var id: String { url.lastPathComponent }
    var url: URL
    var summary: SessionSummary?
    var startedAt: Date
    var transcript: Transcript?
    var progress: Double?

    var duration: Double? {
        guard let t = summary?.tracks.first(where: { $0.id == "system" }) ?? summary?.tracks.first,
              let f = t.frames, t.sampleRate > 0 else { return nil }
        return Double(f) / t.sampleRate
    }
}

@MainActor
@Observable
final class AppModel {
    let paths = MeetNotesPaths.fromEnvironment()
    let secrets: any SecretStore = KeychainSecretStore()

    var section: Section = .meetings
    var providers = ProvidersFile()
    var presets = PresetsFile()
    var settings = GlobalSettings()
    var probeCache = ProbeCache()
    var models: [UUID: [ModelInfo]] = [:]
    var sessions: [SessionItem] = []
    var selectedSessionID: String?
    var activePresetID: UUID?
    var lastError: String?
    var showSetup = false

    let recording = RecordingController()

    init() {
        load()
        showSetup = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
    }

    var activePreset: Preset? {
        presets.presets.first { $0.id == (activePresetID ?? settings.defaultPresetID) } ?? presets.presets.first
    }

    func provider(_ id: UUID?) -> Provider? { providers.providers.first { $0.id == id } }

    func load() {
        do {
            providers = try JSONFile.load(ProvidersFile.self, from: paths.providers, default: ProvidersFile())
            presets = try JSONFile.load(PresetsFile.self, from: paths.presets, default: PresetsFile())
            settings = try JSONFile.load(GlobalSettings.self, from: paths.settings, default: GlobalSettings())
            probeCache = try JSONFile.load(ProbeCache.self, from: paths.probeCache, default: ProbeCache())
        } catch {
            lastError = "Couldn't read your settings: \(error)"
        }
        reloadSessions()
    }

    func save() {
        do {
            try JSONFile.save(providers, to: paths.providers)
            try JSONFile.save(presets, to: paths.presets)
            try JSONFile.save(settings, to: paths.settings)
            try JSONFile.save(probeCache, to: paths.probeCache)
        } catch {
            lastError = "Couldn't save your settings: \(error)"
        }
    }

    func reloadSessions() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: paths.sessions, includingPropertiesForKeys: nil)) ?? []
        sessions = dirs.compactMap { url -> SessionItem? in
            let sd = SessionDirectory(url: url)
            guard fm.fileExists(atPath: sd.journalURL.path) else { return nil }
            let summary = try? sd.summarize()
            let transcript = latestTranscript(in: url)
            return SessionItem(url: url, summary: summary, startedAt: summary?.wallClock ?? .distantPast, transcript: transcript)
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func latestTranscript(in session: URL) -> Transcript? {
        let runs = session.appendingPathComponent("runs")
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: runs.path)) ?? []).sorted()
        for id in ids.reversed() {
            if let t = try? JSONFile.load(Transcript?.self, from: RunDirectory(session: session, runID: id).transcript, default: nil) {
                return t
            }
        }
        return nil
    }

    // MARK: Dostawcy

    func client(for providerID: UUID) -> OpenAICompatibleClient? {
        guard let p = provider(providerID) else { return nil }
        return OpenAICompatibleClient(provider: p, key: try? secrets.get(p.id))
    }

    func addProvider(name: String, baseURL: URL, key: String) {
        let p = Provider(name: name, baseURL: baseURL)
        do {
            if !key.isEmpty { try secrets.set(p.id, key) }
            providers.providers.append(p)
            save()
        } catch {
            lastError = "Couldn't store the key in Keychain: \(error)"
        }
    }

    func removeProvider(_ id: UUID) {
        try? secrets.delete(id)
        providers.providers.removeAll { $0.id == id }
        save()
    }

    func refreshModels(_ id: UUID) async {
        guard let c = client(for: id) else { return }
        do { models[id] = try await c.listModels() } catch { lastError = "Couldn't refresh models: \(error)" }
    }

    func probe(providerID: UUID, model: String, role: Role, language: LanguageCode?) async {
        guard let c = client(for: providerID) else { return }
        let r = await ProbeRunner(client: c).probe(model: model, role: role, language: language)
        probeCache.record(r)
        save()
    }

    // MARK: Presety

    func savePreset(_ p: Preset) -> String? {
        do {
            try presets.upsert(p)
            if settings.defaultPresetID == nil { settings.defaultPresetID = p.id }
            save()
            return nil
        } catch PresetError.missingLanguage {
            return "Choose a language. Presets never detect it automatically."
        } catch PresetError.missingASR {
            return "Choose a speech-to-text model."
        } catch PresetError.missingName {
            return "Give the preset a name."
        } catch {
            return "\(error)"
        }
    }

    // MARK: Nagrywanie i transkrypcja

    func startRecording() {
        let dir = paths.sessions.appendingPathComponent(Self.sessionName(Date()))
        do {
            try recording.start(directory: dir) { [weak self] _ in
                Task { @MainActor in
                    self?.reloadSessions()
                    if let self, let preset = self.activePreset { self.transcribe(sessionURL: dir, preset: preset) }
                }
            }
            reloadSessions()
        } catch {
            lastError = "Couldn't start recording: \(error)"
        }
    }

    func transcribe(sessionURL: URL, preset: Preset) {
        guard let asr = preset.asr, let provider = provider(asr.providerID), let c = client(for: asr.providerID) else {
            lastError = "The preset's speech-to-text provider is missing."
            return
        }
        let probe = probeCache.result(provider: asr.providerID, model: asr.model, role: .asr)
        let snapshot: RunSnapshot
        do { snapshot = try RunSnapshot(preset: preset, provider: provider, probe: probe) } catch {
            lastError = "\(error)"
            return
        }
        let runID = Self.sessionName(Date())
        let id = sessionURL.lastPathComponent
        Task {
            do {
                _ = try await TranscriptionRunner(session: sessionURL, runID: runID, snapshot: snapshot, client: c).run { p in
                    Task { @MainActor in
                        if let i = self.sessions.firstIndex(where: { $0.id == id }) { self.sessions[i].progress = p.fraction }
                    }
                }
            } catch {
                self.lastError = "Transcription failed: \(error)"
            }
            self.reloadSessions()
        }
    }

    static func sessionName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return f.string(from: d) + "-" + UUID().uuidString.prefix(4).lowercased()
    }
}
```

`Sources/MeetNotesApp/RecordingController.swift`:

```swift
import AppKit
import Foundation
import MeetNotesRecording
import Observation
import SwiftUI

/// Stan trwającego nagrania dla interfejsu i pływającego okna.
@MainActor
@Observable
final class RecordingController {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastEndReason: EndReason?
    private var recorder: SessionRecorder?
    private var timer: Timer?
    private var started = Date()
    private var panel: NSPanel?

    func start(directory: URL, onEnded: @escaping @MainActor (EndReason) -> Void) throws {
        let r = SessionRecorder(directory: directory,
                                sources: [SystemTapSource(), RawMicrophoneSource()]) // bez VP: ściszałby Teams przez całe nagranie (S5, spec rdzenia §2 korekta 2026-09-29)
        r.onEnded = { reason in
            Task { @MainActor in
                self.finish(reason)
                onEnded(reason)
            }
        }
        try r.start()
        recorder = r
        isRecording = r.endReason == nil
        started = Date()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.elapsed = Date().timeIntervalSince(self.started)
                self.recorder?.tick()
            }
        }
        if isRecording { showPanel() }
    }

    func stop() { recorder?.stop(reason: .button) }

    private func finish(_ reason: EndReason) {
        isRecording = false
        lastEndReason = reason
        timer?.invalidate()
        timer = nil
        recorder = nil
        panel?.close()
        panel = nil
    }

    /// 🔀 Odstępstwa 1 i 2 z `docs/design/macos.md` §10: pływające okno zostaje na
    /// wierzchu, gdy aktywny jest Teams, i klik w nie nie odbiera fokusu spotkaniu.
    private func showPanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
                        styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Recording"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: RecordingPanelView(controller: self))
        p.center()
        p.orderFrontRegardless()
        panel = p
    }
}

struct RecordingPanelView: View {
    let controller: RecordingController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .accessibilityHidden(true)
            // Stan nigdy samym kolorem: napis i licznik (macos.md §6.1).
            Text("Recording \(Self.clock(controller.elapsed))")
                .monospacedDigit()
            Spacer()
            Button("Stop") { controller.stop() }
                .keyboardShortcut(".", modifiers: .command)
        }
        .padding(12)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
```

- [x] **Krok 2: Punkt wejścia i nawigacja.** `Sources/MeetNotesApp/MeetNotesApp.swift`:

```swift
import SwiftUI

/// 🔴 Bez Xcode nie ma pluginu `SwiftUIMacros`, a w SDK macOS 27 `@State`,
/// `@Entry`, `@Animatable` i `#Preview` są makrami. Nie używamy ich: model
/// aplikacji jest stałą struktury `App` (tworzonej raz), a stan lokalny widoków
/// mieszka w `ObservableObject` pod `@StateObject` (zwykłe opakowanie właściwości).
@main
struct MeetNotesApp: App {
    private let model = AppModel()

    var body: some Scene {
        WindowGroup("MeetNotes") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            // 🔀 Odstępstwo 3 (macos.md §10): ustawienia są zakładką, ale Settings… i Cmd-, zostają.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.section = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Recording") {
                Button(model.recording.isRecording ? "Stop Recording" : "Record Meeting") {
                    model.recording.isRecording ? model.recording.stop() : model.startRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.section) {
                ForEach(Section.allCases) { s in
                    Label(s.rawValue, systemImage: s.symbol).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch model.section {
            case .meetings: MeetingsView()
            case .presets: PresetsView()
            case .settings: SettingsView()
            case .tasks: LaterPhaseView(title: "Tasks", text: "Tasks with owners across meetings arrive with notes and speaker identity.")
            case .dictation: LaterPhaseView(title: "Dictation", text: "Dictation arrives in a later phase.")
            case .dictionary: LaterPhaseView(title: "Dictionary", text: "Your vocabulary and corrections from transcripts will live here.")
            }
        }
        .sheet(isPresented: $model.showSetup) { SetupView() }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct LaterPhaseView: View {
    let title: String
    let text: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "clock", description: Text(text))
    }
}
```

- [x] **Krok 3: Strona główna i widok spotkania.**

`Sources/MeetNotesApp/MeetingsView.swift`:

```swift
import MeetNotesProviders
import SwiftUI

/// Strona główna, wariant B (spec fazy 1, §1.2): oś nagrań po dniach. Szyna
/// „Coming up" i wyróżnione najbliższe spotkanie przychodzą z kalendarzem.
final class MeetingsViewState: ObservableObject {
    @Published var query = ""
}

struct MeetingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = MeetingsViewState()
    private var query: String { state.query }

    private var days: [(Date, [SessionItem])] {
        let cal = Calendar.current
        let filtered = model.sessions.filter { s in
            query.isEmpty || s.transcript?.utterances.contains { $0.text.localizedCaseInsensitiveContains(query) } == true
        }
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List(selection: $model.selectedSessionID) {
                if model.recording.isRecording {
                    RecordingRow(elapsed: model.recording.elapsed, preset: model.activePreset?.name ?? "")
                }
                ForEach(days, id: \.0) { day, items in
                    SwiftUI.Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(items) { item in SessionRow(item: item).tag(item.id) }
                    }
                }
            }
            .overlay {
                if model.sessions.isEmpty && !model.recording.isRecording {
                    ContentUnavailableView {
                        Label("Record your first meeting", systemImage: "waveform")
                    } description: {
                        Text("System audio and your microphone are recorded to separate files.")
                    } actions: {
                        Button("Record Meeting") { model.startRecording() }
                    }
                }
            }
            .searchable(text: $state.query, prompt: "Search transcripts")
            .navigationDestination(item: $model.selectedSessionID) { id in
                if let item = model.sessions.first(where: { $0.id == id }) { MeetingDetailView(item: item) }
            }
            .toolbar {
                ToolbarItemGroup {
                    PresetMenu()
                    Button {
                        model.recording.isRecording ? model.recording.stop() : model.startRecording()
                    } label: {
                        Label(model.recording.isRecording ? "Stop" : "Record", systemImage: model.recording.isRecording ? "stop.circle" : "record.circle")
                    }
                    .help(model.recording.isRecording ? "Stop recording" : "Record a meeting")
                }
            }
            .navigationTitle("Meetings")
        }
    }
}

/// 🔴 Preset — z językiem — widoczny przed startem (W§2, §6).
struct PresetMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.presets.presets) { p in
                Button(p.name + " · " + (p.language?.rawValue.uppercased() ?? "?")) { model.activePresetID = p.id }
            }
            Divider()
            Button("Edit Presets…") { model.section = .presets }
        } label: {
            Label(model.activePreset.map { "\($0.name) · \($0.language?.rawValue.uppercased() ?? "?")" } ?? "No preset",
                  systemImage: "slider.horizontal.3")
        }
        .help("Preset used for the next recording: language and models")
    }
}

struct RecordingRow: View {
    let elapsed: TimeInterval
    let preset: String
    var body: some View {
        HStack {
            Image(systemName: "record.circle").foregroundStyle(.red).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("Recording").font(.headline)
                Text("\(RecordingPanelView.clock(elapsed)) · \(preset)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

struct SessionRow: View {
    let item: SessionItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.startedAt.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                Text(item.duration.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            status
        }
    }

    @ViewBuilder private var status: some View {
        if let p = item.progress, p < 1 {
            ProgressView(value: p) { Text("Transcribing \(Int(p * 100))%") }.frame(width: 140)
        } else if item.summary?.crashed == true {
            Label("Recovered", systemImage: "bandage").foregroundStyle(.orange).help("The app stopped during this recording; the audio was kept")
        } else if let t = item.transcript {
            if t.languageFlagCount > 0 {
                Label("\(t.languageFlagCount) language flags", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                Label("Transcript ready", systemImage: "checkmark.circle")
            }
        } else {
            Text("Not transcribed").foregroundStyle(.secondary)
        }
    }
}
```

`Sources/MeetNotesApp/MeetingDetailView.swift`:

```swift
import AVFoundation
import MeetNotesProviders
import MeetNotesTranscription
import SwiftUI

/// Zalążek widoku spotkania w fazie 1: transkrypt i skok w nagraniu (W§1).
/// Odsłuch = ścieżka systemowa bit w bit (spec rdzenia §5); mikrofon osobno.
final class PlaybackState: ObservableObject {
    var player: AVAudioPlayer?
}

struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    @StateObject private var playback = PlaybackState()
    private var player: AVAudioPlayer? { playback.player }

    var body: some View {
        Group {
            if let t = item.transcript {
                List {
                    ForEach(Array(t.utterances.enumerated()), id: \.offset) { _, u in
                        UtteranceRow(utterance: u) { play(from: u.start) }
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
                    if let p = model.activePreset {
                        Button("Transcribe with \(p.name)") { model.transcribe(sessionURL: item.url, preset: p) }
                    }
                }
            }
        }
        .navigationTitle(item.startedAt.formatted(date: .abbreviated, time: .shortened))
        .toolbar {
            Button {
                if player?.isPlaying == true { player?.pause() } else { player?.play() }
            } label: {
                Label("Play", systemImage: "playpause")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play or pause")
        }
    }

    private func play(from t: Double) {
        if playback.player == nil {
            playback.player = try? AVAudioPlayer(contentsOf: item.url.appendingPathComponent("system.caf"))
        }
        player?.currentTime = max(0, t)
        player?.play()
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
```

- [x] **Krok 4: Presety.** `Sources/MeetNotesApp/PresetsView.swift`:

```swift
import MeetNotesProviders
import SwiftUI

final class PresetEditorState: ObservableObject {
    @Published var draft: Preset?
    @Published var error: String?
}

/// Presety (spec fazy 1, §1.5): język i modele jako jeden byt.
struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var state = PresetEditorState()

    var body: some View {
        HSplitView {
            List(model.presets.presets, selection: Binding(get: { state.draft?.id }, set: { id in
                state.draft = model.presets.presets.first { $0.id == id }
                state.error = nil
            })) { p in
                VStack(alignment: .leading) {
                    Text(p.name)
                    Text(p.asr?.model ?? "No speech-to-text model").font(.caption).foregroundStyle(.secondary)
                }
                .tag(p.id)
            }
            .frame(minWidth: 180, idealWidth: 200)
            .toolbar {
                Button { state.draft = Preset(name: "New preset", language: nil, asr: nil); state.error = nil } label: {
                    Label("New Preset", systemImage: "plus")
                }
                .help("New preset")
            }
            if state.draft != nil {
                PresetForm(state: state)
            } else {
                ContentUnavailableView("Choose a preset", systemImage: "slider.horizontal.3",
                                       description: Text("A preset ties a language to its models, so they can't drift apart."))
            }
        }
        .navigationTitle("Presets")
    }
}

struct PresetForm: View {
    @Environment(AppModel.self) private var model
    @ObservedObject var state: PresetEditorState

    private var draft: Binding<Preset> {
        Binding(get: { state.draft ?? Preset(name: "", language: nil, asr: nil) }, set: { state.draft = $0 })
    }

    var body: some View {
        Form {
            TextField("Name", text: draft.name)
            // 🔴 Bez wartości domyślnej i bez „Automatic" — P7.
            Picker("Language", selection: draft.language) {
                Text("Choose…").tag(LanguageCode?.none)
                ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
            }
            RoleEditor(title: "Speech to text", role: .asr, assignment: draft.asr, language: draft.wrappedValue.language)
            RoleEditor(title: "Correction", role: .correction, assignment: draft.correction, language: nil, hasPrompt: true)
            RoleEditor(title: "Summary", role: .summary, assignment: draft.summary, language: nil, hasPrompt: true)
            Picker("Notes language", selection: draft.notesLanguage) {
                Text("Same as preset").tag(LanguageCode?.none)
                ForEach(LanguageCode.selectable, id: \.code) { l in Text(l.name).tag(Optional(l.code)) }
            }
            Text("Embeddings are set once for the whole archive in Settings.").font(.caption).foregroundStyle(.secondary)
            if let e = state.error { Text(e).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Save") { state.error = state.draft.flatMap { model.savePreset($0) } }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
    }
}

/// Dostawca + model (z listy albo wpisany z ręki — §4.3) + wynik sondy.
struct RoleEditor: View {
    @Environment(AppModel.self) private var model
    let title: String
    let role: Role
    @Binding var assignment: RoleAssignment?
    let language: LanguageCode?
    var hasPrompt = false

    var body: some View {
        SwiftUI.Section(title) {
            Picker("Provider", selection: Binding(get: { assignment?.providerID }, set: { id in
                assignment = id.map { RoleAssignment(providerID: $0, model: assignment?.model ?? "", prompt: assignment?.prompt) }
            })) {
                Text("None").tag(UUID?.none)
                ForEach(model.providers.providers) { p in Text(p.name).tag(Optional(p.id)) }
            }
            if let a = assignment {
                // Lista to wygoda; wpisanie z ręki jest wymagane — mai-transcribe-2 nie jest na liście.
                TextField("Model", text: Binding(get: { a.model }, set: { assignment?.model = $0 }), prompt: Text("microsoft/mai-transcribe-2"))
                if let list = model.models[a.providerID], !list.isEmpty {
                    Menu("Choose from \(list.count) models") {
                        ForEach(list.prefix(300), id: \.id) { m in Button(m.id) { assignment?.model = m.id } }
                    }
                }
                HStack {
                    ProbeBadges(result: model.probeCache.result(provider: a.providerID, model: a.model, role: role))
                    Spacer()
                    Button("Test") { Task { await model.probe(providerID: a.providerID, model: a.model, role: role, language: language) } }
                        .disabled(a.model.isEmpty)
                        .help("Sends a short test request to check this model works in this role")
                }
                if hasPrompt {
                    TextEditor(text: Binding(get: { a.prompt ?? "" }, set: { assignment?.prompt = $0 }))
                        .frame(minHeight: 60)
                        .font(.body.monospaced())
                }
            }
        }
    }
}

/// Wynik sondy jako znaczniki, nie przypis drobnym drukiem (spec fazy 1, §9).
struct ProbeBadges: View {
    let result: ProbeResult?

    var body: some View {
        HStack(spacing: 6) {
            if let r = result {
                if r.works {
                    Label("Verified", systemImage: "checkmark.seal")
                    switch r.languageHandling {
                    case .enforced: Label("Language enforced", systemImage: "lock")
                    case .automatic:
                        Label("This model detects language itself — your language setting can't be enforced",
                              systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    case .filtered: Label("Language filtered", systemImage: "line.3.horizontal.decrease")
                    case .unknown: Label("Language handling unknown", systemImage: "questionmark.circle").foregroundStyle(.orange)
                    case nil: EmptyView()
                    }
                    if r.shape == .chatAudio { Text("No word timings").foregroundStyle(.secondary) }
                } else {
                    Label("Doesn't work in this role", systemImage: "xmark.octagon").foregroundStyle(.red).help(r.failure ?? "")
                }
            } else {
                Text("Not tested").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}
```

Następnie ⚠️ **zmiana nieweryfikowana — luka spike'u.** Spec fazy 1 §4 krok 2 wymaga filtra wstępnego po metadanych modelu; spike go nie ma. W `RoleEditor` zamień blok:

```swift
                if let list = model.models[a.providerID], !list.isEmpty {
                    Menu("Choose from \(list.count) models") {
                        ForEach(list.prefix(300), id: \.id) { m in Button(m.id) { assignment?.model = m.id } }
                    }
                }
```

na:

```swift
                if let all = model.models[a.providerID], !all.isEmpty {
                    // Filtr wstępny po modalnościach (spec fazy 1, §4, krok 2): zawęża, nie rozstrzyga —
                    // rozstrzyga sonda. Model transkrypcyjny i tak nie jest na liście (wpisanie z ręki).
                    let audio = all.filter { $0.inputModalities?.contains("audio") == true }
                    let list = role == .asr && !audio.isEmpty ? audio : all
                    Menu("Choose from \(list.count) models") {
                        ForEach(list.prefix(300), id: \.id) { m in Button(m.id) { assignment?.model = m.id } }
                    }
                }
```

- [x] **Krok 5: Ustawienia i setup.**

`Sources/MeetNotesApp/SettingsView.swift`:

```swift
import MeetNotesProviders
import SwiftUI

final class AddProviderState: ObservableObject {
    @Published var showing = false
    @Published var name = "OpenRouter"
    @Published var url = "https://openrouter.ai/api/v1"
    @Published var key = ""
}

/// Settings trzyma połączenia (dostawcy, klucze) i globalny embedding (§1.5).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var add = AddProviderState()

    var body: some View {
        @Bindable var model = model
        Form {
            SwiftUI.Section("Providers") {
                ForEach(model.providers.providers) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(p.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                            Text((try? model.secrets.get(p.id)).flatMap { $0 }.map(maskedKey) ?? "No key")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await model.refreshModels(p.id) } } label: { Label("Refresh Models", systemImage: "arrow.clockwise") }
                            .help("Refresh the model list")
                        Button(role: .destructive) { model.removeProvider(p.id) } label: { Label("Remove", systemImage: "trash") }
                            .help("Remove this provider and its key")
                    }
                }
                Button("Add Provider…") { add.showing = true }
            }
            SwiftUI.Section("Archive") {
                RoleEditor(title: "Embeddings (whole archive)", role: .embedding, assignment: $model.settings.embedding, language: nil)
                Text("Changing the embedding model re-indexes the whole archive, never part of it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Setup") {
                Button("Check Permissions…") { model.showSetup = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: model.settings) { model.save() }
        .sheet(isPresented: $add.showing) {
            Form {
                TextField("Name", text: $add.name)
                TextField("Base URL", text: $add.url)
                SecureField("API key", text: $add.key)
                HStack {
                    Button("Cancel") { add.showing = false }
                    Spacer()
                    Button("Add") {
                        if let u = URL(string: add.url) { model.addProvider(name: add.name, baseURL: u, key: add.key) }
                        add.key = ""
                        add.showing = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 420)
        }
    }
}
```

`Sources/MeetNotesApp/SetupView.swift`:

```swift
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
                        state.systemAudio = await SystemAudioCheck.run()
                        state.checking = false
                    }
                }
                .disabled(state.checking)
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
```

- [x] **Krok 6: Zbuduj.** `swift build --product MeetNotesApp` — oczekiwane: `Build complete!`. Jeśli pojawi się `plugin for module 'SwiftUIMacros' not found`, ktoś użył `@State` — zamień na `ObservableObject` + `@StateObject` (przegląd §4). Nie instaluj Xcode, żeby to obejść: to decyzja użytkownika.

- [x] **Krok 7: Złóż paczkę i testy.** `scripts/bundle.sh` — `.build/MeetNotes.app`. `scripts/test.sh` — `109/109`.

- [x] **Krok 8: Commit.**

```bash
git add Sources/MeetNotesApp
git commit -m "Aplikacja: nawigacja, os nagran, presety, ustawienia, setup, plywajace okno" -m "Bez @State - w SDK macOS 27 to makro z pluginu dostepnego tylko z Xcode. Stan lokalny w ObservableObject pod @StateObject."
```

---

### Zadanie D3: Odbiór ręczny

Status: nigdy niewykonane. **Wymaga użytkownika** — monity TCC, prawdziwe spotkanie, klucz API.

**Pliki:**
- Utwórz: `docs/superpowers/spikes/2026-09-24-d3-odbior-aplikacji.md` — lista kroków z wynikiem ✅/❌ i uwagami.

- [ ] **Krok 1: Pierwsze uruchomienie.** `rm -rf .devdata && scripts/run.sh`. Oczekiwane: okno setupu. „Allow" przy mikrofonie → monit systemowy z tekstem z `NSMicrophoneUsageDescription`. „Test" przy dźwięku systemowym → słychać krótki ton, stan „Working — the test tone was captured." Monitu o nagrywanie ekranu **nie ma**. O6: odmów uprawnienia dźwięku systemowego i kliknij Test — stan „The test tone wasn't captured…" i przycisk „Open System Audio Settings", który ma otworzyć panel *Nagrywanie ekranu i dźwięku systemowego*. Jeśli otwiera coś innego, zanotuj (kotwica `Privacy_AudioCapture` jest z pamięci) i zamień w `SetupView` na ogólne `x-apple.systempreferences:com.apple.preference.security?Privacy`. Włącz uprawnienie z powrotem.

- [ ] **Krok 2: Odmowa mikrofonu.** W Ustawieniach systemowych wyłącz mikrofon dla MeetNotes, nagraj 15 s z grającym dźwiękiem. W `.devdata/sessions/<sesja>/session.json`: `mic_raw` i `mic_aec` z `permissionDenied: microphone`, `system` z ramkami. Włącz mikrofon z powrotem.

- [ ] **Krok 3: Dostawca i klucz (P8).** Settings → Add Provider… → OpenRouter z kluczem. Wiersz pokazuje `••••` i cztery ostatnie znaki. `grep -c "sk-or" .devdata/providers.json` → `0`. Zamknij i otwórz aplikację: klucz nadal zamaskowany (pęk kluczy). Refresh Models → lista się pojawia.

- [ ] **Krok 4: Preset (P7, P2, P10).** Presets → +. Save bez języka → „Choose a language. Presets never detect it automatically." i preset nie pojawia się na liście. Język Polish, dostawca OpenRouter, model wpisany z ręki `microsoft/mai-transcribe-2`, Test → „Verified" i „Language enforced". Save. Chip przy Record pokazuje „Polish · PL".

- [ ] **Krok 5: Nagranie z Teamsem na pierwszym planie.** Record → pływające okno „Recording 00:00:0x". Przełącz się na Teams albo przeglądarkę: okno zostaje. Kliknij Stop w oknie: fokus zostaje na Teamsie (odstępstwa 1 i 2). Cmd-. w pływającym oknie też zatrzymuje.

- [ ] **Krok 6: Transkrypcja i skok w nagraniu.** Po Stop wiersz sesji pokazuje „Transcribing N%", potem „Transcript ready". Otwórz sesję: wypowiedzi Me/Them; klik w czas odtwarza od tego miejsca; spacja pauzuje.

- [ ] **Krok 7: Cmd-, i klawiatura.** Cmd-, przełącza na Settings. Tab/Shift-Tab przechodzi po kontrolkach ustawień i presetów (Full Keyboard Access włączony w systemie).

- [ ] **Krok 8: Wygląd.** Tryb ciemny i jasny — teksty czytelne. Reduce Motion włączone → ikona w pływającym oknie nie pulsuje. VoiceOver na liście sesji czyta godzinę i stan.

- [ ] **Krok 8b: Poprawki z E4.**
  - Pływające okno bez nagrania (Recording → Show Recording Window, ⌥⌘R): wybór presetu i Record. Nagrywanie bez ważnego presetu → komunikat i przejście do Presets.
  - W trakcie nagrania zmień chip presetu w oknie głównym: pływające okno dalej pokazuje preset ze startu, a transkrypcja po Stop idzie w **jego** języku (`<sesja>/runs/<id>/run.json`).
  - **Prawdziwe spotkanie w Teamsie** (Hermes 3.3): 2 minuty rozmowy, potem odsłuch `system.caf` — słychać rozmówcę.
  - Klik w czas wypowiedzi „Me" odtwarza **Twój** głos, „Them" — rozmówcę.
  - Zakończ aplikację w trakcie transkrypcji (Cmd-Q), uruchom ponownie: wiersz „Interrupted", w widoku spotkania „Resume Transcription"; po wznowieniu `requestCount` w `run.json` = liczba brakujących okien.
  - Otwórz widok spotkania przed końcem transkrypcji: po zakończeniu transkrypt pojawia się bez ponownej nawigacji (ChatGPT 🟡). Jeśli nie — zanotuj.

- [ ] **Krok 9: Przebudowa a TCC.** `scripts/run.sh` jeszcze raz (z certyfikatem z D1): **brak** ponownych monitów o mikrofon. Dla porównania `MEETNOTES_SIGN_IDENTITY=- scripts/run.sh` — monit wraca (potwierdza spec rdzenia §8). Po teście wróć do podpisu certyfikatem.

- [ ] **Krok 10: Zapisz wyniki i commit.**

```bash
git add docs/superpowers/spikes
git commit -m "Odbior reczny aplikacji fazy 1"
```
