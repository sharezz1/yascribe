import Foundation
import MeetNotesMeetings
import MeetNotesProviders

extension MeetingTuning {
    /// Inicjalizuj na bazie `MeetingSettings` — nadpisz thresholdy i aplikacje ignorowane.
    init(settings: MeetingSettings?) {
        self.init()
        let applied = applying(startSeconds: settings?.startSeconds, releaseSeconds: settings?.releaseSeconds, silenceSeconds: settings?.silenceSeconds, ignoredApps: settings?.ignoredApps)
        self = applied
    }
}
