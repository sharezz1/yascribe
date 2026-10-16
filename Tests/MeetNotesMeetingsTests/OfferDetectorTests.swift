import Foundation
import Testing
@testable import MeetNotesMeetings

private let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 10))!
private let teamsFamily = "com.microsoft.teams2"

fileprivate extension MeetingTuning {
    static var test: MeetingTuning {
        var t = MeetingTuning()
        t.offerLead = 60
        t.offerGrace = 600
        t.startSeconds = 12
        t.releaseSeconds = 20
        return t
    }
}

fileprivate extension AudioProcessSample {
    /// Pomiar T0: mikrofon trzyma proces pomocniczy, nie `com.microsoft.teams2`.
    static let teams = AudioProcessSample(pid: 100, bundleID: "com.microsoft.teams2.modulehost", isRunningInput: true)
    static let teamsHelper = AudioProcessSample(pid: 200, bundleID: "com.microsoft.teams2.helper", isRunningInput: true)
    static let speech = AudioProcessSample(pid: 300, bundleID: "com.apple.CoreSpeech", isRunningInput: true)
    static let wispr = AudioProcessSample(pid: 400, bundleID: "com.electron.wispr-flow.helper", isRunningInput: true)
    static let zoom = AudioProcessSample(pid: 500, bundleID: "us.zoom.xos", isRunningInput: true)
    static let lookalike = AudioProcessSample(pid: 600, bundleID: "com.microsoft.teams2extra", isRunningInput: true)
}

/// Wydarzenie z linkiem Teams w `notes`, zaakceptowane; `name` jest też identyfikatorem.
private func meeting(_ name: String, at start: Date, minutes: Double = 30) -> CalendarEventInfo {
    CalendarEventInfo(title: name, start: start, end: start + minutes * 60, myStatus: .accepted,
                      notes: "Join: <https://teams.microsoft.com/meet/123456?p=abc>", eventIdentifier: name)
}

private func isOffering(_ a: OfferAction) -> Bool {
    if case .hide = a { return false }
    return true
}

private struct Rig {
    var d = OfferDetector(tuning: .test)
    var events: [CalendarEventInfo] = []
    var procs: [AudioProcessSample] = []
    var recording = false
    var callsEnabled = true
    var autoStart = false

    mutating func step(_ now: Date) -> OfferAction? {
        d.step(now: now, events: events, processes: procs, recording: recording, callsEnabled: callsEnabled, autoStart: autoStart)
    }

    /// Tiki co `every` s od `from` do `to` włącznie; zwraca tylko niepuste akcje.
    mutating func run(_ from: Date, _ to: Date, every: Double = 1) -> [OfferAction] {
        var out: [OfferAction] = []
        var t = from
        while t <= to {
            if let a = step(t) { out.append(a) }
            t += every
        }
        return out
    }
}

@Test func calendarEventWithLinkOffersInsideTheWindowOnly() {
    var r = Rig()
    r.events = [meeting("Standup", at: t0)]
    #expect(r.step(t0 - 61) == nil)
    guard case .show(let o)? = r.step(t0 - 59) else { Issue.record("no offer"); return }
    #expect(o.source == .calendar && o.title == "Standup" && o.app == nil)
    #expect(o.event == r.events[0] && o.id == r.events[0].id)
    #expect(r.step(t0 - 58) == nil)    // bez powtórzeń co tik
    #expect(r.step(t0 + 600) == nil)   // koniec okna włącznie
    #expect(r.step(t0 + 601) == .hide)
    #expect(r.step(t0 + 602) == nil)
}

@Test func teamsHoldingTheMicForStartSecondsOffersACall() {
    var r = Rig()
    r.procs = [.teams]
    #expect(r.run(t0, t0 + 11).isEmpty)   // tiki co 1 s: przerwa > 3 s zeruje ciągłość
    guard case .show(let o)? = r.step(t0 + 12) else { Issue.record("no offer"); return }
    #expect(o.source == .call && o.title == "Call in Teams")
    #expect(o.app == teamsFamily && o.id == "call:" + teamsFamily && o.event == nil)
    #expect(r.step(t0 + 13) == nil)
}

