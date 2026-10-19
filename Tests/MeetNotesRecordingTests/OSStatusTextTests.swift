import Testing
@testable import MeetNotesRecording

@Test func osStatusFourCCIsTranslated() {
    // 2003334207 = 'wht?' — surowy kod z komunikatu o nieotwartym pliku ścieżki (BACKLOG D3/odbiór).
    #expect(OSStatusText.fourCC(2003334207) == "wht?")
    #expect(OSStatusText.describe(2003334207).contains("missing or unreadable"))
    #expect(OSStatusText.describe(-50).contains("-50")) // nie-czteroznakowy kod zostaje liczbą
    #expect(!OSStatusText.describe(1718449215).contains("missing")) // 'fmt?' to nie to samo
}
