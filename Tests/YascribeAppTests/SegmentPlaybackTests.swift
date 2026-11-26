import Foundation
import Testing
@testable import YascribeApp

// TASK-109: odsłuch jednego segmentu — okno na osi pliku toru i stop tylko dla bieżącego odtworzenia.

@Suite @MainActor struct SegmentPlaybackTests {
    @Test func windowShiftsBothEndsByTrackOffsetAndClamps() {
        #expect(MeetingDetailView.segmentWindow(start: 2, end: 5.5, offset: 0, fileDuration: 60) == (2, 5.5))
        #expect(MeetingDetailView.segmentWindow(start: 1, end: 3, offset: 2, fileDuration: 60) == (0, 1)) // mowa przed startem toru
        #expect(MeetingDetailView.segmentWindow(start: 3, end: 4, offset: -1, fileDuration: 60) == (4, 5))
        #expect(MeetingDetailView.segmentWindow(start: 10, end: 10.1, offset: 0, fileDuration: 60) == (10, 10.1))
        #expect(MeetingDetailView.segmentWindow(start: 58, end: 70, offset: 0, fileDuration: 60) == (58, 60)) // koniec pliku
        #expect(MeetingDetailView.segmentWindow(start: 7, end: 7, offset: 0, fileDuration: 60) == (7, 7.5)) // bez długości
        #expect(MeetingDetailView.segmentWindow(start: 70, end: 72, offset: 0, fileDuration: 60) == (60, 60))
        #expect(MeetingDetailView.segmentWindow(start: 1, end: 2, offset: 3, fileDuration: 60) == (0, 0)) // cały przed startem toru
    }

    @Test func pauseKeepsCurrentRowButClearsPlayingAndFinishClearsBoth() {
        let p = PlaybackState()
        let e = TranscriptPlaylist.Entry(row: 3, speaker: .me, start: 1, end: 2)
        p.began(e, fileFrom: 1, fileTo: 2, sessionFrom: 1)
        #expect(p.playing == 3 && p.current == 3)
        p.pause()
        #expect(p.playing == nil && p.current == 3) // podświetlenie zostaje po pauzie, ikona ⏸ znika
        p.began(e, fileFrom: 1, fileTo: 2, sessionFrom: 1)
        p.finish(position: 9)
        #expect(p.playing == nil && p.current == nil && p.clock.position == 9)
    }
}
