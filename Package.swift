// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CmdTab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CmdTab", targets: ["CmdTab"])
    ],
    targets: [
        .executableTarget(
            name: "CmdTab",
            path: "Sources/CmdTab",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