@Test func lobbyBlipShorterThanStartSecondsNeverOffers() {
    var r = Rig()
    r.procs = [.teams]
    #expect(r.run(t0, t0 + 5).isEmpty)
    r.procs = []
    #expect(r.run(t0 + 6, t0 + 10).isEmpty)
    r.procs = [.teams]
    #expect(r.run(t0 + 11, t0 + 16).isEmpty)
    // przerwa zeruje licznik: 8 s + 1 tik przerwy + 10 s to nie 12 s ciągłego użycia
    var q = Rig()
    q.procs = [.teams]
    #expect(q.run(t0, t0 + 8).isEmpty)
    q.procs = []
    #expect(q.step(t0 + 9) == nil)
    q.procs = [.teams]
    #expect(q.run(t0 + 10, t0 + 20).isEmpty)
    guard case .show? = q.step(t0 + 22) else { Issue.record("no offer after 12 s since the gap"); return }
}

@Test func ignoredAppsNeverOffer() {
    var r = Rig()
    r.autoStart = true
    r.procs = [.speech, .wispr]
    #expect(r.run(t0, t0 + 3600, every: 5).isEmpty)
}

@Test func ignoredAppsHoldingTheMicDoNotBlockOrTriggerAnything() {
    var r = Rig()
    r.procs = [.speech]   // system trzyma wejście stale
    #expect(r.run(t0, t0 + 3600, every: 10).isEmpty)
    r.procs = [.speech, .wispr, .teams]
    #expect(r.run(t0 + 3601, t0 + 3612).isEmpty)
    guard case .show(let o)? = r.step(t0 + 3613) else { Issue.record("Teams blocked by an ignored app"); return }
    #expect(o.source == .call && o.app == teamsFamily)
    // po zwolnieniu przez Teams stale wejście systemu niczego nie przywraca ani nie blokuje końca sesji
    r.procs = [.speech]
    #expect(!r.run(t0 + 3614, t0 + 3700).contains(where: isOffering))
    r.procs = [.speech, .teams]
    #expect(r.run(t0 + 3701, t0 + 3712).isEmpty)
    guard case .show? = r.step(t0 + 3713) else { Issue.record("no new offer"); return }
}

@Test func unknownAppsNeverOffer() {
    var r = Rig()
    r.autoStart = true
    r.procs = [.zoom, .lookalike]   // `com.microsoft.teams2extra` nie jest rodziną `com.microsoft.teams2`
    #expect(r.run(t0, t0 + 3600, every: 5).isEmpty)
}

@Test func calendarPlusTeamsMakesOneOfferWithTheEvent() {
    var r = Rig()
    r.events = [meeting("Standup", at: t0)]
    r.procs = [.teams]
    // okno kalendarza otwiera się w t0-60, Teams osiąga 12 s w tym samym tiku: jedna pigułka, nie dwie
    let acts = r.run(t0 - 72, t0 + 120)
    #expect(acts.count == 1)
    guard case .show(let o)? = acts.first else { Issue.record("no offer"); return }
    #expect(o.source == .calendarAndCall && o.event == r.events[0] && o.title == "Standup")
    #expect(o.id == r.events[0].id && o.app == teamsFamily)
}

@Test func calendarOnlyOfferUpgradesToCalendarAndCallWhenTeamsJoins() {
    var r = Rig()
    r.events = [meeting("Standup", at: t0)]
    var acts = r.run(t0 - 60, t0 - 50)
    r.procs = [.teams]
    acts += r.run(t0 - 49, t0 + 120)
    #expect(acts.count == 2)
    guard case .show(let a)? = acts.first, case .show(let b)? = acts.last else { Issue.record("expected two shows"); return }
    #expect(a.source == .calendar && b.source == .calendarAndCall)
    #expect(a.id == b.id && b.event == r.events[0] && b.app == teamsFamily)
}

