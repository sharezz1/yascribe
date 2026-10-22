import AppKit
import Foundation
import MeetNotesMeetings
import MeetNotesNotes
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
    /// Preset zamrożony przy starcie — pokazywany przez całe nagranie (ChatGPT #2).
    private(set) var presetLabel = ""
    /// Tytuł wydarzenia z kalendarza (start z oferty) — pokazywany obok presetu; `nil` = bez wydarzenia.
    private(set) var eventTitle: String?
    /// Ustawia `AppModel.init`; potrzebny, by `showOffer`/`showEndPrompt` mogły utworzyć okno bez nagrywania.
    @ObservationIgnored weak var model: AppModel?
    /// Ostatni poziom (dBFS) każdej ścieżki i nazwa mikrofonu — dla rozwiniętej pigułki.
    private(set) var levels: [String: Double] = [:]
    private(set) var micName = ""
    /// Wyjście, z którego tap czyta dźwięk systemowy, i flaga „tor `system` milczy ≥ 30 s” (informacja, nie błąd:
    /// w poczekalni na wbudowanych urządzeniach nic nie gra i tor nie dostaje klatek).
    private(set) var outputName = ""
    private(set) var systemStalled = false
    /// UID wejścia i wyjścia oraz Bluetooth wejścia — dla podpowiedzi przy martwym torze (faza 2.0.2); odświeżane z nazwami.
    private(set) var micUID = ""
    private(set) var outputUID = ""
    private(set) var micIsBluetooth = false
    var stallHint: String? {
        PillHint.systemStalled(stalled: systemStalled, micUID: micUID, outputUID: outputUID, isBluetooth: micIsBluetooth)
    }
    /// Tory wyciszone w pigułce (macos.md §11.5); każde nagranie startuje bez wyciszenia.
    private(set) var muted: Set<String> = []
    /// „Nothing is being recorded” po próbie wyciszenia ostatniego nagrywającego toru; znika po 4 s (decyzja 1).
    private(set) var muteWarning = false
    @ObservationIgnored private var warningTask: Task<Void, Never>?
    /// Katalog trwającej sesji — lista sesji go pomija (Hermes 4.5: nie „Recovered").
    private(set) var directory: URL?
    private var recorder: SessionRecorder?
    private var timer: Timer?
    private var started = Date()
    private var panel: NSPanel?
    private var levelTimer: Timer?
    /// Stan rozwinięcia pigułki; żyje tu, bo okno jest tworzone raz i chowane po każdym nagraniu.
    private let pill = PillState()

    /// Drugi start przy żywym rejestratorze wyciekłby pierwszy (check S15 #1).
    enum StartError: Error { case alreadyRecording }

    func start(directory: URL, presetLabel: String, eventTitle: String? = nil, onEnded: @escaping @MainActor (EndReason) -> Void) throws {
        guard recorder == nil else { throw StartError.alreadyRecording }
        let r = SessionRecorder(directory: directory,
                                sources: [SystemTapSource(), RawMicrophoneSource()]) // bez VP: ściszałby Teams przez całe nagranie (S5, spec rdzenia §2 korekta 2026-09-29)
        r.onEnded = { [weak r] reason in
            Task { @MainActor in
                // Tylko bieżący rejestrator kończy stan — spóźnione zakończenie innego go nie zeruje.
                guard let r, self.recorder === r else { return }
                self.finish(reason)
                onEnded(reason)
            }
        }
        try r.start()
        recorder = r
        self.directory = directory
        self.presetLabel = presetLabel
        self.eventTitle = eventTitle
        pill.mode = .recording // start zdejmuje ofertę/pytanie; to samo okno staje się pigułką nagrania
        isRecording = r.endReason == nil
        muted = []
        muteWarning = false
        micName = CoreAudioDevices.defaultInputName() ?? "Unknown microphone"
        outputName = CoreAudioDevices.defaultOutputName() ?? "Unknown output"
        refreshDeviceIdentity()
        systemStalled = false
        started = Date()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.elapsed = Date().timeIntervalSince(self.started)
                // Źródło mikrofonu podąża za domyślnym wejściem systemu (np. AirPods podłączone w trakcie) — nazwa też.
                self.micName = CoreAudioDevices.defaultInputName() ?? self.micName
                self.outputName = CoreAudioDevices.defaultOutputName() ?? self.outputName
                self.refreshDeviceIdentity()
                self.recorder?.tick()
                self.systemStalled = self.recorder?.currentStalledTracks().contains("system") ?? false
            }
        }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in self.levels = self.recorder?.currentLevels() ?? [:] }
        }
    }

    private func refreshDeviceIdentity() {
        micUID = CoreAudioDevices.defaultInputUID() ?? ""
        outputUID = CoreAudioDevices.defaultOutputUID() ?? ""
        micIsBluetooth = CoreAudioDevices.defaultInputIsBluetooth()
    }

    func stop() { recorder?.stop(reason: .button) }

    /// Przełącza wyciszenie toru. Odmowę (oba tory naraz) zgłasza rdzeń — pigułka tylko ją pokazuje.
    func toggleMute(_ trackID: String) {
        guard let recorder else { return }
        if recorder.setMuted(trackID, !muted.contains(trackID)) {
            muted = recorder.mutedTracks()
        } else {
            muteWarning = true
            warningTask?.cancel()
            warningTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { self?.muteWarning = false }
            }
        }
    }

    /// Cisza trwającego nagrania (próg i `lastLoudAt` rekordera, jak `SilenceCondition`); 0 bez nagrania. Czyta ją `MeetingMonitor`.
    var silentSeconds: Double { recorder?.silentSeconds() ?? 0 }

    /// Migawki (`Snapshots.swift`): kontroler w stanie „trwa nagranie” bez rejestratora i czasomierzy.
    static func snapshotPreview(elapsed: TimeInterval, muted: Set<String> = [], muteWarning: Bool = false,
                                systemStalled: Bool = false, headsetStall: Bool = false) -> RecordingController {
        let r = RecordingController()
        r.isRecording = true
        r.elapsed = elapsed
        r.presetLabel = "Polish · PL"
        r.micName = "MacBook Air Microphone"
        r.outputName = "MacBook Air Speakers"
        r.systemStalled = systemStalled || headsetStall
        if headsetStall {
            r.micName = "Sound Blaster JAM V2"; r.outputName = "Sound Blaster JAM V2"
            r.micUID = "00-02-3C-8D-E0-50:input"; r.outputUID = "00-02-3C-8D-E0-50:output"; r.micIsBluetooth = true
        }
        r.levels = ["system": systemStalled || headsetStall ? -160 : -22, "mic_raw": -41]
        r.muted = muted
        r.muteWarning = muteWarning
        return r
    }

    private func finish(_ reason: EndReason) {
        isRecording = false
        lastEndReason = reason
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        levels = [:]
        muted = []
        muteWarning = false
        warningTask?.cancel()
        recorder = nil
        directory = nil
        hidePanel()
    }

    /// Pigułka w trybie nagrania jest widoczna tylko podczas nagrywania (odbiór 2026-10-16): pokazuje ją start nagrania
    /// (`AppModel.startRecording`), chowa `finish`; pozycja menu ma `.disabled(!isRecording)`. Okno nie sprawdza już `isRecording`
    /// (T8, żeby żyło też bez nagrania). Ponowne wywołanie (Cmd-Opt-R) wynosi je na wierzch i wciąga z powrotem na ekran.
    func showPanel(model: AppModel) {
        if panel == nil { panel = makePanel(model: model, pill: pill) }
        guard let panel, let host = panel.contentView as? PillHostingView<PillContentView> else { return }
        host.fit(placing: !panel.isVisible)
        panel.orderFrontRegardless()
        // Zmiana `mode` dociera do widoku SwiftUI po kolejce, więc rozmiar liczony tu może dotyczyć starej treści.
        DispatchQueue.main.async { host.fit(force: true) }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        pill.expanded = false
        pill.mode = .recording
    }

    // MARK: Oferta i pytanie o koniec (faza 1.6, T9)

    func showOffer(_ offer: Offer, onStart: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        guard !isRecording else { return } // nigdy nie zasłaniamy pigułki nagrania
        pill.onPrimary = onStart
        pill.onSecondary = { [weak self] in onDismiss(); self?.hideOffer() }
        present(.offer(offer), title: "Meeting detected")
    }

    /// Zdejmuje wyłącznie ofertę; pigułka nagrania zostaje.
    func hideOffer() {
        guard case .offer = pill.mode else { return }
        if isRecording { pill.mode = .recording } else { hidePanel() }
    }

    func showEndPrompt(_ signal: EndSignal, onStop: @escaping () -> Void, onContinue: @escaping () -> Void) {
        pill.onPrimary = onStop
        pill.onSecondary = { [weak self] in onContinue(); self?.hideEndPrompt() }
        present(.endPrompt(signal), title: "Meeting ended?")
    }

    /// Wraca do pigułki nagrania (pytanie wisi podczas nagrywania); bez nagrania chowa okno.
    func hideEndPrompt() {
        guard case .endPrompt = pill.mode else { return }
        if isRecording { pill.mode = .recording } else { hidePanel() }
    }

    private func present(_ mode: PillMode, title: String) {
        guard let model else { return }
        pill.mode = mode
        showPanel(model: model)
        panel?.title = title // czyta go VoiceOver
    }
}

