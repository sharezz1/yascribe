// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeetNotes",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "MeetNotesApp", targets: ["MeetNotesApp"]),
        .executable(name: "meetnotes-cli", targets: ["meetnotes-cli"]),
    ],
    dependencies: [
        // Jedyny pin zewnętrzny (F20 S0 §2); FluidAudio importuje wyłącznie MeetNotesLocalASR.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .target(name: "MeetNotesSessionFormat"),
        .target(name: "MeetNotesRecording", dependencies: ["MeetNotesSessionFormat"]),
        .target(name: "MeetNotesProviders"),
        .target(name: "MeetNotesLocalASR", dependencies: ["MeetNotesProviders", "MeetNotesTranscription", .product(name: "FluidAudio", package: "FluidAudio")]),
        .target(name: "MeetNotesTranscription", dependencies: ["MeetNotesSessionFormat", "MeetNotesProviders"]),
        .target(name: "MeetNotesMeetings"),
        .target(name: "MeetNotesNotes", dependencies: ["MeetNotesSessionFormat", "MeetNotesProviders", "MeetNotesTranscription",
                                                       "MeetNotesMeetings"]),
        .executableTarget(name: "meetnotes-cli", dependencies: ["MeetNotesRecording", "MeetNotesProviders", "MeetNotesTranscription", "MeetNotesLocalASR"]),
        .executableTarget(name: "MeetNotesApp", dependencies: ["MeetNotesRecording", "MeetNotesProviders", "MeetNotesTranscription", "MeetNotesNotes",
                                                       "MeetNotesMeetings", "MeetNotesLocalASR"]),
        .testTarget(name: "MeetNotesSessionFormatTests", dependencies: ["MeetNotesSessionFormat"]),
        .testTarget(name: "MeetNotesRecordingTests", dependencies: ["MeetNotesRecording"]),
        .testTarget(name: "MeetNotesProvidersTests", dependencies: ["MeetNotesProviders"], exclude: ["Fixtures"]),
        .testTarget(name: "MeetNotesTranscriptionTests", dependencies: ["MeetNotesTranscription", "MeetNotesRecording"], exclude: ["Fixtures"]),
        .testTarget(name: "MeetNotesNotesTests", dependencies: ["MeetNotesNotes", "MeetNotesTranscription", "MeetNotesProviders",
                                                                "MeetNotesSessionFormat", "MeetNotesRecording", "MeetNotesMeetings"]),
        .testTarget(name: "MeetNotesLocalASRTests", dependencies: ["MeetNotesLocalASR", "MeetNotesProviders", "MeetNotesTranscription", .product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "MeetNotesMeetingsTests", dependencies: ["MeetNotesMeetings"]),
    ]
)
