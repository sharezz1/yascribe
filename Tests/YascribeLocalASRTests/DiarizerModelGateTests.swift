import Testing
@testable import YascribeLocalASR

@Test func diarizerGateUsesAReadyModelWithoutDownloading() throws {
    #expect(try DiarizerModelGate.decide(status: .ready, download: false) == .use)
    #expect(try DiarizerModelGate.decide(status: .ready, download: true) == .use)
}

@Test func diarizerGateRefusesAMissingOrIncompleteModelWithoutTheDownloadFlag() {
    for status in [DiarizerModelStatus.missing, .incomplete] {
        #expect(throws: DiarizerModelStoreError(message: "model missing, run with --download")) {
            try DiarizerModelGate.decide(status: status, download: false)
        }
    }
}

@Test func diarizerGateDownloadsOnlyWhenAskedTo() throws {
    for status in [DiarizerModelStatus.missing, .incomplete] {
        #expect(try DiarizerModelGate.decide(status: status, download: true) == .download)
    }
}
