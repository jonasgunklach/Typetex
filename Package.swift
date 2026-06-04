// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Typetex",
    platforms: [.macOS(.v14)],
    targets: [
        // Single executable: all rendering sources + main.swift in one module
        // (no cross-module access issues, no `public` modifiers needed)
        .executableTarget(
            name: "generate-pdfs",
            path: ".",
            exclude: [
                // SwiftUI app sources – not needed and pull in extra dependencies
                "Typetex/Utilities/LaTeXRenderer.swift",
                // Everything else that isn't utility or generator source
                "Typetex/App",
                "Typetex/Models",
                "Typetex/Views",
                "Typetex/ViewModels",
                "Typetex/Assets.xcassets",
                "Typetex/Info.plist",
                "Typetex/Typetex.entitlements",
                "Typetex.xcodeproj",
                "TectonicFFI.xcframework",
                "testchi",
                "templates",
                "README.md",
            ],
            sources: [
                "Typetex/Utilities",
                "Sources/generate-pdfs",
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-access-control"])
            ]
        ),
    ]
)
