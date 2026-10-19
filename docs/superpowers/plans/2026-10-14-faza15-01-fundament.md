# Plan 1.5-A — fundament: migawki UI, język Auto, lista modeli

> **Dla wykonawców:** najpierw `2026-10-14-faza15-00-przeglad.md` §0 (zasady, modele, STOP) i §3 (licznik testów). Kroki używają pól `- [ ]`. Znaczniki `[haiku]` / `[sonnet]` / `[opus]` przy krokach = model wykonawcy (przegląd §0).

**Cel:** narzędzie migawek ekranów (T0), język „Auto" w domenie presetu i potoku (T1), `listModels(output:)` z ponowieniem i lokalnym filtrem (T2).

**Spec:** `docs/superpowers/specs/2026-10-14-faza15-design.md` §3 (decyzje 8, 12, 13, 17), §4.2, §8 (testy 7, 8).

**Wspólne ograniczenia:** przegląd, sekcja „Wspólne ograniczenia". Kod w T1–T2 jest ⚠️ (nieskompilowany w repo): błąd kompilacji napraw minimalnie i opisz w raporcie; inna rozbieżność = STOP.

---

### Zadanie T0: narzędzie migawek ekranów (macos.md §9)

Status: ⚠️ **spike** — model **Opus** wykonuje całe zadanie. Kod poniżej to szkielet do sprawdzenia, nie gotowy produkt.

**Dlaczego tak:** wszystkie widoki leżą w `MeetNotesApp` (`executableTarget`), a osobny cel debugowy nie może go zaimportować. Dlatego tryb migawek jest **wewnątrz aplikacji**, włączany zmienną środowiskową, renderuje ekrany poza ekranem do PNG i kończy proces. Dane z katalogu fixture (`MEETNOTES_DATA_DIR`), bez arkusza setupu, bez TCC i pęku kluczy.

**Pliki:**
- Utwórz: `Sources/MeetNotesApp/Snapshots.swift`, `scripts/snapshot.sh`
- Zmień: `Sources/MeetNotesApp/MeetNotesApp.swift` (init), `.gitignore` (`.design/`)

**Interfejsy:**
- Dostarcza: `Snapshots.directory: URL?`, `Snapshots.render(_ name:, size:, dark:, model:, content:) throws`, `Snapshots.runAll(model:)` (lista ekranów — kolejne zadania dopisują swoje), `scripts/snapshot.sh [nazwa]` → PNG w `.design/review/`.

- [x] **Krok 1 `[opus]`: ignoruj katalog wyników.** Dopisz do `.gitignore` linię `.design/`.

- [x] **Krok 2 `[opus]`: szkielet.** Utwórz `Sources/MeetNotesApp/Snapshots.swift`:

```swift
import AppKit
import MeetNotesProviders
import SwiftUI

/// Tryb migawek (macos.md §9): `MEETNOTES_SNAPSHOT_DIR=<katalog>` renderuje ekrany do PNG i kończy proces.
/// Dowód w raporcie: „migawka" (ten plik), nie „zrzut na żywo".
enum SnapshotError: Error { case noBitmap, noPNG }

@MainActor
enum Snapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["MEETNOTES_SNAPSHOT_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    static func render<V: View>(_ name: String, size: CGSize, dark: Bool, model: AppModel,
                                @ViewBuilder _ content: () -> V) throws {
        let host = NSHostingView(rootView: content().environment(model).frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SnapshotError.noBitmap }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.noPNG }
        // `directory!` jest bezpieczne: `render` woła tylko `runAll`, a `runAll` startuje z `init()` dopiero po sprawdzeniu
        // `directory != nil`. Wywołanie `render` z innego miejsca wymaga guarda.
        try FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        try png.write(to: directory!.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    /// Fixture: presety i dostawca zapisane do katalogu danych, potem `load()`. Kolejne zadania dopisują sesje i stany.
    static func seed(_ model: AppModel) throws {
        let provider = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        var presets = PresetsFile()
        try presets.upsert(Preset(name: "Polish", language: .polish,
                                  asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2")))
        try JSONFile.save(ProvidersFile(providers: [provider]), to: model.paths.providers)
        try JSONFile.save(presets, to: model.paths.presets)
        model.load()
        model.showSetup = false
    }

    static func runAll(model: AppModel) {
        do {
            try seed(model)
            for dark in [false, true] {
                try render("presets", size: CGSize(width: 900, height: 600), dark: dark, model: model) { PresetsView() }
                try render("meetings", size: CGSize(width: 900, height: 600), dark: dark, model: model) { MeetingsView() }
            }
            print("snapshots: \(directory!.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshots: \(error)\n".utf8))
            exit(1)
        }
    }
}
```

W `MeetNotesApp` (struct `MeetNotesApp: App`) dodaj inicjalizator (model jest `private let model = AppModel()`):

```swift
    init() {
        if Snapshots.directory != nil {
            let model = self.model
            DispatchQueue.main.async { MainActor.assumeIsolated { Snapshots.runAll(model: model) } }
        }
    }
```

