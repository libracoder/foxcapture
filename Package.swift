// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoxCapture",
    platforms: [.macOS("15.0")],
    targets: [
        .target(
            name: "FoxCaptureCore",
            path: "Sources"
        ),
        .executableTarget(
            name: "FoxCapture",
            dependencies: ["FoxCaptureCore"],
            path: "FoxCapture",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "FoxCaptureTests",
            dependencies: ["FoxCaptureCore"],
            path: "Tests"
        )
    ]
)
