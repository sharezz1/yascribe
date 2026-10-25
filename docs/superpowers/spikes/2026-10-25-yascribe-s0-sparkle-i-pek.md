# S0 Yascribe: Sparkle przy samych CLT i pęk po zmianie bundle ID

Data: 2026-10-25. Plan: `docs/superpowers/plans/2026-10-25-yascribe-rebrand-i-aktualizacje.md` (T0). Kod spike'u żył w kopii (`$SCRATCH/s0`) i nie trafia do repo.

## Część A — Sparkle: **GO** (zmierzone na sprzęcie)

**Pin: Sparkle `2.9.2`** (wydanie 2026-05-17, najnowsze stabilne z maja 2026 lub starsze; 2.9.3 → 2026-06-08, 2.10.x późniejsze).
`.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")`, `.product(name: "Sparkle", package: "Sparkle")` w `MeetNotesApp`. `swift package --disable-keychain resolve` działa (zip 11,6 MB).

**Ścieżki w `.build/artifacts/sparkle/Sparkle/`:** `Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`, `bin/{generate_keys,sign_update,generate_appcast,BinaryDelta}` (potwierdza decyzję „klucz EdDSA z artefaktu SwiftPM").

**Osadzanie (działa przy CLT, build debug):** `ditto` frameworka do `Contents/Frameworks`; `install_name_tool -add_rpath @executable_path/../Frameworks` na `Contents/MacOS/<exe>`; `rm -rf Sparkle.framework/Versions/B/XPCServices Sparkle.framework/XPCServices` (usuń **też** dowiązanie na korzeniu); podpis od środka certyfikatem „MeetNotes Dev", każdy osobno, bez `--deep`: `Versions/B/Autoupdate`, `Versions/B/Updater.app`, framework, aplikacja; `codesign --verify --strict --deep` przechodzi.
Rozpakowana kopia w innym katalogu, przy niedostępnym `.build`: `otool -L` → `@rpath/Sparkle.framework/Versions/B/Sparkle` (2.9.2); rpath `@executable_path/../Frameworks` obecny; symlinki frameworka (`Versions/Current → B`) zachowane; `Autoupdate` i `Updater` mają prawa wykonywania; aplikacja startuje. (Binarka debug ma dodatkowo bezwzględny rpath do `.build/.../PackageFrameworks` — nieszkodliwy; w release go nie ma.)

**Próba aktualizacji `0.1.0` → `0.1.1` (localhost, `python3 -m http.server`, klucz jednorazowy):**
- „Check for Updates…" → okno „Software Update" widzi 0.1.1 → „Install Update" (pobranie, weryfikacja, rozpakowanie) → **drugi** przycisk „Install and Relaunch" (UI Sparkle wymaga dwóch kliknięć) → podmiana → start `0.1.1` (nowy PID, `CFBundleShortVersionString` = 0.1.1, `codesign --verify --strict --deep` OK).
- **Kolejność callbacków delegata** (log z PID): `didFindValidUpdate` → `userDidMake(choice=1 install)` → `willDownload` → `didExtract` → *(klik „Install and Relaunch")* → `shouldPostponeRelaunch` → `willInstallUpdate` → `willRelaunch` → `applicationShouldTerminate`.
  **Dla T4:** `installationStarted()` na `userDidMake` z `.install`; `installationEnded()` na `didAbortWithError`, `didFinishUpdateCycleFor` (i anulowanie). Uwaga: między „Install Update" a „Install and Relaunch" mija dowolnie długi czas, a blokada nowych nagrań działa już od pierwszego kliknięcia (zgodnie z planem).
- **Odroczenie działa:** przy `busy=true` Sparkle po „Install and Relaunch" woła `shouldPostponeRelaunch`, my zwracamy `true` i trzymamy blok; do czasu jego wywołania **nie ma** `willInstallUpdate` ani terminate (aplikacja żyje). Po zdjęciu „zajętości" i wywołaniu bloku: `willInstallUpdate` → `willRelaunch` → `applicationShouldTerminate` (wołane przez Sparkle) → restart.
- **Obserwacja niewyjaśniona (do sprawdzenia w T9):** w pierwszym przebiegu, bez własnego `NSApplicationDelegate`, po `willRelaunch` aplikacja **nie zakończyła się sama** (Autoupdate czekał; skończyło się dopiero po ręcznym ⌘Q, wtedy podmiana i start 0.1.1 poszły poprawnie). Po dodaniu `@NSApplicationDelegateAdaptor` z `applicationShouldTerminate` Sparkle wołał terminate bez udziału człowieka. Nie wyizolowałem przyczyny; T4 i tak dodaje delegata, ale test na żywo T9 musi potwierdzić samoczynny restart.
- **Negatywna próba (anty-cel „wydanie bez podpisu"):** appcast z popsutym znakiem `sparkle:edSignature` → pobranie, `didAbortWithError` „The update is improperly signed and could not be validated" (SUSparkleErrorDomain 4005 → 3002 „EdDSA signature does not match"), okno „Update Error!"; aplikacja niezmieniona (0.1.0). Potwierdzone też zrzutem użytkownika.

**Wzór kontraktów współbieżności (Swift 6, bez nowych ostrzeżeń):**
```swift
@MainActor final class SpikeUpdateDelegate: NSObject, SPUUpdaterDelegate {
    private var held: (@MainActor @Sendable () -> Void)?
    func updater(_ u: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping @Sendable () -> Void) -> Bool {
        guard busy else { return false }
        held = { installHandler() }   // zwolnienie: held?() w @MainActor po końcu nagrania
        return true
    }
    func updater(_ u: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {}
}
```
Uwagi: nazwa Swift to `updater(_:userDidMake:forUpdate:state:)` (nie `userDidMakeChoice`); `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)` tworzony w `init()` aplikacji (`@MainActor`); timer pomocniczy `Timer.scheduledTimer` + `MainActor.assumeIsolated`.

**Klucz jednorazowy bez pęku:** `openssl genpkey -algorithm ed25519`, seed = ostatnie 32 bajty `openssl pkey -outform DER`, base64; publiczny = ostatnie 32 bajty DER `-pubout`, base64 (to wartość `SUPublicEDKey`). `sign_update --ed-key-file <plik z samym seedem base64>` działa; plik w formacie 64 bajtów (seed+pub) został **odrzucony** („Imported key must be 64 bytes or 96 bytes…" — mylący komunikat). Wyjście dla zipa: `sparkle:edSignature="…" length="N"` (w appcaście `length` to atrybut `enclosure`, `sparkle:edSignature` też; **dla pliku `.txt` wyjście ma `sparkle:length`** — T6 podaje zip, więc `length`). `release.sh` ma parsować `edSignature="…"` i `length="…"`.

**Kontrola tożsamości podpisu dla T6:** `security find-identity -p codesigning` (**bez** `-v`: certyfikat jest `CSSMERR_TP_NOT_TRUSTED`, `-v` pokazuje 0 ważnych tożsamości) daje SHA-1 `7C8CA11F…D29D`; `codesign -dr - <app>` zwraca `designated => identifier "io.github.sharezz1.…" and certificate leaf = H"7c8ca11f4e66100390a76d709b1f116db9bad29d"` — **to** porównujemy (identifier + odcisk, bez wielkości liter). Na tym sprzęcie `codesign -dvv` pokazuje też `Authority=MeetNotes Dev`, ale nie polegamy na nim. Podpis ad-hoc rozpoznajemy po `Signature=adhoc` w `codesign -dv`.

## Część B — pęk po zmianie bundle ID: **czeka na kroki użytkownika**

Przygotowane (w scratchpadzie sesji; ścieżki bezwzględne w skryptach): stara aplikacja `old/MeetNotes.app` (kopia `.build/MeetNotes.app`, ID `io.github.sharezz1.meetnotes`, „MeetNotes Dev"), sonda `kc-probe` w dwóch paczkach (`probe/old`, `probe/new`; ten sam certyfikat, DR odpowiednio `identifier "io.github.sharezz1.meetnotes"` i `…yascribe`, `certificate leaf = H"7c8c…"`; sonda **tylko czyta** i wypisuje status i długość, nigdy wartość), skrypty `start-old-app.sh` i `run-s0.sh`.

Wynik: *do uzupełnienia po uruchomieniu* — macierz: odczyt bez okna / okno i po „Allow" odczyt / odmowa (kod `OSStatus`).