/// Stan rozwinięcia pigułki; rozmiar okna zmienia się tylko razem z nim (`PillHostingView`).
final class PillState: ObservableObject {
    @Published var expanded = false
    @Published var mode: PillMode = .recording
    /// Zmiana tożsamości treści: po zamknięciu menu (Preset w ofercie) SwiftUI zostaje z gestem przeciągania w złym stanie, a nowe drzewo go zeruje.
    @Published var rev = 0
    /// Akcje przycisków oferty (Start / Not a meeting) i pytania (Stop / Continue); ustawia `RecordingController`.
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
}

/// Okno ma dokładnie rozmiar treści (bez przezroczystego marginesu łapiącego kliknięcia), a treść ma stały
/// rozmiar w każdym stanie (licznik o stałej szerokości, nazwa mikrofonu z zarezerwowanymi dwoma wierszami).
/// Dlatego okno zmienia rozmiar WYŁĄCZNIE przy zmianie `pill.expanded` — nie przy każdym tiku licznika.
/// Kotwica: środek dolnej krawędzi (decyzja 2026-10-16, R5) — zwinięta ↔ rozwinięta nie przesuwa pigułki w bok,
/// rośnie na boki i w górę; ramkę liczy `PillPlacement` (wsunięcie w `visibleFrame`).
private final class PillHostingView<Content: View>: NSHostingView<Content> {
    /// Zapamiętana pozycja: środek dolnej krawędzi („x, y” jako punkt).
    static var anchorKey: String { "recordingPillBottomCenter" }
    /// Do wersji sprzed R5: lewy dolny róg okna w stanie, w którym je przeciągnięto (szerokość nieznana).
    private static var legacyOriginKey: String { "recordingPillOrigin" }
    private let pill: PillState
    private struct LayoutKey: Equatable { var expanded: Bool; var mode: PillMode }
    private var fittedKey: LayoutKey?
    private var key: LayoutKey { LayoutKey(expanded: pill.expanded, mode: pill.mode) }
    private var fitScheduled = false
    private var fitting = false
    private var moveObserver: NSObjectProtocol?
    private var menuObserver: NSObjectProtocol?

