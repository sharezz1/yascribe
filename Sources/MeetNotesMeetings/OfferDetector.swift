import Foundation

public struct Offer: Equatable, Sendable, Identifiable {
    public enum Source: Equatable, Sendable { case calendar, call, calendarAndCall }
    public var id: String
    public var title: String
    public var source: Source
    public var event: CalendarEventInfo?
    public var app: String?

    public init(id: String, title: String, source: Source, event: CalendarEventInfo?, app: String?) {
        self.id = id
        self.title = title
        self.source = source
        self.event = event
        self.app = app
    }
}

public enum OfferAction: Equatable, Sendable { case show(Offer), hide, startRecording(Offer) }

/// Oferta startu nagrywania (spec §4.2, §4.5). Czysta maszyna stanów: czas wstrzykiwany (`now`), zero `Date()`.
/// Klucz stanu rozmowy to RODZINA aplikacji (wpis z `callApps` dopasowany po prefiksie bundle ID), nie `pid`.
/// Aplikacje spoza `callApps` (w tym `ignoredApps`: system, dyktowanie) nigdy nie dają oferty ani jej nie blokują.
public struct OfferDetector {
    private let tuning: MeetingTuning
    /// Rodzina → początek ciągłego użycia wejścia (zerowany każdym tikiem bez wejścia rodziny); liczy `startSeconds`.
    private var micSince: [String: Date] = [:]
    /// Rodzina → ostatni tik z wejściem; sesja mikrofonu trwa, dopóki przerwa < `releaseSeconds`.
    private var lastInput: [String: Date] = [:]
    /// Rodziny wyciszone do końca swojej sesji mikrofonu (dismiss albo zatrzymanie nagrania).
    private var mutedFamilies: Set<String> = []
    /// Id wydarzenia → koniec jego okna oferty (wtedy wpis wygasa; wydarzenie znikające z listy nie zdejmuje wyciszenia).
    /// Dopóki jakiś wpis trwa, rozmowa ad hoc (bez wydarzenia) nie dostaje oferty ani auto-startu: wyciszone wydarzenie
    /// jest odfiltrowane, więc bez tego ta sama rozmowa wracałaby jako "Call in Teams".
    private var mutedEvents: [String: Date] = [:]
    private var wasRecording = false
    /// Czas poprzedniego `step`; przerwa dłuższa niż `maxTickGap` zrywa ciągłość mikrofonu.
    private var lastStep: Date?
    /// ponytail: 3 s = 3× tik monitora 1 s; nastawna, jeśli tiki zrzedną
    private static let maxTickGap: Double = 3
    private var current: Offer?
    /// `.startRecording` już poszło dla bieżącej oferty; nie powtarzamy, dopóki nie zacznie się nagranie albo oferta nie zniknie.
    private var starting = false

    public init(tuning: MeetingTuning) { self.tuning = tuning }

    /// Zwraca akcję tylko przy zmianie stanu.
    public mutating func step(now: Date, events: [CalendarEventInfo], processes: [AudioProcessSample], recording: Bool,
                              callsEnabled: Bool, autoStart: Bool) -> OfferAction? {
        if let prev = lastStep, now.timeIntervalSince(prev) > Self.maxTickGap { micSince = [:] }  // uśpienie, App Nap
        lastStep = now
        let active = Set(processes.filter(\.isRunningInput).compactMap { tuning.family(of: $0.bundleID) })
        for fam in tuning.callApps {
            if active.contains(fam) {
                lastInput[fam] = now
                micSince[fam] = micSince[fam] ?? now
            } else {
                micSince[fam] = nil
                if lastInput[fam].map({ now.timeIntervalSince($0) >= tuning.releaseSeconds }) ?? true {
                    lastInput[fam] = nil
                    mutedFamilies.remove(fam)
                }
            }
        }
        mutedEvents = mutedEvents.filter { $0.value >= now }

        if recording {
            wasRecording = true
            defer { current = nil; starting = false }
            return current == nil ? nil : .hide
        }
        let inWindow = events.filter {
            EventFilter.isOfferable($0, tuning: tuning) && now >= $0.start - tuning.offerLead && now <= $0.start + tuning.offerGrace && now < $0.end
        }
        if wasRecording {
            // Stop (ręczny albo bezpiecznik): trwające sesje rodzin (też po krótkiej przerwie) i bieżące okna wydarzeń milkną.
            wasRecording = false
            mutedFamilies.formUnion(lastInput.keys)
            for e in inWindow { mutedEvents[e.id] = windowEnd(e) }
        }

        let event = inWindow.filter { mutedEvents[$0.id] == nil }.min {
            let (a, b) = (abs($0.start.timeIntervalSince(now)), abs($1.start.timeIntervalSince(now)))
            return a != b ? a < b : $0.id < $1.id
        }
        // Rozmowa, która zaczęła się w oknie wyciszonego wydarzenia, milknie do końca swojej sesji (także po wygaśnięciu okna).
        let adHocBlocked = event == nil && !mutedEvents.isEmpty
        if adHocBlocked { mutedFamilies.formUnion(active) }
        let fam = callsEnabled && !adHocBlocked ? tuning.callApps.first {
            !mutedFamilies.contains($0) && micSince[$0].map { now.timeIntervalSince($0) >= tuning.startSeconds } == true
        } : nil
        let offer: Offer? = switch (event, fam) {
        case let (e?, f?): Offer(id: e.id, title: e.title, source: .calendarAndCall, event: e, app: f)
        case let (e?, nil): Offer(id: e.id, title: e.title, source: .calendar, event: e, app: nil)
        case let (nil, f?): Offer(id: "call:" + f, title: "Call in " + Self.appName(f), source: .call, event: nil, app: f)
        case (nil, nil): nil
        }

        var action: OfferAction?
        if offer != current {
            current = offer
            if let offer {
                if !starting { action = .show(offer) }
            } else {
                starting = false
                action = .hide
            }
        }
        // Auto-start: nigdy na samym kalendarzu.
        if autoStart, !starting, let o = current, o.source != .calendar {
            starting = true
            action = .startRecording(o)
        }
        return action
    }

    /// "Not a meeting": wycisza bieżącą ofertę (rodzinę i wydarzenie). Pigułkę chowa kolejny `step` (`.hide`).
    public mutating func dismiss() {
        guard let o = current else { return }
        if let f = o.app { mutedFamilies.insert(f) }
        if let e = o.event { mutedEvents[e.id] = windowEnd(e) }
    }

    /// Koniec okna oferty wydarzenia: `start + offerGrace`, nie później niż koniec wydarzenia.
    private func windowEnd(_ e: CalendarEventInfo) -> Date { min(e.start + tuning.offerGrace, e.end) }

    private static let appNames = ["com.microsoft.teams2": "Teams"]
    private static func appName(_ family: String) -> String {
        appNames[family] ?? String(family.split(separator: ".").last ?? Substring(family))
    }
}
