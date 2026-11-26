import YascribeTranscription

/// TASK-131: lista odtwarzania transkryptu — jedyne miejsce mapowania pozycja ↔ wiersz.
/// Wiersz = indeks w `utterances` transkryptu z ukrytymi (`includeHidden: true`, jak w widoku); ukryte (TASK-119) nie wchodzą na listę,
/// części podziału (TASK-127) to osobne wpisy z własnym zakresem, więc przesunięcie wierszy za podzieloną ich nie myli.
struct TranscriptPlaylist: Equatable {
    struct Entry: Equatable {
        let row: Int
        let speaker: Speaker
        let start: Double
        /// Zawsze > `start`: wypowiedź bez długości dostaje 0,5 s (jak `MeetingDetailView.segmentWindow`).
        let end: Double
    }

    /// Posortowane po (start, wiersz): kolejność odtwarzania.
    let entries: [Entry]

    static let empty = TranscriptPlaylist(entries: [])

    init(entries: [Entry]) {
        self.entries = entries.sorted { ($0.start, $0.row) < ($1.start, $1.row) }
    }

    init(_ t: Transcript) {
        self.init(entries: t.utterances.enumerated().compactMap { i, u in
            u.hidden == true ? nil : Entry(row: i, speaker: u.speaker, start: u.start, end: u.end > u.start ? u.end : u.start + 0.5)
        })
    }

    /// Koniec osi paska.
    var duration: Double { entries.map(\.end).max() ?? 0 }

    func entry(row: Int) -> Entry? { entries.first { $0.row == row } }

    /// Wiersz, którego zakres zawiera `t`; przy nakładaniu się mówców — ten, który zaczął później.
    func row(at t: Double) -> Int? { entries.last { $0.start <= t && t < $0.end }?.row }

    /// Skąd zacząć od pozycji `t`: wpis, który ją zawiera, inaczej najbliższy następny (od jego początku); `nil` = za końcem.
    func start(at t: Double) -> (entry: Entry, from: Double)? {
        if let e = entries.last(where: { $0.start <= t && t < $0.end }) { return (e, t) }
        return entries.first { $0.start > t }.map { ($0, $0.start) }
    }

    /// Następny wpis po `e`, gdy odtworzono już wszystko do `cursor`: wpisy w całości przed kursorem (nakładanie mówców) są pomijane,
    /// częściowo przed — grają od kursora, więc nic nie gra dwa razy. Cisza między wypowiedziami jest pomijana.
    func next(after e: Entry, cursor: Double) -> (entry: Entry, from: Double)? {
        entries.first { ($0.start, $0.row) > (e.start, e.row) && $0.end > cursor }.map { ($0, max($0.start, cursor)) }
    }
}