@Test func overlappingEventsOfferTheOneStartingClosestToNow() {
    var r = Rig()
    r.events = [meeting("A", at: t0), meeting("B", at: t0 + 120)]
    guard case .show(let first)? = r.step(t0 + 30) else { Issue.record("no offer"); return }
    #expect(first.title == "A")   // 30 s od A, 90 s od B
    guard case .show(let second)? = r.step(t0 + 100) else { Issue.record("no switch to B"); return }
    #expect(second.title == "B")  // 100 s od A, 20 s od B
    // bez migotania: dalej tylko jedno przełączenie, potem koniec okna B
    #expect(r.run(t0 + 101, t0 + 720, every: 5).isEmpty)
    #expect(r.step(t0 + 721) == .hide)

    // remis: ten sam początek wybiera stabilnie po id, niezależnie od kolejności na liście
    var t = Rig()
    t.events = [meeting("Y", at: t0), meeting("X", at: t0)]
    guard case .show(let tied)? = t.step(t0) else { Issue.record("no offer"); return }
    #expect(tied.title == "X")
    t.events.reverse()
    #expect(t.run(t0 + 1, t0 + 300).isEmpty)
}

@Test func autoStartNeverFiresOnCalendarAlone() {
    var r = Rig()
    r.autoStart = true
    r.events = [meeting("Standup", at: t0)]
    let acts = r.run(t0 - 60, t0 + 600)
    #expect(acts.count == 1)
    guard case .show(let o)? = acts.first else { Issue.record("expected only a show"); return }
    #expect(o.source == .calendar)
}

@Test func autoStartFiresForACall() {
    var r = Rig()
    r.autoStart = true
    r.procs = [.teams]
    #expect(r.run(t0, t0 + 11).isEmpty)
    guard case .startRecording(let o)? = r.step(t0 + 12) else { Issue.record("no auto-start"); return }
    #expect(o.source == .call && o.title == "Call in Teams")
    // „startuje": bez powtórzeń, dopóki recording nie stanie się true
    #expect(r.run(t0 + 13, t0 + 120).isEmpty)
}

@Test func autoStartFiresForCalendarPlusCall() {
    var r = Rig()
    r.autoStart = true
    r.events = [meeting("Standup", at: t0)]
    r.procs = [.teams]
    let acts = r.run(t0 - 72, t0 + 120)
    #expect(acts.count == 1)
    guard case .startRecording(let o)? = acts.first else { Issue.record("no auto-start"); return }
    #expect(o.source == .calendarAndCall && o.event == r.events[0])
}

@Test func dismissedOfferStaysQuietForTheWholeMicSession() {
    var r = Rig()
    r.procs = [.teams]
    guard case .show? = r.run(t0, t0 + 12).last else { Issue.record("no offer"); return }
    r.d.dismiss()
    // dwie godziny ciągłego użycia (tiki co minutę)
    #expect(!r.run(t0 + 13, t0 + 7200, every: 60).contains(where: isOffering))
}

@Test func dismissedOfferReturnsForANewMicSession() {
    var r = Rig()
    r.procs = [.teams]
    _ = r.run(t0, t0 + 12)
    r.d.dismiss()
    #expect(!r.run(t0 + 13, t0 + 100).contains(where: isOffering))
    // krótka przerwa (10 s < releaseSeconds) nie kończy sesji
    r.procs = []
    #expect(!r.run(t0 + 101, t0 + 110).contains(where: isOffering))
    r.procs = [.teams]
    #expect(!r.run(t0 + 111, t0 + 200).contains(where: isOffering))
    // przerwa ≥ releaseSeconds kończy sesję i wyciszenie
    r.procs = []
    #expect(!r.run(t0 + 201, t0 + 221).contains(where: isOffering))
    r.procs = [.teams]
    #expect(r.run(t0 + 222, t0 + 233).isEmpty)
    guard case .show(let o)? = r.step(t0 + 234) else { Issue.record("no offer in the new session"); return }
    #expect(o.source == .call)
}

