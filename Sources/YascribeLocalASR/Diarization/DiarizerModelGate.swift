/// Decyzja CLI `diarize`: model pobiera wyłącznie użytkownik, jawną flagą (spec §4.2).
public enum DiarizerModelGate {
    public enum Decision: Equatable, Sendable { case use, download }

    public static func decide(status: DiarizerModelStatus, download: Bool) throws -> Decision {
        if status == .ready { return .use }
        guard download else { throw DiarizerModelStoreError(message: "model missing, run with --download") }
        return .download
    }
}