- [x] **Krok 3 `[opus]`: spike — czy renderuje.** Utwórz `scripts/snapshot.sh` (`chmod +x`):

```bash
#!/bin/bash
# Renderuje ekrany aplikacji do PNG w .design/review/ (macos.md §9). Dane: świeży katalog fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=".design/review"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT
swift build --product MeetNotesApp >&2
BIN="$(swift build --show-bin-path)/MeetNotesApp"
MEETNOTES_DATA_DIR="$DATA" MEETNOTES_SNAPSHOT_DIR="$OUT" "$BIN"
ls "$OUT"
```

Uruchom `scripts/snapshot.sh`, potem `Read` na `.design/review/presets-light.png` i `meetings-light.png`.
**Kryterium:** na PNG widać wiersz presetu „Polish" na liście, pola formularza po wybraniu presetu **albo** (gdy nic nie wybrano) panel „Choose a preset", a na `meetings` — pusty stan „Record your first meeting". Nie biała plansza.
**Jeśli lista (`List`) lub pola tekstowe nie renderują się poza ekranem → STOP** (przegląd §0): raport z opisem, co się nie renderuje i co spróbowano (np. `window.orderBack`, krótki `RunLoop.run` przed `cacheDisplay`); decyzja użytkownika: odbiór ręczny po T3, T4, T7, T8, T9, T10 zamiast migawek. Wynik tego kroku wpisz do raportu `F15-T0`.

- [x] **Krok 4 `[opus]`: commit.**

```bash
git add .gitignore Sources/MeetNotesApp/Snapshots.swift Sources/MeetNotesApp/MeetNotesApp.swift scripts/snapshot.sh docs/superpowers/plans
git commit -m "T0: tryb migawek ekranów (MEETNOTES_SNAPSHOT_DIR, scripts/snapshot.sh)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [x] **Krok 5 `[opus]`: bramka.** `scripts/test.sh` — oczekiwane: `111/111` (zadanie nie dodaje testów).

---

### Zadanie T1: język Auto w presecie i potoku

Status: ⚠️ nieskompilowane. **Przegląd Opusa po zadaniu (krok 12).**

**Spec:** §3 decyzje 8 i 13, §4.2. **Zasada:** `LanguageCode` nadal nie przyjmuje `auto`; Auto = `language == nil && languageAuto == true`. Presetów **nie normalizujemy** przy wczytywaniu. **Przy Auto strażnik języka PL/EN jest pomijany, ale `LanguageGuard.nonLatinScript` oznacza wypowiedź, w której większość liter nie jest łacińska** (decyzja użytkownika 2026-10-14; Granola „Multi" zamieniła polski w rosyjski bełkot) — flaga `languageMismatch` i wyłączenie z notatek, jak przy złym języku.

**Pliki:**
- Zmień: `Sources/MeetNotesProviders/Preset.swift`, `Sources/MeetNotesProviders/LanguageCode.swift`, `Sources/MeetNotesTranscription/Transcript.swift` (`RunSnapshot`), `Sources/MeetNotesTranscription/Merger.swift`, `Sources/MeetNotesTranscription/LanguageGuard.swift`, `Sources/meetnotes-cli/CLI.swift`, `Sources/MeetNotesApp/AppModel.swift`, `Sources/MeetNotesApp/MeetingsView.swift`
- Test: `Tests/MeetNotesProvidersTests/PresetTests.swift`, `Tests/MeetNotesProvidersTests/ClientTests.swift`, `Tests/MeetNotesTranscriptionTests/RunnerTests.swift`, `Tests/MeetNotesTranscriptionTests/SessionFixtures.swift`, `Tests/MeetNotesTranscriptionTests/LanguageGuardTests.swift`

**Wszystkie miejsca, w których język ma znaczenie** (wynik `rg -n "snapshot.language|\.language\b|merge\(|mismatch\(|validate\(\)|missingLanguage|Automatic|automatically" Sources` z 2026-10-14):

| Miejsce | Co robi dziś | Zmiana w T1 |
|---|---|---|
| `Preset.swift:49-53` `validate()` | `guard language != nil` | przepuszcza też Auto |
| `Transcript.swift:73` `RunSnapshot.init` | `guard let language = preset.language` | `language` opcjonalny |
| `Transcript.swift:~65` `RunSnapshot.language` | `LanguageCode` | `LanguageCode?` |
| `Merger.swift:34,70` `merge`/`mismatch` | język wymagany | `LanguageCode?`; nil = Auto: bez strażnika PL/EN, ale z `nonLatinScript` |
| `LanguageGuard.swift` | tylko `mismatch(_:expected:)` dla PL/EN | + `nonLatinScript(_:)` (tylko przy Auto) |
| `TranscriptionRunner.swift:123,142` | podaje `snapshot.language` | **bez zmian** (opcjonalny przechodzi) |
| `OpenAICompatibleClient.swift` `transcribe` | `if let language` dodaje pole | **bez zmian** (kontrakt już dopuszcza nil) |
| `AppModel.swift:188,254` | klucz cache `p.language` | **bez zmian** (nil → klucz `-`) |
| `AppModel.swift:195-196` `savePreset` | „Presets never detect it automatically." | nowy komunikat |
| `AppModel.swift:246` `label` | `language?.rawValue.uppercased() ?? "?"` | `p.languageLabel` |
| `MeetingsView.swift:76,81` `PresetMenu` | to samo | `languageLabel` |
| `CLI.swift:178-201` `transcribe` | `--language` obowiązkowe, `try LanguageCode` | przyjmuje `auto` (tylko pomiary) |
| `PresetsView.swift:55-60` | Picker bez Auto, komentarz „bez Automatic" | **T3** (przepisuje ekran) |
| `Probe.swift:60-64` | `language ?? .english` | **bez zmian** (Auto nie klasyfikuje obsługi języka) |

**Interfejsy:**
- Dostarcza: `Preset.languageAuto: Bool?`, `Preset.isAutoLanguage: Bool`, `Preset.languageLabel: String` (`"PL"`, `"Auto ⚠"`, `"?"`), `Preset.languageChoice: LanguageChoice` (get/set), `enum LanguageChoice: Hashable, Sendable { case unset, auto, code(LanguageCode) }`, `LanguageCode.englishName: String`, `RunSnapshot.language: LanguageCode?`, `Merger.merge(..., language: LanguageCode?, ...)`, `LanguageGuard.nonLatinScript(_:) -> LanguageCode?`.

- [x] **Krok 1 `[sonnet]`: testy (najpierw).** Dopisz na końcu `Tests/MeetNotesProvidersTests/PresetTests.swift`:

```swift
@Test func autoLanguagePresetValidatesButStillNeedsAnExplicitChoice() throws {
    var p = Preset(name: "Mixed", language: nil, asr: asr, languageAuto: true)
    try p.validate()
    #expect(p.isAutoLanguage)
    #expect(p.languageLabel == "Auto ⚠")
    #expect(p.languageChoice == .auto)
    p.languageChoice = .code(.polish)
    #expect(p.language == .polish && p.languageAuto == nil && !p.isAutoLanguage)
    #expect(p.languageLabel == "PL")
    p.languageChoice = .unset
    #expect(throws: PresetError.missingLanguage) { try p.validate() }
    p.languageAuto = false
    #expect(throws: PresetError.missingLanguage) { try p.validate() }
}

