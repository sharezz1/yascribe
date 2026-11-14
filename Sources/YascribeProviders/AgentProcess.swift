import Darwin
import Foundation

/// Proces agenta CLI we własnej grupie procesów (TASK-86, spec §4.2). `Foundation.Process` nie ustawia grupy, a potomek, który
/// przeżyje rodzica i trzyma stdout, zawiesiłby czytanie: dlatego `posix_spawn` + `POSIX_SPAWN_SETPGROUP` i sygnały do całej grupy.
enum AgentProcess {
    struct Output: Sendable {
        var stdout: Data
        var stderr: Data
        var status: Int32
        /// `stopEarly` zwrócił `true` dla linii stdout i grupa została zakończona.
        var stoppedEarly = false
        /// Minął `limit` i grupa została zakończona.
        var timedOut = false
        var stderrText: String { String(String(decoding: stderr, as: UTF8.self).suffix(600)) }
    }

    /// Czas między SIGTERM a SIGKILL grupy.
    static let killGrace: Double = 2

    /// Uruchamia `executable` z `arguments` (bez powłoki), zapisuje `input` na stdin i czyta stdout/stderr równolegle do EOF.
    /// Anulowanie zadania: SIGTERM do grupy, po `killGrace` SIGKILL do grupy, potem `CancellationError`. Anulowanie przed startem
    /// nie uruchamia procesu. `limit` działa tak samo, ale kończy się wynikiem z `timedOut`.
    static func run(executable: URL, arguments: [String], environment: [String: String], directory: URL, input: Data,
                    limit: Double? = nil, stopEarly: @escaping @Sendable (String) -> Bool = { _ in false }) async throws -> Output {
        let job = Job()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let pipes = try Pipes()
            let pid = try spawn(executable: executable, arguments: arguments, environment: environment, directory: directory, pipes: pipes)
            job.started(pid) // anulowanie, które przyszło w trakcie startu, zabija grupę tutaj
            pipes.closeChildEnds()
            let timer = limit.map { seconds in
                Task.detached { try? await Task.sleep(for: .seconds(seconds)); job.stop(.timedOut) }
            }
            defer { timer?.cancel() }
            async let written: Void = background { writeAll(input, to: pipes.stdinWrite) }
            async let out = background { readAll(pipes.stdoutRead) { line in if stopEarly(line) { job.stop(.early) } } }
            async let err = background { readAll(pipes.stderrRead) { _ in } }
            async let status = background { waitFor(pid) }
            let exit = await status
            job.parentExited()
            let (o, e) = await (out, err)
            _ = await written
            job.finished()
            if job.reason == .cancelled { throw CancellationError() }
            return Output(stdout: o, stderr: e, status: exit, stoppedEarly: job.reason == .early, timedOut: job.reason == .timedOut)
        } onCancel: {
            job.stop(.cancelled)
        }
    }

    // MARK: stan

    enum StopReason { case cancelled, timedOut, early }

    /// Stan start/stop/koniec pod zamkiem: handler anulowania jest synchroniczny i może przyjść przed startem, w trakcie i po.
    final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t = 0
        private var stopReason: StopReason?
        private var done = false

        var reason: StopReason? { lock.withLock { stopReason } }

        func started(_ p: pid_t) {
            let pending = lock.withLock { () -> Bool in pid = p; return stopReason != nil }
            if pending { signalGroup() }
        }

        /// Pierwszy powód wygrywa. SIGTERM do grupy teraz, SIGKILL po `killGrace` — bez względu na to, czy rodzic jeszcze żyje.
        func stop(_ r: StopReason) {
            let go = lock.withLock { () -> Bool in
                guard stopReason == nil, !done else { return false }
                stopReason = r
                return pid != 0
            }
            if go { signalGroup() }
        }

        /// Rodzic zakończył się sam: jeśli w grupie został ktoś, kto trzyma potoki, po `killGrace` dostaje SIGKILL.
        func parentExited() {
            let p = lock.withLock { pid }
            DispatchQueue.global().asyncAfter(deadline: .now() + AgentProcess.killGrace) { [self] in
                if !lock.withLock({ done }) { kill(-p, SIGKILL) }
            }
        }

        func finished() { lock.withLock { done = true } }

        private func signalGroup() {
            let p = lock.withLock { pid }
            guard p > 0 else { return }
            kill(-p, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + AgentProcess.killGrace) { [self] in
                if !lock.withLock({ done }) { kill(-p, SIGKILL) }
            }
        }
    }

    // MARK: posix

    final class Pipes: @unchecked Sendable {
        let stdinRead: Int32, stdinWrite: Int32, stdoutRead: Int32, stdoutWrite: Int32, stderrRead: Int32, stderrWrite: Int32

        init() throws {
            var a: [Int32] = [0, 0], b: [Int32] = [0, 0], c: [Int32] = [0, 0]
            guard pipe(&a) == 0, pipe(&b) == 0, pipe(&c) == 0 else { throw ProviderError.agentFailed("Couldn't create pipes (errno \(errno)).") }
            (stdinRead, stdinWrite, stdoutRead, stdoutWrite, stderrRead, stderrWrite) = (a[0], a[1], b[0], b[1], c[0], c[1])
            // Zapis do zamkniętego stdin nie może zabić aplikacji sygnałem SIGPIPE.
            _ = fcntl(stdinWrite, F_SETNOSIGPIPE, 1)
        }

        func closeChildEnds() { close(stdinRead); close(stdoutWrite); close(stderrWrite) }
    }

    static func spawn(executable: URL, arguments: [String], environment: [String: String], directory: URL, pipes: Pipes) throws -> pid_t {
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Własna grupa (pgid = pid), tylko jawnie przekazane deskryptory, domyślne sygnały i pusta maska.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attr, 0)
        var defaults = sigset_t(), empty = sigset_t()
        sigfillset(&defaults)
        sigemptyset(&empty)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setsigmask(&attr, &empty)

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, pipes.stdinRead, 0)
        posix_spawn_file_actions_adddup2(&actions, pipes.stdoutWrite, 1)
        posix_spawn_file_actions_adddup2(&actions, pipes.stderrWrite, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)

        let argv = [executable.path] + arguments
        let envp = environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let rc = withCStrings(argv) { a in withCStrings(envp) { e in posix_spawn(&pid, executable.path, &actions, &attr, a, e) } }
        guard rc == 0 else {
            close(pipes.stdinRead); close(pipes.stdoutWrite); close(pipes.stderrWrite)
            close(pipes.stdinWrite); close(pipes.stdoutRead); close(pipes.stderrRead)
            throw ProviderError.agentFailed("Couldn't start \(executable.path) (\(String(cString: strerror(rc)))).")
        }
        return pid
    }

    private static func withCStrings<R>(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var ptrs: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) } + [nil]
        defer { ptrs.forEach { free($0) } }
        return ptrs.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }

    /// Blokujące wywołanie na osobnym wątku (czytanie potoku, `waitpid`), żeby nie zajmować puli współbieżności.
    private static func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { c in Thread.detachNewThread { c.resume(returning: work()) } }
    }

    private static func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n < 0 { if errno == EINTR { continue }; break } // EPIPE: proces nie czyta stdin — nic do zrobienia
                off += n
            }
        }
        close(fd)
    }

    /// Czyta do EOF; `onLine` dostaje każdą pełną linię (strumień JSONL Codex).
    private static func readAll(_ fd: Int32, onLine: (String) -> Void) -> Data {
        var all = Data(), pending = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n < 0 { if errno == EINTR { continue }; break }
            if n == 0 { break }
            all.append(buf, count: n)
            pending.append(buf, count: n)
            while let nl = pending.firstIndex(of: 0x0A) {
                onLine(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...nl)
            }
        }
        close(fd)
        return all
    }

    /// Kod wyjścia; zabity sygnałem = 128 + numer sygnału (jak w powłoce).
    private static func waitFor(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 { if errno != EINTR { return -1 } }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }
}
