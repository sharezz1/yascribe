import Foundation

/// Czy aplikacja robi coś, czego restart nie może przerwać (nagrywanie, zapis, przenoszenie nagrań).
@MainActor
public protocol RecordingActivity: AnyObject {
    var isBusy: Bool { get }
}

public enum UpdatePhase: Equatable {
    case idle
    /// Od pierwszego kliknięcia „Install Update" do końca cyklu (także podczas odroczonego restartu).
    case installing
    case restartPostponed
}

/// Bramka restartu po aktualizacji: nie pozwala Sparkle zrestartować aplikacji w trakcie nagrania i blokuje nowe nagrania,
/// gdy instalacja trwa. Wszystko na MainActor, bez blokad; blok restartu jest trzymany co najwyżej jeden.
@MainActor
public final class RestartGate {
    private let activity: any RecordingActivity
    private var held: (@MainActor @Sendable () -> Void)?
    public private(set) var phase: UpdatePhase = .idle {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    /// Zmiana fazy (np. restart odroczony do końca nagrania): interfejs pokazuje komunikat, zamiast milczeć.
    public var onPhaseChange: (@MainActor (UpdatePhase) -> Void)?

    public init(activity: any RecordingActivity) { self.activity = activity }

    /// `true` = restart odroczony (blok zostanie wywołany raz, gdy aktywność ustanie). `false` = Sparkle może restartować.
    public func shouldPostpone(untilInvoking block: @escaping @MainActor @Sendable () -> Void) -> Bool {
        guard activity.isBusy else { return false }
        held = block
        phase = .restartPostponed
        return true
    }

    /// Wołać, gdy nagranie lub zapis się kończy.
    public func activityDidChange() {
        guard phase == .restartPostponed, !activity.isBusy, let block = held else { return }
        held = nil
        phase = .installing
        block()
    }

    public func installationStarted() { if phase == .idle { phase = .installing } }

    /// Błąd, anulowanie albo koniec cyklu: porzuca odroczony blok i zdejmuje blokadę nagrywania.
    public func installationEnded() {
        held = nil
        phase = .idle
    }

    /// Druga, niezależna bariera: Sparkle może nie zawołać callbacku odroczenia.
    public func shouldTerminate() -> Bool { !activity.isBusy }

    public var canStartRecording: Bool { phase == .idle }
}
