// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeetNotes",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "MeetNotesApp", targets: ["MeetNotesApp"]),
        .executable(name: "meetnotes-cli", targets: ["meetnotes-cli"]),
    ],
    targets: [
        .target(name: "MeetNotesSessionFormat"),
        .target(name: "MeetNotesRecording", dependencies: ["MeetNotesSessionFormat"]),
        .target(name: "MeetNotesProviders"),
        .target(name: "MeetNotesTranscription", dependencies: ["MeetNotesSessionFormat", "MeetNotesProviders"]),
        .executableTarget(name: "meetnotes-cli", dependencies: ["MeetNotesRecording", "MeetNotesProviders", "MeetNotesTranscription"]),
        .executableTarget(name: "MeetNotesApp", dependencies: ["MeetNotesRecording", "MeetNotesProviders", "MeetNotesTranscription"]),
        .testTarget(name: "MeetNotesSessionFormatTests", dependencies: ["MeetNotesSessionFormat"]),
        .testTarget(name: "MeetNotesRecordingTests", dependencies: ["MeetNotesRecording"]),
        .testTarget(name: "MeetNotesProvidersTests", dependencies: ["MeetNotesProviders"], exclude: ["Fixtures"]),
        .testTarget(name: "MeetNotesTranscriptionTests", dependencies: ["MeetNotesTranscription", "MeetNotesRecording"], exclude: ["Fixtures"]),
    ]
)