@Test func phaseOnePresetJSONStillDecodes() throws {
    // Preset zapisany w fazie 1: bez `languageAuto`, ze `summary.prompt`. Nie wolno go ani odrzucić, ani po cichu zmienić.
    let json = """
    {"id":"00000000-0000-0000-0000-0000000000AA","name":"Polish","language":"pl",
     "asr":{"providerID":"00000000-0000-0000-0000-000000000001","model":"microsoft/mai-transcribe-2"},
     "summary":{"providerID":"00000000-0000-0000-0000-000000000001","model":"s","prompt":"Be brief"}}
    """
    let p = try JSONDecoder().decode(Preset.self, from: Data(json.utf8))
    #expect(p.languageAuto == nil)
    #expect(p.language == .polish)
    #expect(p.summary?.prompt == "Be brief")
    try p.validate()
    let again = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(p))
    #expect(again == p)
}
```

Dopisz na końcu `Tests/MeetNotesProvidersTests/ClientTests.swift`:

```swift
@Test func autoLanguageOmitsTheLanguageField() async throws {
    let http = StubHTTP { _, _ in ok(["text": "x"]) }
    _ = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http)
        .transcribe(wav: ProbeClips.polish.wav, model: "m", language: nil, shape: .audioTranscriptions)
    #expect(http.calls[0].body["language"] == nil)
}
```

Dopisz helper na końcu `Tests/MeetNotesTranscriptionTests/SessionFixtures.swift`:

```swift
func autoSnapshot() throws -> RunSnapshot {
    let provider = Provider(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "OpenRouter",
                            baseURL: URL(string: "https://openrouter.ai/api/v1")!)
    let preset = Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Mixed", language: nil,
                        asr: RoleAssignment(providerID: provider.id, model: "microsoft/mai-transcribe-2"), languageAuto: true)
    return try RunSnapshot(preset: preset, provider: provider, probe: nil)
}
```

Dopisz na końcu `Tests/MeetNotesTranscriptionTests/RunnerTests.swift`:

```swift
@Test func autoLanguageSkipsTheLanguageGuard() async throws {
    // Auto: nie ma języka, którego strażnik miałby pilnować — angielszczyzna w „polskiej" rozmowie nie jest oznaczana.
    struct EnglishASR: HTTPClient {
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let d = try JSONSerialization.data(withJSONObject: ["text": "I think there is a problem with the production of the products."])
            return (d, HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000) + tone(seconds: 3, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    let snap = try autoSnapshot()
    #expect(snap.language == nil)
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: snap, client: client(EnglishASR())).run()
    let u = try #require(t.utterances.first)
    #expect(u.languageMismatch == nil)
    #expect(!u.excludedFromNotes)
}

@Test func phaseOneInputJSONKeepsItsShapeAndResumes() async throws {
    // Lekcja E6: nowe pola tylko opcjonalne. Wznowienie po zmianie kodu nie może dać `inputMismatch`.
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000) + tone(seconds: 3, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(ListeningASR())).run()
    let text = try String(contentsOf: RunDirectory(session: dir, runID: "r1").input, encoding: .utf8)
    #expect(text.contains("\"language\" : \"pl\"")) // język jawny nadal zapisany kluczem z fazy 1
    #expect(!text.contains("languageAuto"))          // nowego klucza nie ma, dopóki nie jest ustawiony
    let again = ListeningASR()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try snapshot(), client: client(again)).run()
    #expect(again.requests == 0) // opłacone okna z dysku, bez inputMismatch
}

