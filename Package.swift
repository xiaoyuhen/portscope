// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortScope",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PortScope", targets: ["PortScope"]),
        // Exposed as a library so a future CLI / widget can reuse the scanning
        // and classification engine without launching the UI.
        .library(name: "PortScopeKit", targets: ["PortScopeKit"]),
    ],
    targets: [
        .target(
            name: "PortScopeKit",
            path: "Sources/PortScopeKit"
        ),
        .executableTarget(
            name: "PortScope",
            dependencies: ["PortScopeKit"],
            path: "Sources/PortScope",
            resources: [.process("Resources")]
        ),
    ]
)
