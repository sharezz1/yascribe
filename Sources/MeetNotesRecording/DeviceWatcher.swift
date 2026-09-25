import CoreAudio
import Foundation

/// Obserwator zmiany domyślnego urządzenia (wejścia albo wyjścia). Bez niego
/// przepięcie słuchawek urywa nagranie (W§1 🆕). Narada instaluje trzy takie.
final class DeviceWatcher: @unchecked Sendable {
    private var addr: AudioObjectPropertyAddress
    private let queue = DispatchQueue(label: "meetnotes.devicewatcher")
    private var block: AudioObjectPropertyListenerBlock?

    init(selector: AudioObjectPropertySelector) {
        addr = CoreAudioDevices.address(selector)
    }

    func start(_ onChange: @escaping @Sendable () -> Void) {
        let b: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        block = b
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, b)
    }

    func stop() {
        guard let b = block else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, b)
        block = nil
    }
}
