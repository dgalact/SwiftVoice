// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Jarvis",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Jarvis", targets: ["Jarvis"])
    ],
    targets: [
        .executableTarget(
            name: "Jarvis",
            path: "Sources/Jarvis",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
