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

    /// Nominalna częstotliwość urządzenia (także zbiorczego). Format tapa bywa inny niż rzeczywisty zegar:
    /// słuchawki Bluetooth w trybie rozmowy dostarczały 16 kHz przy deklarowanych 48 kHz (faza 2.0.2, S0).
    public static func nominalSampleRate(of device: AudioObjectID) throws -> Double {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let st = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
        guard st == noErr else { throw AudioSourceError.coreAudio("NominalSampleRate", st) }
        return rate
    }

    /// Format wejścia IOProc: format tapa, ale z rzeczywistą częstotliwością urządzenia zbiorczego. Tap zgłasza zawsze
    /// 48 kHz, a zegar dostarczania idzie za urządzeniem (44,1 kHz na A2DP, 16 kHz w trybie rozmowy; faza 2.0.2, M1).
    /// Zgodne częstotliwości (urządzenia wbudowane) zwracają ten sam obiekt, więc działający tor się nie zmienia.
    static func captureFormat(tap: AVAudioFormat, deviceRate: Double) -> AVAudioFormat {
        guard deviceRate > 0, abs(deviceRate - tap.sampleRate) > 0.5 else { return tap }
        var d = tap.streamDescription.pointee
        d.mSampleRate = deviceRate
        return format(d) ?? tap
    }

    /// Ustawia nominalną częstotliwość tylko gdy jest inna; błąd nie przerywa nagrania (`captureFormat` i tak czyta rzeczywistą).
    static func setNominalSampleRate(of device: AudioObjectID, to rate: Double) {
        guard rate > 0, let current = try? nominalSampleRate(of: device), abs(current - rate) > 0.5 else { return }
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(rate)
        _ = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
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

    /// Urządzenia z strumieniem wejściowym (do menu wejścia w pigułce); bez naszego urządzenia zbiorczego tapa.
    public static func inputDevices() -> [InputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var streamsSize = UInt32(0)
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0,
                  let deviceUID = try? uid(of: id), let deviceName = try? name(of: id), !deviceName.hasPrefix("yascribe-tap")
            else { return nil }
            return InputDevice(uid: deviceUID, name: deviceName)
        }
    }

    public static func deviceID(forUID uid: String) throws -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        guard st == noErr, id != kAudioObjectUnknown else { throw AudioSourceError.deviceUnavailable("uid \(uid)") }
        return id
    }

    public static func defaultInputUID() -> String? { (try? defaultInputDevice()).flatMap { try? uid(of: $0) } }
    public static func defaultOutputUID() -> String? { (try? defaultOutputDevice()).flatMap { try? uid(of: $0) } }

    /// Słuchawki Bluetooth (klasyczne i LE) przełączają profil, gdy otwiera się ich mikrofon; urządzenie przewodowe nie.
    public static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyTransportType)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Bluetooth wejścia o danym UID (faktycznie nagrywane wejście, które po ręcznym wyborze nie jest już domyślne).
    public static func isBluetooth(uid: String) -> Bool { (try? deviceID(forUID: uid)).map(isBluetooth) ?? false }

    public static func defaultInputIsBluetooth() -> Bool { (try? defaultInputDevice()).map(isBluetooth) ?? false }

    /// Nazwa mikrofonu, który nagrywa `RawMicrophoneSource` (domyślne wejście systemu; wybór urządzenia: faza 2).
    public static func defaultInputName() -> String? {
        guard let d = try? defaultInputDevice() else { return nil }
        return try? name(of: d)
    }

    /// Nazwa wyjścia, z którego tap czyta dźwięk systemowy (domyślne wyjście systemu).
    public static func defaultOutputName() -> String? {
        guard let d = try? defaultOutputDevice() else { return nil }
        return try? name(of: d)
    }
}
