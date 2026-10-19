// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AltPlus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AltPlus",
            path: "Sources/AltPlus",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ]
)
