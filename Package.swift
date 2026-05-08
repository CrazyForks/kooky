// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kooky",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [],
    targets: [
        // Thin executable: main.swift only. Everything else lives in KookyKit so
        // tests can `@testable import` it (SPM doesn't allow importing executables).
        .executableTarget(
            name: "Kooky",
            dependencies: ["KookyKit"],
            path: "Sources/Kooky"
        ),
        .target(
            name: "KookyKit",
            dependencies: [
                "GhosttyKit",
            ],
            path: "Sources/KookyKit",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                // libghostty bundles C++ deps (glslang, spirv-cross, imgui)
                // and uses Metal for rendering; link the system frameworks.
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                // Text Input Services — libghostty uses TIS to read the active
                // keyboard layout. Pulled in implicitly by SwiftTerm before;
                // now declared directly.
                .linkedFramework("Carbon"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            // Run scripts/setup-libghostty.sh to populate this; not committed.
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .testTarget(
            name: "KookyKitTests",
            dependencies: ["KookyKit"],
            path: "Tests/KookyKitTests"
        ),
    ]
)
