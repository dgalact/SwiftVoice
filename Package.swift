// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwiftVoice",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SwiftVoice", targets: ["SwiftVoice"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftVoice",
            path: "Sources/SwiftVoice",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Translation")
            ]
        )
    ]
)