@Test func autoLanguageFlagsGibberishInAnotherScript() async throws {
    // Granola „Multi" zamieniła polską wypowiedź w rosyjski bełkot. Przy Auto taki tekst jest oznaczony i poza notatkami.
    struct CyrillicASR: HTTPClient {
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let d = try JSONSerialization.data(withJSONObject: ["text": "Привет это проверка связи с вами сегодня"])
            return (d, HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000) + tone(seconds: 3, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    let t = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: try autoSnapshot(), client: client(CyrillicASR())).run()
    let u = try #require(t.utterances.first)
    #expect(u.languageMismatch == (try LanguageCode("ru")))
    #expect(u.excludedFromNotes)
}
```

Dopisz na końcu `Tests/MeetNotesTranscriptionTests/LanguageGuardTests.swift`:

```swift
@Test func nonLatinScriptIsDetectedByMajority() throws {
    #expect(LanguageGuard.nonLatinScript("Привет, это проверка связи") == (try LanguageCode("ru")))
    #expect(LanguageGuard.nonLatinScript("これは日本語のテストです") == (try LanguageCode("ja")))
    #expect(LanguageGuard.nonLatinScript("To jest zwykłe polskie zdanie z ąę") == nil)
    #expect(LanguageGuard.nonLatinScript("Spotkanie o Москва i Київ jutro rano") == nil) // większość łacińska — jeden cudzy wyraz to nie bełkot
    #expect(LanguageGuard.nonLatinScript("Да") == nil) // za mało liter, żeby orzekać
    #expect(LanguageGuard.nonLatinScript("Prognoza na sobotę, 9 000 kontaktów") == nil)
}
```

- [x] **Krok 1b `[sonnet]`: fixtury z prawdziwych plików fazy 1 i dwa testy zgodności wstecznej (Review Luna #3).** Skopiuj do repo **prawdziwe** pliki z `.devdata` (nazwy, adres i UUID — bez sekretów) i sprawdź grepem, że nie ma w nich sekretów:

```bash
mkdir -p Tests/MeetNotesProvidersTests/Fixtures Tests/MeetNotesTranscriptionTests/Fixtures
cp .devdata/providers.json Tests/MeetNotesProvidersTests/Fixtures/phase1-providers.json
cp .devdata/presets.json Tests/MeetNotesProvidersTests/Fixtures/phase1-presets.json
INPUT="$(ls -t .devdata/sessions/*/runs/*/input.json | head -1)"
cp "$INPUT" Tests/MeetNotesTranscriptionTests/Fixtures/phase1-input.json
! grep -il 'sk-\|bearer\|api[_-]key\|secret' Tests/*/Fixtures/* && echo "fixtures: bez sekretów"
```
Oczekiwane: „fixtures: bez sekretów" (inaczej **STOP**: usuń skopiowane pliki i zgłoś). W `Package.swift` dodaj `exclude: ["Fixtures"]` do celów testowych `MeetNotesProvidersTests` i `MeetNotesTranscriptionTests` (SwiftPM nie traktuje ich wtedy jako nieobsłużonych zasobów), np. `.testTarget(name: "MeetNotesProvidersTests", dependencies: ["MeetNotesProviders"], exclude: ["Fixtures"])`.

Dopisz na końcu `Tests/MeetNotesProvidersTests/PresetTests.swift`:

```swift
private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
}

@Test func realPhaseOnePresetsAndProvidersStillDecode() throws {
    // Prawdziwe pliki z fazy 1 (E6): wczytują się, a ponowne zakodowanie nie dodaje ani nie gubi kluczy.
    let rawPresets = try fixture("phase1-presets.json")
    let presets = try JSONDecoder().decode(PresetsFile.self, from: rawPresets)
    #expect(presets.presets.count == 2)
    for p in presets.presets {
        try p.validate()
        #expect(p.languageAuto == nil) // stary plik nie ma nowego klucza i nie dostaje go z nil
    }
    #expect(presets.presets.first { $0.name == "Polski" }?.summary?.model == "deepseek/deepseek-v4.1-flash")
    let rawProviders = try fixture("phase1-providers.json")
    let providers = try JSONDecoder().decode(ProvidersFile.self, from: rawProviders)
    #expect(providers.providers.map(\.name) == ["OpenRouter"])
    for (raw, again) in [(rawPresets, try JSONEncoder().encode(presets)), (rawProviders, try JSONEncoder().encode(providers))] {
        let a = try JSONSerialization.jsonObject(with: raw) as? NSDictionary
        let b = try JSONSerialization.jsonObject(with: again) as? NSDictionary
        #expect(a == b)
    }
}
```

Dopisz na końcu `Tests/MeetNotesTranscriptionTests/RunnerTests.swift`:

```swift
private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
}

@Test func realPhaseOneInputJSONDecodesRoundTripsAndResumes() async throws {
    // Prawdziwy input.json z sesji fazy 1: stara migawka wczytuje się, nic się nie zmienia po ponownym zakodowaniu
    // i wznowienie z niej nie daje inputMismatch ani nie płaci drugi raz.
    let raw = try fixture("phase1-input.json")
    let input = try JSONDecoder().decode(RunInput.self, from: raw)
    #expect(input.snapshot.language == .polish)
    #expect(input.snapshot.preset.summary?.model == "deepseek/deepseek-v4.1-flash")
    let a = try JSONSerialization.jsonObject(with: raw) as? NSDictionary
    let b = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? NSDictionary
    #expect(a == b) // ani dodanych, ani zgubionych kluczy
    let dir = try makeSession(system: silence(seconds: 2, rate: 16_000) + tone(seconds: 3, rate: 16_000) + silence(seconds: 2, rate: 16_000))
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: input.snapshot, client: client(ListeningASR())).run()
    let second = ListeningASR()
    _ = try await TranscriptionRunner(session: dir, runID: "r1", snapshot: input.snapshot, client: client(second)).run()
    #expect(second.requests == 0)
}
```

- [x] **Krok 2 `[haiku]`: czerwone.** `scripts/test.sh`. Oczekiwane: **błąd kompilacji** (`languageAuto`, `isAutoLanguage`, `languageLabel`, `languageChoice`, `autoSnapshot` bez `languageAuto`). Inny wynik (np. zielone) = STOP.

- [x] **Krok 3 `[sonnet]`: `LanguageCode.englishName`.** W `Sources/MeetNotesProviders/LanguageCode.swift` dopisz po `description`:

```swift
    /// Nazwa po angielsku (do promptów i interfejsu): „Polish"; nieznany kod → sam kod.
    public var englishName: String { Self.selectable.first { $0.code == self }?.name ?? rawValue }
```

- [x] **Krok 4 `[sonnet]`: `Preset`.** W `Sources/MeetNotesProviders/Preset.swift`:
  (a) przed `public struct Preset` dodaj:

```swift
/// Wybór języka w edytorze presetu. `auto` to opcja awaryjna (spotkania mieszane), nigdy domyślna.
public enum LanguageChoice: Hashable, Sendable {
    case unset
    case auto
    case code(LanguageCode)
}
```
  (b) po polu `notesLanguage` dodaj pole i zaktualizuj `init`:

```swift
    /// `true` = język „Auto" (spec 1.5 §3.8): tylko razem z `language == nil`. Opcjonalne — stare pliki go nie mają.
    public var languageAuto: Bool?

    public init(id: UUID = UUID(), name: String, language: LanguageCode?, asr: RoleAssignment?,
                correction: RoleAssignment? = nil, summary: RoleAssignment? = nil, notesLanguage: LanguageCode? = nil,
                languageAuto: Bool? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.asr = asr
        self.correction = correction
        self.summary = summary
        self.notesLanguage = notesLanguage
        self.languageAuto = languageAuto
    }

    public var isAutoLanguage: Bool { language == nil && languageAuto == true }

    /// Krótka etykieta do list i chipów: „PL", „Auto ⚠", „?".
    public var languageLabel: String { isAutoLanguage ? "Auto ⚠" : (language?.rawValue.uppercased() ?? "?") }

    public var languageChoice: LanguageChoice {
        get { isAutoLanguage ? .auto : (language.map { .code($0) } ?? .unset) }
        set {
            switch newValue {
            case .unset: language = nil; languageAuto = nil
            case .auto: language = nil; languageAuto = true
            case .code(let c): language = c; languageAuto = nil
            }
        }
    }
```
  (usuń stary `init`). (c) w `validate()` zamień `guard language != nil else { throw PresetError.missingLanguage }` na `guard language != nil || isAutoLanguage else { throw PresetError.missingLanguage }`.

- [x] **Krok 5 `[sonnet]`: `RunSnapshot` i `Merger`.** W `Sources/MeetNotesTranscription/Transcript.swift`: `public var language: LanguageCode` → `public var language: LanguageCode?`; w `init` zamień linię `guard let asr = preset.asr, let language = preset.language else { throw PresetError.missingASR }` na `guard let asr = preset.asr else { throw PresetError.missingASR }` i `self.language = language` na `self.language = preset.language` (nil = Auto; `validate()` wyżej już odrzuca preset bez języka i bez Auto). W `Sources/MeetNotesTranscription/Merger.swift`: parametr `language: LanguageCode` → `language: LanguageCode?` i pętla końcowa:

```swift
        for i in utterances.indices {
            let text = utterances[i].text
            if let language {
                utterances[i].languageMismatch = LanguageGuard.mismatch(text, expected: language)
            } else {
                // Auto: nie ma oczekiwanego języka, więc strażnik PL/EN milczy; tekst w większości w obcym alfabecie
                // to bełkot (spec 1.5, decyzja użytkownika 2026-10-14) — flaga i poza notatkami.
                utterances[i].languageMismatch = LanguageGuard.nonLatinScript(text)
            }
        }
```
W `Sources/MeetNotesTranscription/LanguageGuard.swift` dopisz w `enum LanguageGuard` (po `mismatch`):

```swift
    /// Auto: wypowiedź, w której większość liter nie jest łacińska, to bełkot (Granola „Multi" na polskim → cyrylica).
    /// Zwraca język dominującego obcego alfabetu (`ru`, `el`, `ja`…, a dla nieznanego `zz`); za mało liter albo większość
    /// łacińska → `nil` (jeden cudzy wyraz w polskim zdaniu nie jest bełkotem).
    public static func nonLatinScript(_ text: String) -> LanguageCode? {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard letters.count >= 4 else { return nil }
        let foreign = letters.filter { !isLatin($0) }
        guard foreign.count * 2 > letters.count else { return nil }
        let code: String
        switch foreign[foreign.startIndex].value {
        case 0x0400...0x052F: code = "ru"
        case 0x0370...0x03FF: code = "el"
        case 0x0590...0x05FF: code = "he"
        case 0x0600...0x06FF: code = "ar"
        case 0x0900...0x097F: code = "hi"
        case 0x0E00...0x0E7F: code = "th"
        case 0x3040...0x30FF: code = "ja"
        case 0xAC00...0xD7AF: code = "ko"
        case 0x4E00...0x9FFF: code = "zh"
        default: code = "zz"
        }
        return try? LanguageCode(code)
    }

    static func isLatin(_ s: Unicode.Scalar) -> Bool { s.value <= 0x024F || (0x1E00...0x1EFF).contains(s.value) }
```

- [x] **Krok 6 `[sonnet]`: CLI.** W `Sources/meetnotes-cli/CLI.swift` (`transcribe`): zamień komunikat i parsowanie na

```swift
        guard let langRaw = value(args, "--language") else {
            FileHandle.standardError.write(Data("--language jest obowiązkowe (pl, en… albo auto — tylko do pomiarów)\n".utf8)); exit(64)
        }
        let language: LanguageCode? = langRaw.lowercased() == "auto" ? nil : try LanguageCode(langRaw)
```
oraz `Preset(name: "cli", language: language, asr: RoleAssignment(...), languageAuto: language == nil ? true : nil)` (dopisz argument `languageAuto:` na końcu wywołania). Porównanie krotek wznowienia (`saved.snapshot.language` vs `snapshot.language`) kompiluje się bez zmian (opcjonalne są `Equatable`).

- [x] **Krok 7 `[sonnet]`: aplikacja.** W `Sources/MeetNotesApp/AppModel.swift`: `static func label(_ p: Preset) -> String { "\(p.name) · \(p.languageLabel)" }`; w `savePreset` komunikat `missingLanguage` → `"Choose a language, or Auto for meetings that mix languages."`. W `Sources/MeetNotesApp/MeetingsView.swift` (`PresetMenu`): w obu miejscach `(p.language?.rawValue.uppercased() ?? "?")` / `($0.language?.rawValue.uppercased() ?? "?")` → `p.languageLabel` / `$0.languageLabel`.

- [x] **Krok 8 `[haiku]`: zielone.** `scripts/test.sh` — oczekiwane: `120/120` (111 + 9 nowych `@Test`: `autoLanguagePresetValidatesButStillNeedsAnExplicitChoice`, `phaseOnePresetJSONStillDecodes`, `autoLanguageOmitsTheLanguageField`, `autoLanguageSkipsTheLanguageGuard`, `phaseOneInputJSONKeepsItsShapeAndResumes`, `autoLanguageFlagsGibberishInAnotherScript`, `nonLatinScriptIsDetectedByMajority`, `realPhaseOnePresetsAndProvidersStillDecode`, `realPhaseOneInputJSONDecodesRoundTripsAndResumes`).

- [x] **Krok 9 `[haiku]`: mutacja 1 (Auto wysyła język).** Przepis (przegląd §0.5). W `Sources/MeetNotesProviders/OpenAICompatibleClient.swift` w gałęzi `.audioTranscriptions` zamień `if let language { body["language"] = language.rawValue }` na `body["language"] = language?.rawValue ?? "pl"`. `scripts/test.sh --filter autoLanguageOmitsTheLanguageField` — oczekiwane: **pada**. `git checkout Sources/MeetNotesProviders/OpenAICompatibleClient.swift`; pełne `scripts/test.sh` — `120/120`.

- [x] **Krok 10 `[haiku]`: mutacje 2 i 3.** (a) W `Merger.swift`, w gałęzi `else`, zamień `LanguageGuard.nonLatinScript(text)` na `LanguageGuard.mismatch(text, expected: .polish)` (Auto dostaje strażnika PL/EN; kod się kompiluje). Przepis §0.5: `scripts/test.sh --filter autoLanguageSkipsTheLanguageGuard` — oczekiwane: **test pada** (nie błąd budowania — to byłby STOP); `git checkout Sources/MeetNotesTranscription/Merger.swift`. (b) W `LanguageGuard.nonLatinScript` zamień `guard foreign.count * 2 > letters.count else { return nil }` na `guard foreign.count > 0 else { return nil }` (każdy cudzy znak = bełkot). `scripts/test.sh --filter nonLatinScriptIsDetectedByMajority` — oczekiwane: **pada**; `git checkout Sources/MeetNotesTranscription/LanguageGuard.swift`. Pełne `scripts/test.sh` — `120/120`.

- [x] **Krok 11 `[sonnet]`: commit.**

```bash
git add Package.swift Sources Tests scripts Resources docs .gitignore
git commit -m "T1: język Auto w presecie i potoku (languageAuto opcjonalne, RunSnapshot.language?)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [x] **Krok 12 `[opus]`: przegląd T1.** Sprawdź: (a) żadne miejsce z tabeli nie zostało pominięte (`rg -n "\.language\b" Sources`), (b) stary `input.json` bez `languageAuto` wczytuje się (test), (c) nic nie normalizuje presetu przy wczytywaniu (`summary.prompt` zostaje), (d) `LanguageCode("auto")` nadal rzuca (`autoLanguageCannotBeConstructed`), (e) `nonLatinScript` działa tylko przy Auto (przy jawnym języku `Merger` wywołuje wyłącznie `mismatch`) i liczy litery, nie znaki specjalne. Uwagi → raport; blokujące → poprawka przed T2.

---

### Zadanie T2: `listModels(output:)` z ponowieniem i lokalnym filtrem

Status: ⚠️ nieskompilowane.

**Spec:** §3 decyzja 12, §4.2, §8 test 7. OpenRouter filtruje po stronie serwera (`?output_modalities=transcription|embeddings`); dostawca bez parametru (Ollama) może go zignorować (200, pełna lista) albo odrzucić (400/422). Lokalny filtr działa **zawsze**, gdy modalności są w odpowiedzi.

**Pliki:**
- Zmień: `Sources/MeetNotesProviders/OpenAICompatibleClient.swift`
- Test: `Tests/MeetNotesProvidersTests/Stub.swift`, `Tests/MeetNotesProvidersTests/ClientTests.swift`

**Interfejsy:**
- Dostarcza: `OpenAICompatibleClient.listModels(output: String? = nil) async throws -> [ModelInfo]` (wywołania `listModels()` działają bez zmian); `request(_:method:query:body:timeout:)`.

- [x] **Krok 1 `[sonnet]`: Stub widzi zapytanie.** W `Tests/MeetNotesProvidersTests/Stub.swift` w `send` zamień linię `let path = request.url!.path` na:

```swift
        let url = request.url!
        let path = url.path + (url.query.map { "?\($0)" } ?? "") // zapytanie jest częścią „ścieżki" w testach
```
(istniejące testy nie używają zapytań, więc ich oczekiwania ścieżek się nie zmieniają).

- [x] **Krok 2 `[sonnet]`: testy.** Dopisz na końcu `Tests/MeetNotesProvidersTests/ClientTests.swift`:

```swift
@Test func listModelsCanAskForAnOutputModality() async throws {
    let http = StubHTTP { _, _ in ok(["data": [
        ["id": "microsoft/mai-transcribe-2", "architecture": ["output_modalities": ["transcription"]]],
    ]]) }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "transcription")
    #expect(models.map(\.id) == ["microsoft/mai-transcribe-2"])
    #expect(http.calls[0].path == "/api/v1/models?output_modalities=transcription")
}

@Test func providerRejectingTheModalityParameterIsAskedAgainWithoutIt() async throws {
    let http = StubHTTP { path, _ in
        path.contains("output_modalities") ? fail(400, "{\"error\":\"unknown parameter\"}")
            : ok(["data": [["id": "llama3"], ["id": "nomic-embed"]]])
    }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "embeddings")
    #expect(models.map(\.id) == ["llama3", "nomic-embed"]) // brak modalności w odpowiedzi → nic nie odfiltrowane
    #expect(http.calls.map(\.path) == ["/api/v1/models?output_modalities=embeddings", "/api/v1/models"])
}

@Test func providerIgnoringTheModalityFilterIsFilteredLocally() async throws {
    // Review Focus #2: 200 z pełną listą — ponowienie się nie wyzwoli, filtr lokalny musi zadziałać.
    let http = StubHTTP { _, _ in ok(["data": [
        ["id": "microsoft/mai-transcribe-2", "architecture": ["output_modalities": ["transcription"]]],
        ["id": "openai/gpt-x", "architecture": ["output_modalities": ["text"]]],
    ]]) }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "transcription")
    #expect(models.map(\.id) == ["microsoft/mai-transcribe-2"])
}

@Test func modalityRetryHappensOnlyOnce() async throws {
    let http = StubHTTP { _, _ in fail(400, "{}") }
    await #expect(throws: ProviderError.http(400, "{}")) {
        _ = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http).listModels(output: "transcription")
    }
    #expect(http.calls.count == 2)
}
```

- [x] **Krok 3 `[haiku]`: czerwone.** `scripts/test.sh` — oczekiwane: błąd kompilacji (`listModels(output:)` nie istnieje). Inaczej STOP.

- [x] **Krok 4 `[sonnet]`: implementacja.** W `OpenAICompatibleClient.swift` zamień `func request(...)` na wersję z zapytaniem:

```swift
    func request(_ path: String, method: String = "POST", query: [URLQueryItem] = [], body: [String: Any]? = nil,
                 timeout: Double = 120) throws -> URLRequest {
        var comps = URLComponents(url: provider.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method
        r.timeoutInterval = timeout
        if let key { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }
```
i zastąp `listModels()` tym:

```swift
    /// `output` = modalność wyjścia (`"transcription"`, `"embeddings"`). OpenRouter filtruje po stronie serwera;
    /// dostawca, który parametru nie zna, odrzuci go (400/422 → ponawiamy RAZ bez niego) albo zignoruje (200 z pełną
    /// listą). Dlatego lokalny filtr działa zawsze, gdy odpowiedź niesie modalności; model bez modalności zostaje.
    public func listModels(output: String? = nil) async throws -> [ModelInfo] {
        let items = output.map { [URLQueryItem(name: "output_modalities", value: $0)] } ?? []
        let obj: [String: Any]
        do {
            obj = try await json(try request("models", method: "GET", query: items, timeout: 30))
        } catch ProviderError.http(let status, _) where output != nil && (status == 400 || status == 422) {
            obj = try await json(try request("models", method: "GET", timeout: 30))
        }
        guard let data = obj["data"] as? [[String: Any]] else { throw ProviderError.badResponse("no data[]") }
        let all: [ModelInfo] = data.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let arch = m["architecture"] as? [String: Any]
            return ModelInfo(id: id, inputModalities: arch?["input_modalities"] as? [String],
                             outputModalities: arch?["output_modalities"] as? [String])
        }
        guard let output else { return all }
        return all.filter { $0.outputModalities.map { $0.contains(output) } ?? true }
    }
```
(usuń stary `listModels()`; pozostałe wywołania `request("chat/completions", body: …)` i `request("embeddings", body:…, timeout:…)` używają argumentów po nazwie i kompilują się bez zmian).

- [x] **Krok 5 `[haiku]`: zielone.** `scripts/test.sh` — oczekiwane: `124/124` (120 + 4 nowe `@Test`: `listModelsCanAskForAnOutputModality`, `providerRejectingTheModalityParameterIsAskedAgainWithoutIt`, `providerIgnoringTheModalityFilterIsFilteredLocally`, `modalityRetryHappensOnlyOnce`).

- [x] **Krok 6 `[haiku]`: mutacje (ponowienie i filtr lokalny).** (a) W `listModels` usuń klauzulę `catch ProviderError.http(let status, _) where output != nil && (status == 400 || status == 422) { … }` razem z jej ciałem (nie ma ponowienia). `scripts/test.sh --filter providerRejectingTheModalityParameterIsAskedAgainWithoutIt` — oczekiwane: **pada**; `git checkout Sources/MeetNotesProviders/OpenAICompatibleClient.swift`. (b) W `listModels` zamień końcówkę `return all.filter { … }` na `return all`. `scripts/test.sh --filter providerIgnoringTheModalityFilterIsFilteredLocally` — oczekiwane: **pada**; `git checkout Sources/MeetNotesProviders/OpenAICompatibleClient.swift`. Pełne — `124/124`.

- [x] **Krok 7 `[sonnet]`: commit.**

```bash
git add Package.swift Sources Tests scripts Resources docs .gitignore
git commit -m "T2: listModels(output:) — filtr po modalności z ponowieniem i filtrem lokalnym" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
