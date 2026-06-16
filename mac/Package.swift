// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FineClipboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FineClipboard",
            path: "Sources/FineClipboard",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("CryptoKit"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
