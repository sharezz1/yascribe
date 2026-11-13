import Darwin
import Foundation

/// Blokada jest poza usuwanym katalogiem modelu. Pliku nie kasujemy: inode musi pozostać wspólny dla procesów.
/// Właściciel trzyma token do końca operacji; zamknięcie deskryptora (także po awarii procesu) zwalnia flock.
public final class ModelStoreLock: Sendable {
    private let descriptor: Int32

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK {
                throw ModelStoreError(message: "The on-device model is busy in another operation or process.")
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
    }

    deinit { close(descriptor) }
}
