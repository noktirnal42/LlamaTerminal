// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LlamaTerminal",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "LlamaTerminal",
            targets: ["App"]
        ),
        .library(
            name: "TerminalCore",
            targets: ["TerminalCore"]
        ),
        .library(
            name: "AIIntegration",
            targets: ["AIIntegration"]
        ),
        .library(
            name: "SharedModels",
            targets: ["SharedModels"]
        ),
        .library(
            name: "UIComponents",
            targets: ["UIComponents"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", branch: "main"),
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),
        .package(url: "https://github.com/apple/swift-markdown", from: "0.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                "TerminalCore",
                "AIIntegration",
                "UIComponents",
                "SharedModels",
            ],
            path: "Sources/App",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("RELEASE", .when(configuration: .release)),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .target(
            name: "TerminalCore",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/TerminalCore",
            swiftSettings: [
                .define("RELEASE", .when(configuration: .release)),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .target(
            name: "AIIntegration",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/AIIntegration",
            swiftSettings: [
                .define("RELEASE", .when(configuration: .release)),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .target(
            name: "SharedModels",
            dependencies: [
                // No dependencies to avoid circular references
            ],
            path: "Sources/SharedModels",
            swiftSettings: [
                .define("RELEASE", .when(configuration: .release)),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .target(
            name: "UIComponents",
            dependencies: [
                "TerminalCore",
                "AIIntegration",
                "SharedModels",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/UIComponents",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("RELEASE", .when(configuration: .release)),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        // Tests
        .testTarget(
            name: "TerminalCoreTests",
            dependencies: ["TerminalCore"],
            path: "Tests/TerminalCoreTests",
            swiftSettings: [
                .unsafeFlags(["-profile-coverage-mapping", "-profile-generate"])
            ]
        ),
        .testTarget(
            name: "AIIntegrationTests",
            dependencies: ["AIIntegration"],
            path: "Tests/AIIntegrationTests"
        ),
        .testTarget(
            name: "UIComponentsTests",
            dependencies: ["UIComponents"],
            path: "Tests/UIComponentsTests"
        ),
    ]
)
