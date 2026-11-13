import Darwin
import Foundation
import os

/// Blokada jest poza usuwanym katalogiem modelu. Pliku nie kasujemy: inode musi pozostać wspólny dla procesów.
/// Właściciel trzyma token do końca operacji; zamknięcie deskryptora (także po awarii procesu) zwalnia flock.
/// `shared` (LOCK_SH): ładowanie Parakeeta, które tylko czyta, więc dowolnie wielu klientów naraz. Reszta (zapis, Cohere) LOCK_EX.
public final class ModelStoreLock: Sendable {
    private let descriptor: Int32
    private let path: String
    /// Ścieżki trzymane w tym procesie: odmowa mówi, czy konflikt jest w aplikacji, czy z innym procesem.
    private static let held = OSAllocatedUnfairLock(initialState: [String: Int]())

    init(url: URL, shared: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, (shared ? LOCK_SH : LOCK_EX) | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK {
                let here = Self.held.withLock { $0[url.path, default: 0] > 0 }
                throw ModelStoreError(message: here
                    ? "The on-device model is busy in another transcription, probe, dictation or download. Try again when it finishes."
                    : "Another Yascribe process is using this model.")
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
        path = url.path
        Self.held.withLock { $0[url.path, default: 0] += 1 }
    }

    deinit {
        close(descriptor)
        Self.held.withLock { $0[path, default: 1] -= 1 }
    }
}
