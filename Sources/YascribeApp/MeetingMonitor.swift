import Foundation
import YascribeMeetings
import YascribeProviders
import Observation

/// Koordynator wykrywania spotkań (faza 1.6, spec §4.2, §4.5, §4.6): co sekundę czyta procesy audio, co 30 s (i na
/// `EKEventStoreChanged`) wydarzenia, karmi `OfferDetector` i `EndDetector` i pokazuje wynik w pigułce.
/// NIGDY sam nie zatrzymuje nagrania: koniec to pytanie, a "Stop" robi użytkownik (`recording.stop()`).
@MainActor
@Observable
final class MeetingMonitor {
    enum MonitorState: Equatable { case off, watching, calendarDenied, calendarSelectionStale }

    private(set) var state: MonitorState = .off
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private let audio: any AudioProcessSource = AudioProcessMonitor()
    @ObservationIgnored private var tuning = MeetingTuning()
    @ObservationIgnored private var offers = OfferDetector(tuning: MeetingTuning())
    @ObservationIgnored private var end = EndDetector(tuning: MeetingTuning())
    @ObservationIgnored private var events: [CalendarEventInfo] = []
    @ObservationIgnored private var eventsFetchedAt: Date?
    @ObservationIgnored private var eventsDirty = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var lastCalendarIDs: [String]?
    @ObservationIgnored private var changesTask: Task<Void, Never>?

    private static let eventsRefresh: TimeInterval = 30

    func start() {
        guard timer == nil, let model else { return }
        let changes = model.calendarSource.changes
        changesTask = Task { [weak self] in
            for await _ in changes { self?.eventsDirty = true }
        }
        // `.common`: w trybie domyślnym tik staje, gdy menu w pasku jest otwarte. Bez natychmiastowego tiku: `start()` idzie z `App.init`,
        // a oferta nie może budować panelu, zanim aplikacja skończy startować.
        let t = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in self.tick(now: Date()) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        changesTask?.cancel()
        changesTask = nil
        state = .off
        setActivity(false)
    }

    /// App Nap przy zamkniętym oknie rozjeżdża tiki o > 3 s, a wtedy detektor zeruje ciągłość mikrofonu: trzymamy aktywność, gdy wykrywamy.
    private func setActivity(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Meeting detection")
        } else if !on, let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    private func tick(now: Date) {
        guard let model else { return }
        let m = model.settings.meetings
        let calls = m?.detectCallsOrDefault ?? true
        let calendar = m?.appleCalendarOrDefault ?? false
        guard calls || calendar else {  // zero odpytywania
            if state != .off { goOff(model) }
            return
        }
        setActivity(true)
        let newTuning = MeetingTuning(settings: m)
        if newTuning != tuning {  // zmiana progów w Settings
            tuning = newTuning
            offers.retune(tuning)  // nie przebudowujemy: wyciszenia po Stop i "Not a meeting" muszą przetrwać zapis z Settings
            end.retune(tuning)
        }
        refreshEvents(now: now, calendar: calendar)
        // Nieudany odczyt Core Audio to nie zwolnienie mikrofonu: pomijamy tik.
        guard let processes = audio.snapshot() else { return }

        let recording = model.recording.isRecording
        switch offers.step(now: now, events: events, processes: processes, recording: recording, callsEnabled: calls, autoStart: m?.autoStartOrDefault ?? false) {
        case .show(let offer):
            present(offer)
        case .hide:
            model.recording.hideOffer()  // tylko stan Offer, nie pigułka nagrania
        case .startRecording(let offer):
            accept(offer)
        case nil:
            break
        }
        switch end.step(now: now, recording: recording, processes: processes, silentSeconds: model.recording.silentSeconds) {
        case .prompt(let signal):
            model.recording.showEndPrompt(signal, onStop: { [weak self] in self?.model?.recording.stop() },
                                          onContinue: { [weak self] in self?.end.continueMeeting(now: Date()) })
        case .dismissPrompt:
            model.recording.hideEndPrompt()
        case nil:
            break
        }
    }

    private func present(_ offer: Offer) {
        guard let model else { return }
        model.recording.showOffer(offer, onStart: { [weak self] in self?.accept(offer) }, onDismiss: { [weak self] in self?.offers.dismiss() })
    }

    /// Start z oferty (przycisk albo auto-start). Gdy się nie uda (np. preset bez języka), oferta zostaje na ekranie
    /// jako zwykła, ręczna (auto-start nie powtarza się), zamiast cicho wyciszać rozmowę; powód siedzi w `lastError`.
    private func accept(_ offer: Offer) {
        guard let model else { return }
        if !model.startRecording(offer: offer) { present(offer) }
    }

    private func refreshEvents(now: Date, calendar: Bool) {
        guard let model else { return }
        guard calendar else { events = []; eventsFetchedAt = nil; state = .watching; return }
        let source = model.calendarSource
        let ids = model.settings.meetings?.calendarIDs
        if ids != lastCalendarIDs { lastCalendarIDs = ids; eventsDirty = true }  // zmiana wyboru kalendarzy działa od razu, nie po 30 s
        guard source.authorization() == .granted else { events = []; eventsFetchedAt = nil; state = .calendarDenied; return }
        if !eventsDirty, let at = eventsFetchedAt, now.timeIntervalSince(at) < Self.eventsRefresh { return }
        eventsDirty = false
        eventsFetchedAt = now
        if let ids, !ids.isEmpty, Set(ids).isDisjoint(with: source.calendars().map(\.id)) {
            events = []  // identyfikator kalendarza ginie po pełnej synchronizacji; bez tego oferty znikałyby po cichu
            state = .calendarSelectionStale
            return
        }
        state = .watching
        events = source.events(from: now - tuning.offerGrace - 60, to: now + tuning.offerLead + Self.eventsRefresh + 60, calendarIDs: ids)
    }

    /// Wykrywanie wyłączone w Settings: zdejmuje ofertę i pytanie z ekranu; wyciszenia zostają (`pause`).
    private func goOff(_ model: AppModel) {
        state = .off
        offers.pause()
        end.reset()
        events = []
        eventsFetchedAt = nil
        model.recording.hideOffer()
        model.recording.hideEndPrompt()
        setActivity(false)
    }
}
