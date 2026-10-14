import AVFoundation
import CoreAudio
import Foundation

/// Cienkie opakowania na właściwości Core Audio.
public enum CoreAudioDevices {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    public static func defaultOutputDevice() throws -> AudioObjectID {
        try systemDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    public static func defaultInputDevice() throws -> AudioObjectID {
        try systemDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    static func systemDevice(_ selector: AudioObjectPropertySelector) throws -> AudioObjectID {
        var addr = address(selector)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        guard st == noErr, id != kAudioObjectUnknown else { throw AudioSourceError.deviceUnavailable("selector \(selector)") }
        return id
    }

    public static func uid(of device: AudioObjectID) throws -> String {
        var addr = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid)
        guard st == noErr, let v = uid?.takeRetainedValue() else { throw AudioSourceError.coreAudio("DeviceUID", st) }
        return v as String
    }

    /// Format strumienia wejściowego urządzenia (albo urządzenia zbiorczego z tapem).
    public static func inputFormat(of device: AudioObjectID) throws -> AVAudioFormat {
        var addr = address(kAudioDevicePropertyStreamFormat, kAudioObjectPropertyScopeInput)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let st = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &asbd)
        guard st == noErr, let f = format(asbd) else {
            throw AudioSourceError.coreAudio("StreamFormat", st)
        }
        return f
    }

    public static func tapFormat(of tap: AudioObjectID) throws -> AVAudioFormat {
        var addr = address(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let st = AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd)
        guard st == noErr, let f = format(asbd) else {
            throw AudioSourceError.coreAudio("TapFormat", st)
        }
        return f
    }

    /// `AVAudioFormat` z opisu strumienia. Powyżej 2 kanałów AVAudioFormat wymaga
    /// układu kanałów, inaczej zwraca nil — a tak wystawia się wbudowany mikrofon
    /// MacBooka, gdy działa przetwarzanie głosu (3 kanały, sonda S2).
    static func format(_ asbd: AudioStreamBasicDescription) -> AVAudioFormat? {
        var d = asbd
        if let f = AVAudioFormat(streamDescription: &d) { return f }
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | d.mChannelsPerFrame) else { return nil }
        return AVAudioFormat(streamDescription: &d, channelLayout: layout)
    }

    public static func name(of device: AudioObjectID) throws -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name)
        guard st == noErr, let v = name?.takeRetainedValue() else { throw AudioSourceError.coreAudio("DeviceName", st) }
        return v as String
    }

    /// Nazwa mikrofonu, który nagrywa `RawMicrophoneSource` (domyślne wejście systemu; wybór urządzenia: faza 2).
    public static func defaultInputName() -> String? {
        guard let d = try? defaultInputDevice() else { return nil }
        return try? name(of: d)
    }
}