    init(rootView: Content, pill: PillState) {
        self.pill = pill
        super.init(rootView: rootView)
        // Bez automatycznego rozmiaru okna z min/max treści (kotwiczy górną krawędź); rozmiar ustawia tylko `fit`.
        sizingOptions = [.intrinsicContentSize]
        // Menu w ofercie (wybór presetu) zostawiało pigułkę nieprzesuwalną: po śledzeniu menu stan gestu `WindowDragGesture` się zacinał.
        menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case .offer = self.pill.mode else { return }
                DispatchQueue.main.async { self.pill.rev += 1 }
            }
        }
    }
    @available(*, unavailable) required init(rootView: Content) { fatalError() }
    @available(*, unavailable) @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        // Pozycję zapamiętuje tylko przeciągnięcie przez użytkownika, nie nasza zmiana rozmiaru.
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.fitting, let w = self.window else { return }
                UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: w.frame.midX, y: w.frame.minY)), forKey: Self.anchorKey)
            }
        }
    }

    /// Gesty SwiftUI (przeciąganie za tło, `WindowDragGesture`) działają tylko w oknie klucza, a nieaktywująca
    /// aplikacji pigułka nim nie jest, dopóki się jej nie kliknie — więc pierwszy klik robi z niej okno klucza.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if let w = window, !w.isKeyWindow { w.makeKey() }
        super.mouseDown(with: event)
    }

    override func layout() {
        super.layout()
        // Zmiana stanu dociera do układu po przebudowie widoku SwiftUI; dopasowanie po kolejce, gdy treść już nowa.
        guard fittedKey != key, !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.fitScheduled = false
            self?.fit()
        }
    }

    /// `placing`: okno dopiero pojawia się — ustaw je w zapamiętanym albo domyślnym miejscu.
    func fit(placing: Bool = false, force: Bool = false) {
        guard let w = window else { return }
        layoutSubtreeIfNeeded()
        let size = fittingSize
        guard size.width > 0, size.height > 0 else { return }
        guard placing || force || fittedKey != key else { return }
        fittedKey = key
        let size2 = w.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let anchor = placing ? Self.savedAnchor(width: size2.width) ?? Self.defaultAnchor() : NSPoint(x: w.frame.midX, y: w.frame.minY)
        let f = PillPlacement.frame(size: size2, bottomCenter: anchor, screens: NSScreen.screens.map(\.visibleFrame))
        fitting = true
        w.setFrame(f, display: true)
        fitting = false
        // Cień z kształtu treści (promień 20 / kapsuła) liczy się dopiero po układzie nowej treści.
        DispatchQueue.main.async { w.invalidateShadow() }
    }

    private static func savedAnchor(width: CGFloat) -> NSPoint? {
        let d = UserDefaults.standard
        if let a = d.string(forKey: anchorKey) { return NSPointFromString(a) }
        // Migracja: stary lewy dolny róg → środek dołu przy bieżącej (zwiniętej) szerokości; błąd co najwyżej o różnicę szerokości.
        guard let o = d.string(forKey: legacyOriginKey).map(NSPointFromString) else { return nil }
        return NSPoint(x: o.x + width / 2, y: o.y)
    }

    /// Domyślnie: dół ekranu, środek, z marginesem nad dokiem (`visibleFrame` już go omija).
    private static func defaultAnchor() -> NSPoint {
        let v = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: v.midX, y: v.minY + 24)
    }
}

