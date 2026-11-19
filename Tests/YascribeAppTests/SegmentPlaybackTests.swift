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

    @Test func lateStopOfPreviousSegmentDoesNotStopNext() async throws {
        let p = PlaybackState()
        p.started(index: 1, seconds: 0.05)
        p.started(index: 2, seconds: 5)
        try await Task.sleep(for: .milliseconds(200))
        #expect(p.playing == 2)
        // A → B → A: ten sam indeks, ale nowe odtworzenie — stary stop nadal nie działa.
        p.started(index: 1, seconds: 0.05)
        p.started(index: 1, seconds: 5)
        try await Task.sleep(for: .milliseconds(200))
        #expect(p.playing == 1)
        p.started(index: nil, seconds: nil) // menu Meeting przejmuje odtwarzacz
        try await Task.sleep(for: .milliseconds(50))
        #expect(p.playing == nil)
    }

    @Test func segmentStopsAtEndAndStopClears() async throws {
        let p = PlaybackState()
        p.started(index: 3, seconds: 0.05)
        #expect(p.playing == 3)
        try await Task.sleep(for: .milliseconds(300))
        #expect(p.playing == nil)
        p.started(index: 4, seconds: 5)
        p.stop()
        #expect(p.playing == nil)
    }
}