@Test func dismissedOfferStaysQuietAcrossHelperProcessesOfTheSameApp() {
    var r = Rig()
    r.procs = [.teams]
    _ = r.run(t0, t0 + 12)
    r.d.dismiss()
    r.procs = [.teams, .teamsHelper]
    #expect(!r.run(t0 + 13, t0 + 30).contains(where: isOffering))
    r.procs = [.teamsHelper]   // inny pid i inny bundle ID tej samej rodziny
    #expect(!r.run(t0 + 31, t0 + 3600, every: 5).contains(where: isOffering))
}

@Test func dismissedEventStaysQuietForTheSameEvent() {
    var r = Rig()
    r.events = [meeting("A", at: t0)]
    guard case .show? = r.step(t0) else { Issue.record("no offer"); return }
    r.d.dismiss()
    #expect(r.step(t0 + 1) == .hide)
    #expect(!r.run(t0 + 2, t0 + 600, every: 5).contains(where: isOffering))
    // inne wydarzenie oferuje normalnie, mimo że A nadal jest na liście
    r.events = [meeting("A", at: t0), meeting("B", at: t0 + 700)]
    #expect(r.step(t0 + 601) == nil)
    guard case .show(let o)? = r.step(t0 + 640) else { Issue.record("B not offered"); return }
    #expect(o.title == "B")
}

@Test func manualStopSilencesAutoStartForTheSameCall() {
    var r = Rig()
    r.autoStart = true
    r.procs = [.teams]
    guard case .startRecording? = r.run(t0, t0 + 12).last else { Issue.record("no auto-start"); return }
    r.recording = true
    _ = r.run(t0 + 13, t0 + 600, every: 10)
    r.recording = false   // ręczny Stop; Teams dalej trzyma mikrofon
    #expect(!r.run(t0 + 601, t0 + 601 + 7200, every: 10).contains(where: isOffering))
}

@Test func manualStopDuringAMicBlipStaysQuiet() {
    var r = Rig()
    r.autoStart = true
    r.procs = [.teams]
    _ = r.run(t0, t0 + 12)
    r.recording = true
    _ = r.run(t0 + 13, t0 + 30)
    r.recording = false
    r.procs = []   // Stop w chwili krótkiego zwolnienia (< releaseSeconds)
    #expect(!r.run(t0 + 31, t0 + 35).contains(where: isOffering))
    r.procs = [.teams]
    #expect(!r.run(t0 + 36, t0 + 3600, every: 5).contains(where: isOffering))
}

@Test func afterManualStopANewCallOffersAgain() {
    for autoStart in [false, true] {
        var r = Rig()
        r.autoStart = autoStart
        r.procs = [.teams]
        _ = r.run(t0, t0 + 12)
        r.recording = true
        _ = r.run(t0 + 13, t0 + 100, every: 5)
        r.recording = false
        #expect(!r.run(t0 + 101, t0 + 160).contains(where: isOffering))
        r.procs = []   // Teams zwalnia na ≥ releaseSeconds
        #expect(!r.run(t0 + 161, t0 + 181).contains(where: isOffering))
        r.procs = [.teams]
        #expect(r.run(t0 + 182, t0 + 193).isEmpty)
        let next = r.step(t0 + 194)
        if autoStart {
            guard case .startRecording(let o)? = next else { Issue.record("no auto-start for the new call"); return }
            #expect(o.source == .call)
        } else {
            guard case .show(let o)? = next else { Issue.record("no offer for the new call"); return }
            #expect(o.source == .call)
        }
    }
}

