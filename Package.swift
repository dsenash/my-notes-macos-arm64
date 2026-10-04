// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MyNotes",
            path: "Sources/MyNotes",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
