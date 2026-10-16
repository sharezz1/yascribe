import Foundation
import Testing
@testable import MeetNotesMeetings

private let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 10))!

fileprivate extension MeetingTuning {
    static var test: MeetingTuning {
        var t = MeetingTuning()
        t.releaseSeconds = 20
        t.silenceSeconds = 180
        t.snoozeSeconds = 600
        return t
    }
}

fileprivate extension AudioProcessSample {
    /// Pomiar T0: mikrofon trzyma proces pomocniczy, nie `com.microsoft.teams2`.
    static let teams = AudioProcessSample(pid: 100, bundleID: "com.microsoft.teams2.modulehost", isRunningInput: true)
    static let teamsHelper = AudioProcessSample(pid: 200, bundleID: "com.microsoft.teams2.helper", isRunningInput: true)
    static let speech = AudioProcessSample(pid: 300, bundleID: "com.apple.CoreSpeech", isRunningInput: true)
    static let zoom = AudioProcessSample(pid: 500, bundleID: "us.zoom.xos", isRunningInput: true)
}

/// Tiki co `every` s od `from` do `to` włącznie (nagranie trwa); zwraca tylko niepuste akcje.
private func run(_ d: inout EndDetector, _ from: Double, _ to: Double, _ procs: [AudioProcessSample],
                 silent: Double = 0, every: Double = 1) -> [EndAction] {
    var out: [EndAction] = []
    var t = from
    while t <= to {
        if let a = d.step(now: t0 + t, recording: true, processes: procs, silentSeconds: silent) { out.append(a) }
        t += every
    }
    return out
}

private func tick(_ d: inout EndDetector, _ t: Double, _ procs: [AudioProcessSample], silent: Double = 0) -> EndAction? {
    d.step(now: t0 + t, recording: true, processes: procs, silentSeconds: silent)
}

@Test func releaseLongerThanReleaseSecondsPrompts() {
    var d = EndDetector(tuning: .test)
    _ = tick(&d, 0, [.teams])
    #expect(tick(&d, 19, []) == nil)
    #expect(tick(&d, 41, []) == .prompt(.callReleased))
    #expect(tick(&d, 42, []) == nil)  // akcja tylko przy zmianie stanu
}

@Test func releaseAndSilenceThresholdsAreInclusive() {
    var r = EndDetector(tuning: .test)
    _ = tick(&r, 0, [.teams])
    #expect(tick(&r, 19, []) == nil)
    #expect(tick(&r, 20, []) == .prompt(.callReleased))   // dokładnie releaseSeconds

    var s = EndDetector(tuning: .test)
    #expect(tick(&s, 0, [.teams], silent: 179) == nil)
    #expect(tick(&s, 1, [.teams], silent: 180) == .prompt(.silence))   // dokładnie silenceSeconds
}

@Test func shortMicReleaseDoesNotEndTheMeeting() {
    var d = EndDetector(tuning: .test)
    var actions = run(&d, 0, 5, [.teams])
    actions += run(&d, 6, 15, [])         // 10 s bez wejścia (Teams łączy się ponownie)
    actions += run(&d, 16, 600, [.teams])
    #expect(actions.isEmpty)
}

@Test func silenceAloneOnlyPrompts() {
    var d = EndDetector(tuning: .test)
    #expect(tick(&d, 0, [.teams], silent: 179) == nil)
    #expect(tick(&d, 1, [.teams], silent: 181) == .prompt(.silence))
    #expect(tick(&d, 2, [.teams], silent: 182) == nil)
}

@Test func noInputNeverYieldsAnythingButAPrompt() {
    var d = EndDetector(tuning: .test)
    var actions = run(&d, 0, 5, [.teams])
    actions += run(&d, 6, 4 * 3600, [], silent: 600, every: 10)  // 4 h bez wejścia i z ciszą
    for a in actions {
        switch a {  // typ nie ma przypadku zatrzymania; test pilnuje, że nie zostanie dodany
        case .prompt, .dismissPrompt: break
        }
    }
    #expect(actions == [.prompt(.silence)])  // cisza od 1. tiku wyprzedza zwolnienie; jedno pytanie, bez powtórek
}

@Test func continueSnoozesThePromptForSnoozeSeconds() {
    // granica snoozeSeconds (600 s): 599 s jeszcze cisza, 600 i 601 s pytanie wraca
    for (after, prompts) in [(599.0, false), (600.0, true), (601.0, true)] {
        var d = EndDetector(tuning: .test)
        #expect(tick(&d, 0, [.teams], silent: 181) == .prompt(.silence))
        d.continueMeeting(now: t0)
        #expect(tick(&d, after, [.teams], silent: 181) == (prompts ? .prompt(.silence) : nil))
    }
}