@Test func callAlreadyInProgressAtLaunchOffersAfterStartSeconds() {
    var r = Rig()
    let launch = t0 + 5000
    r.procs = [.teams]   // aplikacja startuje w trakcie trwającej rozmowy
    #expect(r.run(launch, launch + 11).isEmpty)
    guard case .show(let o)? = r.step(launch + 12) else { Issue.record("no offer"); return }
    #expect(o.source == .call)
}

@Test func offerDisappearsWhenItsEventIsRemoved() {
    var r = Rig()
    r.events = [meeting("Standup", at: t0)]
    guard case .show? = r.step(t0) else { Issue.record("no offer"); return }
    r.events = []
    #expect(r.step(t0 + 1) == .hide)
    #expect(r.step(t0 + 2) == nil)

    // oferta z wydarzeniem i rozmową: gdy wydarzenie znika, a Teams trzyma mikrofon, zostaje oferta ad hoc
    var q = Rig()
    q.events = [meeting("Standup", at: t0)]
    q.procs = [.teams]
    let acts = q.run(t0 - 72, t0 - 60)
    #expect(acts.count == 1)
    q.events = []
    guard case .show(let o)? = q.step(t0 - 59) else { Issue.record("no fallback to the call"); return }
    #expect(o.source == .call && o.event == nil && o.title == "Call in Teams")
}

@Test func recordingSuppressesOffers() {
    var r = Rig()
    r.autoStart = true
    r.recording = true
    r.events = [meeting("Standup", at: t0)]
    r.procs = [.teams]
    #expect(r.run(t0 - 70, t0 + 700).isEmpty)

    // oferta na ekranie, potem nagranie: jedno .hide
    var q = Rig()
    q.events = [meeting("Standup", at: t0)]
    guard case .show? = q.step(t0 - 59) else { Issue.record("no offer"); return }
    q.recording = true
    #expect(q.step(t0 - 30) == .hide)
    #expect(q.step(t0 - 29) == nil)
}

@Test func callsDisabledKeepsCalendarOffers() {
    var r = Rig()
    r.callsEnabled = false
    r.autoStart = true
    r.procs = [.teams]
    #expect(r.run(t0, t0 + 3600, every: 5).isEmpty)
    r.events = [meeting("Standup", at: t0 + 3700)]
    let acts = r.run(t0 + 3640, t0 + 3800)
    #expect(acts.count == 1)
    guard case .show(let o)? = acts.first else { Issue.record("calendar offer lost"); return }
    #expect(o.source == .calendar)   // Teams nie dołącza się do oferty ani nie uruchamia auto-startu
}

@Test func manualStopSilencesTheEventStillInItsWindow() {
    var r = Rig()
    r.events = [meeting("Standup", at: t0)]
    r.recording = true   // nagranie ręczne w trakcie okna oferty
    #expect(r.run(t0, t0 + 120, every: 10).isEmpty)
    r.recording = false
    #expect(!r.run(t0 + 121, t0 + 1000, every: 5).contains(where: isOffering))
}

@Test func dismissedCalendarOfferDoesNotComeBackAsAnAdHocCall() {
    for autoStart in [false, true] {
        var r = Rig()
        r.autoStart = autoStart
        r.events = [meeting("A", at: t0)]
        guard case .show? = r.step(t0 - 30) else { Issue.record("no offer"); return }
        r.d.dismiss()
        r.procs = [.teams]   // Teams dołącza już po odrzuceniu A, w oknie A: wydarzenie jest odfiltrowane, więc event == nil
        // także po końcu okna (t0 + 600): ta sama sesja mikrofonu milknie razem z wydarzeniem
        #expect(!r.run(t0 - 29, t0 + 700).contains(where: isOffering))
    }
}

