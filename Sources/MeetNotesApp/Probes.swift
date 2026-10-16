import CoreAudio
import EventKit
import Foundation
import ServiceManagement

/// Sondy fazy 1.6 (spec §5, plan T0): `MEETNOTES_PROBE=calendar|audio|login`. Wypisują na stdout i kończą proces.
/// Narzędzie deweloperskie, jak `Snapshots`. Nie wypisują tytułów, adresów e-mail ani treści pól z kalendarza —
/// tylko flagi, liczby i nazwy wzorców; w liniach audio są bundle ID i PID.
/// `login` zmienia pozycje logowania w systemie — uruchamia ją wyłącznie użytkownik.
enum Probes {
    static func runIfRequested() {
        guard let name = ProcessInfo.processInfo.environment["MEETNOTES_PROBE"], !name.isEmpty else { return }
        Task.detached {
            switch name {
            case "calendar": await calendar()
            case "audio": await audio()
            case "login": login()
            default:
                FileHandle.standardError.write(Data("MEETNOTES_PROBE: unknown probe \"\(name)\" (calendar | audio | login)\n".utf8))
                exit(2)
            }
            exit(0)
        }
    }

    /// `print` do potoku jest buforowany blokowo; sondy mają pokazywać linie od razu.
    private static func out(_ s: String) {
        print(s)
        fflush(stdout)
    }

    private static func clock(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    // MARK: calendar

    // ponytail: wzorce na sztywno; w aplikacji będą nastawne (`MeetingTuning.linkPatterns`, plan T1)
    private static let linkPatterns: [(name: String, needles: [String])] = [
        ("teams", ["teams.microsoft.com/l/meetup-join", "teams.live.com"]),
        ("meet", ["meet.google.com"]),
        ("zoom", ["zoom.us/j"]),
        ("webex", ["webex.com"]),
    ]

    private static func kinds(in text: String?) -> String {
        guard let t = text?.lowercased(), !t.isEmpty else { return "-" }
        let hits = linkPatterns.filter { p in p.needles.contains { t.contains($0) } }.map(\.name)
        return hits.isEmpty ? "-" : hits.joined(separator: ",")
    }

    private static func yn(_ b: Bool) -> String { b ? "Y" : "N" }

    private static func calendar() async {
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            out("access: granted=\(granted) status=\(EKEventStore.authorizationStatus(for: .event).rawValue)")
            guard granted else { return }
        } catch {
            out("access: error \(error)")
            return
        }
        let now = Date()
        let day: TimeInterval = 86_400
        let predicate = store.predicateForEvents(withStart: now - 14 * day, end: now + 7 * day, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        out("events: \(events.count) in [-14d, +7d]")
        out("# dayOffset | allDay | hours | availability | status | calType | myStatus | organizer | attendees | hasURL | url | location | notes | extId | recurring | detached")
        for e in events {
            let me = e.attendees?.first { $0.isCurrentUser }
            // `none` = brak wpisu użytkownika w uczestnikach (np. własne wydarzenie bez zaproszonych).
            let myStatus = me.map { "\($0.participantStatus.rawValue)" } ?? "none"
            let hours = e.endDate.timeIntervalSince(e.startDate) / 3600
            let offset = Int((e.startDate.timeIntervalSince(now) / day).rounded(.down))
            out([
                "\(offset)", yn(e.isAllDay), String(format: "%.2f", hours),
                "avail=\(e.availability.rawValue)", "status=\(e.status.rawValue)", "cal=\(e.calendar?.type.rawValue ?? -1)",
                "me=\(myStatus)", "org=\(yn(e.organizer?.isCurrentUser ?? false))", "att=\(e.attendees?.count ?? 0)",
                "hasURL=\(yn(e.url != nil))", "url=\(kinds(in: e.url?.absoluteString))",
                "loc=\(kinds(in: e.location))", "notes=\(kinds(in: e.notes))",
                "extId=\(yn(!(e.calendarItemExternalIdentifier ?? "").isEmpty))",
                "rec=\(yn(e.hasRecurrenceRules))", "detached=\(yn(e.isDetached))",
            ].joined(separator: " | "))
        }
        out("legend: avail 0 busy,1 free,2 tentative,3 unavailable,-1 notSupported; status 0 none,1 confirmed,2 tentative,3 canceled;")
        out("        cal 0 local,1 calDAV,2 exchange,3 subscription,4 birthday; me 0 unknown,1 pending,2 accepted,3 declined,4 tentative,5 delegated,6 completed,7 inProcess,none")
    }

    // MARK: audio

    private struct Proc { var pid: Int32; var bundle: String; var input: Bool }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> (ids: [AudioObjectID], status: OSStatus) {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        var st = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        guard st == noErr else { return ([], st) }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return (st == noErr ? ids : [], st)
    }

    private static func number<T: FixedWidthInteger>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var addr = address(selector)
        var v: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func bundleID(_ obj: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &s) == noErr else { return nil }
        return s?.takeRetainedValue() as String?
    }

    /// Co sekundę lista procesów Core Audio; na stdout tylko zmiany `IsRunningInput`. Działa do Ctrl-C.
    private static func audio() async {
        let me = ProcessInfo.processInfo.processIdentifier
        var known: [AudioObjectID: Proc] = [:]
        let first = processObjects()
        // Nie sprawdzam sam, czy system pokazał monit/zgodę — to widzi użytkownik; tu tylko status odczytu listy.
        out("\(clock()) process list read: OSStatus=\(first.status) objects=\(first.ids.count) (noErr=0; watch whether the system showed a permission prompt)")
        while true {
            let (ids, st) = processObjects()
            if st != noErr { out("\(clock()) process list error: OSStatus=\(st)") }
            var seen = Set<AudioObjectID>()
            for id in ids {
                guard let pid = number(id, kAudioProcessPropertyPID, as: Int32.self), pid != me else { continue }
                seen.insert(id)
                let input = (number(id, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 0) != 0
                let p = Proc(pid: pid, bundle: bundleID(id) ?? "(no bundle id)", input: input)
                if (known[id]?.input ?? false) != input { out("\(clock()) \(p.bundle) pid=\(pid) input=\(input ? "ON" : "OFF")") }
                known[id] = p
            }
            // Proces, który zniknął z listy z włączonym wejściem, to też zwolnienie mikrofonu.
            for (id, p) in known where !seen.contains(id) {
                if p.input { out("\(clock()) \(p.bundle) pid=\(p.pid) input=OFF (process gone)") }
                known[id] = nil
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: login

    private static func login() {
        let service = SMAppService.mainApp
        out("status before: \(service.status) (rawValue \(service.status.rawValue))")
        do { try service.register(); out("register: ok") } catch { out("register: error \(error)") }
        out("status after register: \(service.status) (rawValue \(service.status.rawValue))")
        do { try service.unregister(); out("unregister: ok") } catch { out("unregister: error \(error)") }
        out("status after unregister: \(service.status) (rawValue \(service.status.rawValue))")
    }
}
