import Foundation

public enum EndSignal: Equatable, Sendable { case callReleased, silence }

/// Brak przypadku zatrzymania: detektor NIGDY nie kończy nagrania, tylko pyta ("Meeting ended?").
public enum EndAction: Equatable, Sendable { case prompt(EndSignal), dismissPrompt }

/// Wykrywanie końca spotkania (spec §4.6). Czysta maszyna stanów: czas wstrzykiwany (`now`), zero `Date()`.
/// "Śledzona" rodzina = rodzina z `callApps` (nie z `ignoredApps`), która w jakimkolwiek tiku nagrania miała proces z wejściem
/// (także jeśli zaczęła po starcie nagrania). Klucz to rodzina, nie `pid` (Teams przerzuca wejście między procesami pomocniczymi).
/// Wyciszenie w Teams NIE zwalnia wejścia (pomiar T0), więc nie jest tu osobnym przypadkiem.
public struct EndDetector {
    private let tuning: MeetingTuning
    /// Śledzona rodzina → ostatni tik z wejściem.
    private var lastInput: [String: Date] = [:]
    /// Pytanie, które aktualnie wisi (z którego sygnału).
    private var shown: EndSignal?
    private var snoozedUntil: Date?

    public init(tuning: MeetingTuning) { self.tuning = tuning }

    /// Zwraca akcję tylko przy zmianie stanu.
    public mutating func step(now: Date, recording: Bool, processes: [AudioProcessSample], silentSeconds: Double) -> EndAction? {
        guard recording else { reset(); return nil }
        for p in processes where p.isRunningInput {
            if let fam = tuning.family(of: p.bundleID) { lastInput[fam] = now }
        }
        // callReleased: jest śledzona rodzina i żadna nie miała wejścia przez >= releaseSeconds.
        let released = !lastInput.isEmpty && lastInput.values.allSatisfy { now.timeIntervalSince($0) >= tuning.releaseSeconds }
        let signal: EndSignal? = released ? .callReleased : silentSeconds >= tuning.silenceSeconds ? .silence : nil

        guard let signal else {
            defer { shown = nil }
            return shown == nil ? nil : .dismissPrompt
        }
        if shown != nil { return nil }  // jedno pytanie naraz
        if let until = snoozedUntil, now < until { return nil }
        snoozedUntil = nil
        shown = signal
        return .prompt(signal)
    }

    /// "Continue": zdejmuje wiszące pytanie i wycisza kolejne na `snoozeSeconds`. Zapomina śledzone rodziny: zwolniona rozmowa
    /// nie pyta ponownie co `snoozeSeconds`, gdy spotkanie trwa dalej (wraca tylko cisza albo nowa rozmowa).
    public mutating func continueMeeting(now: Date) {
        lastInput = [:]
        shown = nil
        snoozedUntil = now + tuning.snoozeSeconds
    }

    public mutating func reset() {
        lastInput = [:]
        shown = nil
        snoozedUntil = nil
    }
}