/// Panel bez ramki i tytułu, żeby szkło (§6.2) było jedynym tłem. Bez `canBecomeKey` panel `.borderless`
/// nie dostaje klawiatury (Cmd-. dla Stop, Tab); `.nonactivatingPanel` nadal nie aktywuje aplikacji.
private final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Decyzja 2026-10-16 (c): stanie się oknem klucza (klik w tło, Cmd-Opt-R, Open note) niczego nie fokusuje.
    /// Bez tego pierwszym responderem zostaje `KeyViewProxy` SwiftUI z fokusem na Stop, a Space go wciska
    /// (zmierzone sondą) — Stop kończy nagranie. `makeFirstResponder(nil)` oddaje fokus oknu: nic nie ma pierścienia,
    /// Tab nadal wchodzi do przycisków (Full Keyboard Access), Cmd-. zostaje jawnym skrótem Stop.
    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(nil)
    }
}

extension RecordingController {
    /// 🔀 Odstępstwa 1 i 2 (`docs/design/macos.md` §10): okno zostaje na wierzchu, gdy aktywny
    /// jest Teams, i klik w nie nie odbiera fokusu spotkaniu.
    fileprivate func makePanel(model: AppModel, pill: PillState) -> NSPanel {
        let host = PillHostingView(rootView: PillContentView(model: model, pill: pill), pill: pill)
        let p = PillPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Recording" // nie widać, ale czyta go VoiceOver i menu Window
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        // W pełni przezroczyste okno: kształt (promień 20 / kapsuła) daje tylko szkło, system liczy z niego cień.
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // Przeciąganie za tło; przyciski SwiftUI przechwytują własne kliknięcia.
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        return p
    }
}

/// Szkło tylko tutaj (§6.2): Liquid Glass regular od macOS 26, niżej zwykły materiał z cienką obwódką.
/// `clipShape` po szkle: Liquid Glass rysuje własną poświatę (alfa 2–5 %) na CAŁYM prostokącie warstwy, także w rogach
/// poza kształtem. Okno ma rozmiar treści, więc jego maska alfa była prostokątem i system liczył z niej prostokątny cień;
/// cień okna klucza (macOS 26+) ma wyraźną krawędź, stąd prostokątne rogi tylko na pierwszym planie (drugi odbiór,
/// zmierzone sondą: rogi alfa 0 dopiero po przycięciu). Bez przycięcia `invalidateShadow` nic nie zmienia.
/// Całe szkło przeciąga okno (`WindowDragGesture`); przyciski w środku mają pierwszeństwo przed gestem rodzica.
extension View {
    @ViewBuilder func pillGlass<S: InsettableShape>(_ shape: S) -> some View {
        Group {
            if #available(macOS 26, *) {
                glassEffect(.regular, in: shape).clipShape(shape)
            } else {
                background(.regularMaterial, in: shape).overlay(shape.strokeBorder(.mnLine, lineWidth: 0.5))
            }
        }
        .contentShape(shape)
        .gesture(WindowDragGesture())
    }
}

