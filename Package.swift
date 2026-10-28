// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Yascribe",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "YascribeApp", targets: ["YascribeApp"]),
        .executable(name: "yascribe-cli", targets: ["yascribe-cli"]),
    ],
    dependencies: [
        // Pierwszy pin zewnętrzny (F20 S0 §2); FluidAudio importuje wyłącznie YascribeLocalASR.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
        // Drugi pin zewnętrzny; Sparkle importuje wyłącznie YascribeUpdates (S0 Yascribe, 2026-10-26).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
    ],
    targets: [
        .target(name: "CSpeexDSP", exclude: ["NOTICE.md"], sources: ["AEC.c", "vendor/mdf.c", "vendor/preprocess.c", "vendor/fftwrap.c", "vendor/filterbank.c", "vendor/smallft.c"],
                publicHeadersPath: "include", cSettings: [.define("HAVE_CONFIG_H"), .headerSearchPath("vendor")]),
        .target(name: "YascribeSessionFormat"),
        .target(name: "YascribeRecording", dependencies: ["YascribeSessionFormat"]),
        .target(name: "YascribeProviders"),
        .target(name: "YascribeLocalASR", dependencies: ["YascribeProviders", "YascribeTranscription", .product(name: "FluidAudio", package: "FluidAudio")]),
        .target(name: "YascribeTranscription", dependencies: ["YascribeSessionFormat", "YascribeProviders", "CSpeexDSP"]),
        .target(name: "YascribeMeetings"),
        .target(name: "YascribeUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .target(name: "YascribeNotes", dependencies: ["YascribeSessionFormat", "YascribeProviders", "YascribeTranscription",
                                                       "YascribeMeetings"]),
        .executableTarget(name: "yascribe-cli", dependencies: ["YascribeRecording", "YascribeProviders", "YascribeTranscription", "YascribeLocalASR", "YascribeNotes"]),
        .executableTarget(name: "YascribeApp", dependencies: ["YascribeRecording", "YascribeProviders", "YascribeTranscription", "YascribeNotes",
                                                       "YascribeMeetings", "YascribeLocalASR", "YascribeUpdates"]),
        .testTarget(name: "YascribeSessionFormatTests", dependencies: ["YascribeSessionFormat"]),
        .testTarget(name: "YascribeRecordingTests", dependencies: ["YascribeRecording"]),
        .testTarget(name: "YascribeProvidersTests", dependencies: ["YascribeProviders"], exclude: ["Fixtures"]),
        .testTarget(name: "YascribeTranscriptionTests", dependencies: ["YascribeTranscription", "YascribeRecording"], exclude: ["Fixtures"]),
        .testTarget(name: "YascribeNotesTests", dependencies: ["YascribeNotes", "YascribeTranscription", "YascribeProviders",
                                                                "YascribeSessionFormat", "YascribeRecording", "YascribeMeetings"]),
        .testTarget(name: "YascribeLocalASRTests", dependencies: ["YascribeLocalASR", "YascribeProviders", "YascribeTranscription", .product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "YascribeMeetingsTests", dependencies: ["YascribeMeetings"]),
        .testTarget(name: "YascribeUpdatesTests", dependencies: ["YascribeUpdates"]),
    ]
)
