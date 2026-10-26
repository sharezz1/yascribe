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
        // Jedyny pin zewnętrzny (F20 S0 §2); FluidAudio importuje wyłącznie YascribeLocalASR.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .target(name: "YascribeSessionFormat"),
        .target(name: "YascribeRecording", dependencies: ["YascribeSessionFormat"]),
        .target(name: "YascribeProviders"),
        .target(name: "YascribeLocalASR", dependencies: ["YascribeProviders", "YascribeTranscription", .product(name: "FluidAudio", package: "FluidAudio")]),
        .target(name: "YascribeTranscription", dependencies: ["YascribeSessionFormat", "YascribeProviders"]),
        .target(name: "YascribeMeetings"),
        .target(name: "YascribeNotes", dependencies: ["YascribeSessionFormat", "YascribeProviders", "YascribeTranscription",
                                                       "YascribeMeetings"]),
        .executableTarget(name: "yascribe-cli", dependencies: ["YascribeRecording", "YascribeProviders", "YascribeTranscription", "YascribeLocalASR", "YascribeNotes"]),
        .executableTarget(name: "YascribeApp", dependencies: ["YascribeRecording", "YascribeProviders", "YascribeTranscription", "YascribeNotes",
                                                       "YascribeMeetings", "YascribeLocalASR"]),
        .testTarget(name: "YascribeSessionFormatTests", dependencies: ["YascribeSessionFormat"]),
        .testTarget(name: "YascribeRecordingTests", dependencies: ["YascribeRecording"]),
        .testTarget(name: "YascribeProvidersTests", dependencies: ["YascribeProviders"], exclude: ["Fixtures"]),
        .testTarget(name: "YascribeTranscriptionTests", dependencies: ["YascribeTranscription", "YascribeRecording"], exclude: ["Fixtures"]),
        .testTarget(name: "YascribeNotesTests", dependencies: ["YascribeNotes", "YascribeTranscription", "YascribeProviders",
                                                                "YascribeSessionFormat", "YascribeRecording", "YascribeMeetings"]),
        .testTarget(name: "YascribeLocalASRTests", dependencies: ["YascribeLocalASR", "YascribeProviders", "YascribeTranscription", .product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "YascribeMeetingsTests", dependencies: ["YascribeMeetings"]),
    ]
)