/// Stop: kapsuła `card` z obwódką, czerwony kwadrat 10 pt (promień 2) i słowo — stan nie tylko kolorem.
struct StopButtonStyle: ButtonStyle {
    var fill = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.mnRec).frame(width: 10, height: 10)
            configuration.label.fontWeight(.semibold).lineLimit(1).fixedSize()
        }
        .font(.system(size: 13))
        .foregroundStyle(.mnRec)
        .padding(.leading, 10).padding(.trailing, 12)
        .frame(maxWidth: fill ? .infinity : nil)
        .frame(height: 32)
        .background(.mnCard, in: Capsule())
        .overlay(Capsule().strokeBorder(.mnLine, lineWidth: 0.5))
        .opacity(configuration.isPressed ? 0.7 : 1)
        .contentShape(Capsule())
    }
}

/// Przycisk-ikona bez tła (⌃ / ⌄): podpis w `.help` i dla VoiceOver.
private struct PillIconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 32
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)).foregroundStyle(.mnText2)
                .frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct RecordingPanelView: View {
    let model: AppModel
    /// Domyślnie kontroler aplikacji; migawki podają własny, z wymuszonym stanem nagrywania.
    var recording: RecordingController?
    @ObservedObject var pill: PillState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Działa także w panelu poza sceną (sonda 2026-10-16: otwiera okno WindowGroup po jego zamknięciu).
    @Environment(\.openWindow) private var openWindow

    init(model: AppModel, recording: RecordingController? = nil, pill: PillState) {
        self.model = model; self.recording = recording; self.pill = pill
    }

    var body: some View {
        let rec = recording ?? model.recording
        Group {
            if pill.expanded {
                expandedBody(rec).padding(14).frame(width: 360).pillGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                collapsedBody(rec).padding(6).padding(.leading, 8).frame(height: 44).pillGlass(Capsule())
            }
        }
        .environment(model)
    }

    private func collapsedBody(_ rec: RecordingController) -> some View {
        HStack(spacing: 8) {
            // Stały wskaźnik, bez pulsowania (§7); stan mówi też licznik i słowo Stop.
            Circle().fill(.mnRecDot).frame(width: 8, height: 8).accessibilityHidden(true)
            LevelBars(fraction: Self.fraction(rec), animated: !reduceMotion)
            // Stała szerokość na najdłuższy format (00:00:00), żeby okno nie skakało przy przejściu 59:59 → 1:00:00.
            Text("00:00:00").lineLimit(1).fixedSize().hidden().accessibilityHidden(true)
                .overlay(alignment: .leading) { Text(Self.shortClock(rec.elapsed)).accessibilityLabel("Recording \(Self.shortClock(rec.elapsed))") }
                .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(.mnText)
            // Miejsce zarezerwowane zawsze (decyzja 2): szerokość zwiniętej pigułki nie zależy od wyciszenia.
            let micMuted = rec.muted.contains("mic_raw")
            Image(systemName: "mic.slash").font(.system(size: 12, weight: .semibold)).foregroundStyle(.mnText2)
                .frame(width: 14).opacity(micMuted ? 1 : 0)
                .help("Microphone muted").accessibilityLabel("Microphone muted").accessibilityHidden(!micMuted)
            Button("Stop") { rec.stop() }.buttonStyle(StopButtonStyle()).keyboardShortcut(".", modifiers: .command)
            PillIconButton(systemImage: "chevron.up", label: "Show details") { pill.expanded = true }
        }
        // Szerokość z treści przy najszerszym liczniku. Zmierzone: ideał 253, ale przy propozycji 253 układ ściskał się do 245
        // i „Stop” łamał się na „Sto / p” (przypuszczalnie zaokrąglenie ideału do punktu);
        // `fixedSize` tu i na etykietach trzyma je w jednej linii niezależnie od zaokrąglenia.
        .fixedSize()
    }

    /// Rozwinięta: Stop i wyciszanie torów (1.5b, zmienia spec decyzję 4 „tylko do odczytu”).
    private func expandedBody(_ rec: RecordingController) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // D2: w pigułce czerwona tylko kropka, słowo ciemne (na liście spotkań `StateLabel(.live)` zostaje czerwony).
                HStack(spacing: 4) {
                    Circle().fill(.mnRecDot).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text("Recording").font(.callout).fontWeight(.semibold).foregroundStyle(.mnText).lineLimit(1).fixedSize()
                }
                .accessibilityElement(children: .combine)
                Text(Self.shortClock(rec.elapsed)).font(.callout).monospacedDigit().foregroundStyle(.mnText2).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                PillIconButton(systemImage: "chevron.down", label: "Hide details", size: 24) { pill.expanded = false }
            }
            // Ostrzeżenie w miejscu linii presetu, ta sama wysokość — okno nie zmienia rozmiaru (decyzja 1).
            Text(rec.eventTitle.map { "\($0) · \(rec.presetLabel)" } ?? rec.presetLabel).lineLimit(rec.eventTitle == nil ? nil : 1)
                .font(.callout).foregroundStyle(.mnText2).opacity(rec.muteWarning || rec.stallHint != nil ? 0 : 1)
                .overlay(alignment: .leading) {
                    // Na tym samym miejscu i o tej samej wysokości co ostrzeżenie: okno pigułki zmienia rozmiar tylko przy rozwinięciu.
                    if rec.muteWarning { WarnLabel("Nothing is being recorded").lineLimit(1).fixedSize() }
                    else if let hint = rec.stallHint { Text(hint).font(.callout).foregroundStyle(.mnText2).lineLimit(1).fixedSize() }
                }
                .padding(.leading, 16).padding(.top, 2).padding(.bottom, 14)
            LevelRow(title: "System audio: \(rec.systemStalled ? "No system audio yet · " : "")\(rec.outputName)", db: rec.levels["system"], animated: !reduceMotion,
                     muted: rec.muted.contains("system")) { rec.toggleMute("system") }
            // Nazwa mikrofonu wyraźnie — żeby od razu było widać, gdy nagrywa nie ten (decyzja użytkownika).
            LevelRow(title: "Microphone: \(rec.micName)", db: rec.levels["mic_raw"], emphasized: true, animated: !reduceMotion,
                     muted: rec.muted.contains("mic_raw")) { rec.toggleMute("mic_raw") }
                .padding(.top, 10)
            HStack(spacing: 8) {
                Button { openNote(rec) } label: { Text("Open note").lineLimit(1).fixedSize() }
                .buttonStyle(PillButtonStyle(kind: .secondary, large: true)).frame(maxWidth: .infinity)
                Button("Stop") { rec.stop() }.buttonStyle(StopButtonStyle(fill: true)).keyboardShortcut(".", modifiers: .command)
            }
            .padding(.top, 14)
        }
    }

    /// Drugi odbiór: wcześniej tylko `openSession` (już ustawione przy starcie nagrania) i przestarzałe
    /// `activate(ignoringOtherApps:)` — przy zamkniętym albo zminimalizowanym oknie nic się nie działo.
    /// Zamknięte okno WindowGroup znika z `NSApp.windows` (sonda), więc wtedy otwieramy nowe; ono pokazuje już ustawioną sesję.
    private func openNote(_ rec: RecordingController) {
        model.go(to: .forRecording(directory: rec.directory))
        MainWindow.show(openWindow)
    }

    /// Głośniejsza z nagrywanych ścieżek (wyciszona się nie liczy), 0…1 (−60…0 dBFS).
    static func fraction(_ rec: RecordingController) -> Double {
        LevelRow.fraction(db: ["system", "mic_raw"].filter { !rec.muted.contains($0) }.compactMap { rec.levels[$0] }.max())
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// Licznik pigułki jak na makiecie: mm:ss, godziny dopiero po pełnej godzinie.
    static func shortClock(_ t: TimeInterval) -> String {
        t >= 3600 ? clock(t) : String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// Siedem słupków 3 pt (makieta `.lvl`): wzór wysokości stały, amplituda z poziomu. Bez animacji przy Reduce Motion.
private struct LevelBars: View {
    let fraction: Double
    let animated: Bool
    private static let profile: [CGFloat] = [6, 11, 15, 9, 13, 5, 8]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.profile.indices, id: \.self) { i in
                Capsule().fill(.mnText).frame(width: 3, height: max(3, Self.profile[i] * (0.3 + 0.7 * fraction)))
            }
        }
        .frame(height: 16)
        .animation(animated ? .easeOut(duration: 0.2) : nil, value: fraction)
        .accessibilityHidden(true)
    }
}