@Test func manualStopWithAnEventInItsWindowKeepsALaterCallQuiet() {
    for autoStart in [false, true] {
        var r = Rig()
        r.autoStart = autoStart
        r.events = [meeting("A", at: t0)]
        r.recording = true   // nagranie ręczne w oknie A, Teams jeszcze nie gra
        _ = r.run(t0 - 30, t0 + 100, every: 10)
        r.recording = false
        _ = r.step(t0 + 101)   // tik Stop bez rozmowy: wyciszenie obejmuje tylko wydarzenie A
        r.procs = [.teams]     // Teams zaczyna po Stop, nadal w oknie A
        #expect(!r.run(t0 + 102, t0 + 700).contains(where: isOffering))
    }
}

@Test func aNewCallAfterTheMutedEventWindowOffersNormally() {
    var r = Rig()
    r.events = [meeting("A", at: t0)]
    guard case .show? = r.step(t0 - 30) else { Issue.record("no offer"); return }
    r.d.dismiss()
    #expect(r.run(t0 - 29, t0 + 650, every: 5) == [.hide])
    r.procs = [.teams]
    #expect(r.run(t0 + 651, t0 + 662).isEmpty)
    guard case .show(let o)? = r.step(t0 + 663) else { Issue.record("no offer for the call after the window"); return }
    #expect(o.source == .call && o.event == nil)
}

@Test func calendarOfferEndsWithTheEventNotAfterGrace() {
    var r = Rig()
    r.events = [meeting("Short", at: t0, minutes: 5)]
    guard case .show? = r.step(t0) else { Issue.record("no offer"); return }
    #expect(r.step(t0 + 299) == nil)
    #expect(r.step(t0 + 300) == .hide)   // koniec wydarzenia (5 min), nie start + offerGrace (10 min)
    #expect(r.run(t0 + 301, t0 + 700, every: 5).isEmpty)
}

@Test func gapLongerThanThreeSecondsBetweenTicksResetsContinuity() {
    // przerwa dokładnie 3 s (np. jeden pominięty tik) nie zrywa ciągłości
    var ok = Rig()
    ok.procs = [.teams]
    #expect(ok.run(t0, t0 + 5).isEmpty)
    #expect(ok.step(t0 + 8) == nil)
    #expect(ok.run(t0 + 9, t0 + 11).isEmpty)
    guard case .show? = ok.step(t0 + 12) else { Issue.record("3 s gap must not reset"); return }

    // przerwa 4 s (uśpienie, App Nap) zeruje: ciągłość nie jest dowiedziona
    var r = Rig()
    r.procs = [.teams]
    #expect(r.run(t0, t0 + 5).isEmpty)
    #expect(r.step(t0 + 9) == nil)
    #expect(r.run(t0 + 10, t0 + 20).isEmpty)
    guard case .show? = r.step(t0 + 21) else { Issue.record("no offer 12 s after the gap"); return }
}

@Test func appOnBothCallAndIgnoredListsIsInvisible() {
    var t = MeetingTuning.test
    t.callApps = [teamsFamily]
    t.ignoredApps = [teamsFamily]
    var d = OfferDetector(tuning: t)
    var out: [OfferAction] = []
    for i in 0...60 {
        if let a = d.step(now: t0 + Double(i), events: [], processes: [.teams], recording: false, callsEnabled: true, autoStart: true) { out.append(a) }
    }
    #expect(out.isEmpty)
}

@Test func micSessionEndsAtExactlyReleaseSeconds() {
    // wyciszenie sesji znika, gdy wejście milczy >= releaseSeconds (20 s): 19 s jeszcze nie, 20 s tak
    for (gap, offers) in [(19.0, false), (20.0, true)] {
        var r = Rig()
        r.procs = [.teams]
        _ = r.run(t0, t0 + 12)   // oferta; ostatnie wejście w t0 + 12
        r.d.dismiss()
        r.procs = []
        _ = r.run(t0 + 13, t0 + 12 + gap)
        r.procs = [.teams]
        #expect(r.run(t0 + 13 + gap, t0 + 25 + gap).contains(where: isOffering) == offers)
    }
}
