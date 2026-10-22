import MeetNotesSessionFormat

/// Podpowiedź pod wierszem „System audio" w pigułce. Informacja, nie błąd: cisza w poczekalni to zwykły stan,
/// ale gdy mikrofon i wyjście to ta sama słuchawka Bluetooth, tryb rozmowy potrafi zablokować dźwięk systemowy (sesja 08f6).
public enum PillHint {
    public static func systemStalled(stalled: Bool, micUID: String, outputUID: String, isBluetooth: Bool) -> String? {
        guard stalled, isBluetooth, DeviceUID.same(micUID, outputUID) else { return nil }
        return "Headset in call mode may block system audio. Switch the microphone or the output."
    }
}
