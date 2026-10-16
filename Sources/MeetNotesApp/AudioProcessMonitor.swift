import CoreAudio
import Foundation
import MeetNotesMeetings

/// Lista procesów Core Audio (`kAudioHardwarePropertyProcessObjectList`) z flagą użycia wejścia. Własny proces pominięty.
/// Pusta lub nieudana lista → `[]`. Nie loguje niczego.
final class AudioProcessMonitor: AudioProcessSource {
    func snapshot() -> [AudioProcessSample] {
        let me = ProcessInfo.processInfo.processIdentifier
        return Self.processObjects().ids.compactMap { id in
            guard let pid = Self.number(id, kAudioProcessPropertyPID, as: Int32.self), pid != me else { return nil }
            let input = (Self.number(id, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 0) != 0
            return AudioProcessSample(pid: pid, bundleID: Self.bundleID(id) ?? "", isRunningInput: input)
        }
    }

    // Wspólne z `Probes.audio()`.

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func processObjects() -> (ids: [AudioObjectID], status: OSStatus) {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        var st = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        guard st == noErr else { return ([], st) }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return (st == noErr ? ids : [], st)
    }

    static func number<T: FixedWidthInteger>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var addr = address(selector)
        var v: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func bundleID(_ obj: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &s) == noErr else { return nil }
        return s?.takeRetainedValue() as String?
    }
}