/// Poziom ścieżki (makieta `.meter`): ikona, nazwa, pasek 6 pt (`line` + wypełnienie `accent`) i ✓/— (stan nie tylko kolorem).
/// Z `onToggleMute` po prawej przycisk „Mute” / „Unmute” (1.5b, odbiór 2026-10-19: ikona-przełącznik była nieczytelna);
/// wyciszony tor ma ikonę `…slash`, szary pasek (rzeczywisty poziom — widać, że mówisz przy wyciszeniu, decyzja 3)
/// i słowo „Muted” zamiast ✓, a „Unmute” jest wypełnione kolorem ostrzeżenia.
/// Tytuł „Microphone: nazwa” dzieli się na etykietę w wierszu i nazwę pogrubioną pod spodem (nazwa nie może być ucięta).
struct LevelRow: View {
    let title: String
    let db: Double?
    var emphasized = false
    var animated = true
    var muted = false
    var onToggleMute: (() -> Void)?

    static func fraction(db: Double?) -> Double { max(0, min(1, ((db ?? -60) + 60) / 60)) }

    private var parts: (label: String, detail: String?) {
        guard let r = title.range(of: ": ") else { return (title, nil) }
        return (String(title[..<r.lowerBound]), String(title[r.upperBound...]))
    }
    private var hasSignal: Bool { (db ?? -160) > -60 }

