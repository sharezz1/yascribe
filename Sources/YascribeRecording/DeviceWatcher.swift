import CoreAudio
import Foundation

/// Obserwator zmiany domyślnego urządzenia (wejścia albo wyjścia). Bez niego
/// przepięcie słuchawek urywa nagranie (W§1 🆕). inne narzędzie instaluje trzy takie.
final class DeviceWatcher: @unchecked Sendable {
    private var addr: AudioObjectPropertyAddress
    private let object: AudioObjectID
    private let queue = DispatchQueue(label: "yascribe.devicewatcher")
    private var block: AudioObjectPropertyListenerBlock?

    init(selector: AudioObjectPropertySelector) {
        addr = CoreAudioDevices.address(selector)
        object = AudioObjectID(kAudioObjectSystemObject)
    }

    /// Nasłuch właściwości konkretnego urządzenia (np. nominalnej częstotliwości urządzenia zbiorczego).
    init(object: AudioObjectID, selector: AudioObjectPropertySelector) {
        addr = CoreAudioDevices.address(selector)
        self.object = object
    }

    func start(_ onChange: @escaping @Sendable () -> Void) {
        let b: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        block = b
        AudioObjectAddPropertyListenerBlock(object, &addr, queue, b)
    }

    func stop() {
        guard let b = block else { return }
        AudioObjectRemovePropertyListenerBlock(object, &addr, queue, b)
        block = nil
    }
}