@Test func continueAfterCallReleasedDoesNotAskAgainOnTheSameReleasedCall() {
    // Wcześniej „Continue" zostawiało śledzoną rodzinę, więc po snooze pytanie wracało co 600 s, jeśli spotkanie trwa dalej
    // w sali (mikrofon Teams zwolniony na dobre). Teraz „Continue" zapomina rodziny: wraca tylko cisza albo nowa rozmowa.
    var d = EndDetector(tuning: .test)
    _ = tick(&d, 0, [.teams])
    #expect(tick(&d, 41, []) == .prompt(.callReleased))
    d.continueMeeting(now: t0 + 41)
    #expect(run(&d, 42, 41 + 3600, [], every: 5).isEmpty)       // godzina po snooze: żadnego pytania z tego samego zwolnienia
    #expect(tick(&d, 41 + 3601, [], silent: 181) == .prompt(.silence))   // cisza dalej pyta
    // nowa rozmowa w tym samym nagraniu jest śledzona od nowa
    d.continueMeeting(now: t0 + 41 + 3601)
    _ = run(&d, 41 + 3602, 41 + 8000, [.teams], every: 100)
    #expect(tick(&d, 41 + 8021, []) == .prompt(.callReleased))
}

@Test func manualStartAdoptsACallThatStartsLater() {
    var d = EndDetector(tuning: .test)
    #expect(run(&d, 0, 59, []).isEmpty)        // ręczny start, jeszcze żadnej rozmowy
    #expect(run(&d, 60, 65, [.teams]).isEmpty) // Teams zaczyna w trakcie nagrania
    #expect(tick(&d, 65 + 19, []) == nil)
    #expect(tick(&d, 65 + 21, []) == .prompt(.callReleased))
}

@Test func manualStartWithoutACallNeverPromptsOnMicRelease() {
    var d = EndDetector(tuning: .test)
    var actions = run(&d, 0, 30, [.zoom])      // aplikacja spoza callApps nie jest śledzona
    actions += run(&d, 31, 170, [])            // zwolnienie mikrofonu nic nie znaczy
    #expect(actions.isEmpty)
    #expect(tick(&d, 171, [], silent: 181) == .prompt(.silence))  // tylko cisza
}

@Test func promptIsDismissedWhenTheCallComesBack() {
    var d = EndDetector(tuning: .test)
    _ = tick(&d, 0, [.teams])
    #expect(tick(&d, 41, []) == .prompt(.callReleased))
    #expect(tick(&d, 42, [.teams]) == .dismissPrompt)
    #expect(tick(&d, 43, [.teams]) == nil)
    // to samo dla ciszy: dźwięk wraca
    #expect(tick(&d, 44, [.teams], silent: 181) == .prompt(.silence))
    #expect(tick(&d, 45, [.teams], silent: 0) == .dismissPrompt)
}

@Test func notRecordingProducesNoActions() {
    var d = EndDetector(tuning: .test)
    #expect(d.step(now: t0, recording: false, processes: [.teams], silentSeconds: 9999) == nil)
    _ = tick(&d, 1, [.teams])
    #expect(d.step(now: t0 + 2, recording: false, processes: [], silentSeconds: 9999) == nil)
    // nowe nagranie zaczyna od czystego stanu: poprzednio śledzony Teams jest zapomniany
    #expect(tick(&d, 100, []) == nil)
    d.reset()
    #expect(tick(&d, 101, []) == nil)
}

@Test func helperProcessOfTheSameFamilyKeepsTheCallAlive() {
    var d = EndDetector(tuning: .test)
    var actions = run(&d, 0, 5, [.teams])
    actions += run(&d, 6, 120, [.teamsHelper])  // wejście przeszło na inny proces rodziny
    #expect(actions.isEmpty)
    #expect(tick(&d, 121 + 21, []) == .prompt(.callReleased))
}

@Test func ignoredAppsAreNeverTracked() {
    var d = EndDetector(tuning: .test)
    _ = tick(&d, 0, [.teams, .speech])
    // CoreSpeech trzyma wejście cały czas, Teams zwalnia: i tak koniec rozmowy
    #expect(tick(&d, 10, [.speech]) == nil)
    #expect(tick(&d, 41, [.speech]) == .prompt(.callReleased))
}

@Test func appOnBothCallAndIgnoredListsIsNeverTracked() {
    var t = MeetingTuning.test
    t.callApps = ["com.microsoft.teams2"]
    t.ignoredApps = ["com.microsoft.teams2"]
    var d = EndDetector(tuning: t)
    _ = tick(&d, 0, [.teams])
    #expect(run(&d, 1, 600, []).isEmpty)   // gdyby była śledzona, zwolnienie dałoby pytanie
}