    private var isMic: Bool { parts.label.hasPrefix("Microphone") }

    @ViewBuilder private var icon: some View {
        let name = isMic ? (muted ? "mic.slash" : "mic") : (muted ? "speaker.slash" : "speaker.wave.2")
        Image(systemName: name).font(.system(size: 12)).foregroundStyle(.mnText2).frame(width: 14).accessibilityHidden(true)
    }

    @ViewBuilder private var muteButton: some View {
        if let onToggleMute {
            let what = isMic ? "microphone" : "system audio"
            Button(muted ? "Unmute" : "Mute", action: onToggleMute)
                .buttonStyle(MuteButtonStyle(muted: muted))
                .help(muted ? "Record \(what) again" : "Record silence instead of \(what)")
                .accessibilityLabel("\(muted ? "Unmute" : "Mute") \(what)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                icon
                Text(parts.label).font(.callout).foregroundStyle(.mnText).frame(width: 92, alignment: .leading)
                ZStack(alignment: .leading) {
                    Capsule().fill(.mnLine)
                    GeometryReader { g in Capsule().fill(muted ? Color.mnText3 : Color.mnAccent).frame(width: g.size.width * Self.fraction(db: db)) }
                }
                .frame(height: 6)
                .animation(animated ? .easeOut(duration: 0.2) : nil, value: db)
                Group {
                    if muted { Text("Muted").font(.callout).foregroundStyle(.mnText2) }
                    else if hasSignal { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.mnAccent) }
                    else { Text("—").foregroundStyle(.mnText2) }
                }
                .frame(width: onToggleMute == nil ? 14 : 44, alignment: .trailing)
                .accessibilityLabel(muted ? "Muted" : hasSignal ? "Signal present" : "No signal")
                muteButton
            }
            if let detail = parts.detail {
                Text(detail).font(.callout.weight(.semibold)).foregroundStyle(.mnText).lineLimit(2, reservesSpace: true).padding(.leading, 22) // dwa wiersze zawsze: rozmiar rozwiniętej pigułki nie zależy od nazwy mikrofonu
            }
        }
    }
}

/// „Mute” / „Unmute” w wierszu toru: mała kapsuła o stałej szerokości (przełączanie nie przesuwa paska).
/// Wyciszony tor: wypełnienie `warn` — stan widać z daleka, a słowo „Muted” obok mówi go nie tylko kolorem.
private struct MuteButtonStyle: ButtonStyle {
    let muted: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: muted ? .semibold : .medium)).lineLimit(1)
            .foregroundStyle(muted ? Color.mnOnPrimary : Color.mnText)
            .frame(width: 64, height: 24)
            .background(muted ? Color.mnWarn : Color.mnCard, in: Capsule())
            .overlay(Capsule().strokeBorder(.mnLine, lineWidth: 0.5).opacity(muted ? 0 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
