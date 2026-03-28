// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIDevToolsKit",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ai-dev-tools-kit", targets: ["AIDevToolsKitCLI"]),
        .library(name: "AIDevToolsKitMac", targets: ["AIDevToolsKitMac"]),
        .library(name: "AIOutputSDK", targets: ["AIOutputSDK"]),
        .library(name: "AnthropicSDK", targets: ["AnthropicSDK"]),
        .library(name: "ChatFeature", targets: ["ChatFeature"]),
        .library(name: "ClaudeCLISDK", targets: ["ClaudeCLISDK"]),
        .library(name: "ClaudePythonSDK", targets: ["ClaudePythonSDK"]),
        .library(name: "CodexCLISDK", targets: ["CodexCLISDK"]),
        .library(name: "ConcurrencySDK", targets: ["ConcurrencySDK"]),
        .library(name: "DataPathsService", targets: ["DataPathsService"]),
        .library(name: "EnvironmentSDK", targets: ["EnvironmentSDK"]),
        .library(name: "EvalFeature", targets: ["EvalFeature"]),
        .library(name: "EvalSDK", targets: ["EvalSDK"]),
        .library(name: "EvalService", targets: ["EvalService"]),
        .library(name: "GitSDK", targets: ["GitSDK"]),
        .library(name: "LoggingSDK", targets: ["LoggingSDK"]),
        .library(name: "MarkdownPlannerFeature", targets: ["MarkdownPlannerFeature"]),
        .library(name: "MarkdownPlannerService", targets: ["MarkdownPlannerService"]),
        .library(name: "ProviderRegistryService", targets: ["ProviderRegistryService"]),
        .library(name: "RepositorySDK", targets: ["RepositorySDK"]),
        .library(name: "SkillBrowserFeature", targets: ["SkillBrowserFeature"]),
        .library(name: "SkillScannerSDK", targets: ["SkillScannerSDK"]),
        .library(name: "SkillService", targets: ["SkillService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
        .package(url: "https://github.com/gestrich/SwiftCLI", branch: "main"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.0.0"),
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic", from: "2.0.0"),
    ],
    targets: [
        // Apps Layer
        .executableTarget(
            name: "AIDevToolsKitCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "AIOutputSDK",
                "AnthropicSDK",
                "ArchitecturePlannerFeature",
                "ArchitecturePlannerService",
                "ChatFeature",
                "ClaudeCLISDK",
                "CodexCLISDK",
                "DataPathsService",
                "EnvironmentSDK",
                "EvalFeature",
                "EvalSDK",
                "EvalService",
                "LoggingSDK",
                "MarkdownPlannerFeature",
                "MarkdownPlannerService",
                "ProviderRegistryService",
                "RepositorySDK",
                "SkillBrowserFeature",
            ],
            path: "Sources/Apps/AIDevToolsKitCLI"
        ),
        .target(
            name: "AIDevToolsKitMac",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                "AIOutputSDK",
                "AnthropicSDK",
                "ArchitecturePlannerFeature",
                "ArchitecturePlannerService",
                "ChatFeature",
                "ClaudeCLISDK",
                "CodexCLISDK",
                "DataPathsService",
                "EvalFeature",
                "EvalSDK",
                "EvalService",
                "LoggingSDK",
                "MarkdownPlannerFeature",
                "MarkdownPlannerService",
                "ProviderRegistryService",
                "RepositorySDK",
                "SkillBrowserFeature",
                "SkillScannerSDK",
                "SkillService",
            ],
            path: "Sources/Apps/AIDevToolsKitMac"
        ),

        // Features Layer
        .target(
            name: "ArchitecturePlannerFeature",
            dependencies: [
                "AIOutputSDK",
                "ArchitecturePlannerService",
                "RepositorySDK",
            ],
            path: "Sources/Features/ArchitecturePlannerFeature"
        ),
        .target(
            name: "ChatFeature",
            dependencies: [
                "AIOutputSDK",
                "SkillScannerSDK",
            ],
            path: "Sources/Features/ChatFeature"
        ),
        .target(
            name: "EvalFeature",
            dependencies: [
                "AIOutputSDK",
                "EvalSDK",
                "EvalService",
                "ProviderRegistryService",
                "SkillScannerSDK",
            ],
            path: "Sources/Features/EvalFeature"
        ),
        .target(
            name: "MarkdownPlannerFeature",
            dependencies: [
                "AIOutputSDK",
                "GitSDK",
                "LoggingSDK",
                "MarkdownPlannerService",
                "RepositorySDK",
            ],
            path: "Sources/Features/MarkdownPlannerFeature"
        ),
        .target(
            name: "SkillBrowserFeature",
            dependencies: [
                "RepositorySDK",
                "SkillScannerSDK",
                "SkillService",
            ],
            path: "Sources/Features/SkillBrowserFeature"
        ),

        // Services Layer
        .target(
            name: "ArchitecturePlannerService",
            dependencies: [],
            path: "Sources/Services/ArchitecturePlannerService"
        ),
        .target(
            name: "DataPathsService",
            dependencies: [],
            path: "Sources/Services/DataPathsService"
        ),
        .target(
            name: "EvalService",
            dependencies: ["AIOutputSDK", "SkillScannerSDK"],
            path: "Sources/Services/EvalService"
        ),
        .target(
            name: "MarkdownPlannerService",
            dependencies: [],
            path: "Sources/Services/MarkdownPlannerService"
        ),
        .target(
            name: "ProviderRegistryService",
            dependencies: ["AIOutputSDK"],
            path: "Sources/Services/ProviderRegistryService"
        ),
        .target(
            name: "SkillService",
            dependencies: [
                "SkillScannerSDK",
            ],
            path: "Sources/Services/SkillService"
        ),

        // SDKs Layer
        .target(
            name: "AIOutputSDK",
            dependencies: ["SkillScannerSDK"],
            path: "Sources/SDKs/AIOutputSDK"
        ),
        .target(
            name: "AnthropicSDK",
            dependencies: [
                "AIOutputSDK",
                "SwiftAnthropic",
            ],
            path: "Sources/SDKs/AnthropicSDK"
        ),
        .target(
            name: "ClaudeCLISDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
                .product(name: "Logging", package: "swift-log"),
                "AIOutputSDK",
                "ConcurrencySDK",
                "SkillScannerSDK",
            ],
            path: "Sources/SDKs/ClaudeCLISDK"
        ),
        .target(
            name: "ClaudePythonSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
                "ConcurrencySDK",
                "EnvironmentSDK",
            ],
            path: "Sources/SDKs/ClaudePythonSDK"
        ),
        .target(
            name: "CodexCLISDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
                "AIOutputSDK",
                "SkillScannerSDK",
            ],
            path: "Sources/SDKs/CodexCLISDK"
        ),
        .target(
            name: "ConcurrencySDK",
            path: "Sources/SDKs/ConcurrencySDK"
        ),
        .target(
            name: "EnvironmentSDK",
            path: "Sources/SDKs/EnvironmentSDK"
        ),
        .target(
            name: "EvalSDK",
            dependencies: [
                "AIOutputSDK",
                "EvalService",
            ],
            path: "Sources/SDKs/EvalSDK"
        ),
        .target(
            name: "GitSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/SDKs/GitSDK"
        ),
        .target(
            name: "LoggingSDK",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SDKs/LoggingSDK"
        ),
        .target(
            name: "RepositorySDK",
            dependencies: [],
            path: "Sources/SDKs/RepositorySDK"
        ),
        .target(
            name: "SkillScannerSDK",
            dependencies: [],
            path: "Sources/SDKs/SkillScannerSDK"
        ),

        // Test Targets (alphabetical)
        .testTarget(
            name: "AIOutputSDKTests",
            dependencies: ["AIOutputSDK"],
            path: "Tests/SDKs/AIOutputSDKTests"
        ),
        .testTarget(
            name: "AIDevToolsKitCLITests",
            dependencies: ["AIDevToolsKitCLI"]
        ),
        .testTarget(
            name: "ArchitecturePlannerFeatureTests",
            dependencies: ["ArchitecturePlannerFeature", "ArchitecturePlannerService", "RepositorySDK"],
            path: "Tests/Features/ArchitecturePlannerFeatureTests"
        ),
        .testTarget(
            name: "ArchitecturePlannerServiceTests",
            dependencies: ["ArchitecturePlannerService"],
            path: "Tests/Services/ArchitecturePlannerServiceTests"
        ),
        .testTarget(
            name: "ChatFeatureTests",
            dependencies: ["AIOutputSDK", "ChatFeature", "SkillScannerSDK"],
            path: "Tests/Features/ChatFeatureTests"
        ),
        .testTarget(
            name: "ClaudeCLISDKTests",
            dependencies: ["ClaudeCLISDK"],
            path: "Tests/SDKs/ClaudeCLISDKTests"
        ),
        .testTarget(
            name: "ClaudePythonSDKTests",
            dependencies: ["ClaudePythonSDK"],
            path: "Tests/SDKs/ClaudePythonSDKTests"
        ),
        .testTarget(
            name: "DataPathsServiceTests",
            dependencies: ["DataPathsService"],
            path: "Tests/Services/DataPathsServiceTests"
        ),
        .testTarget(
            name: "EnvironmentSDKTests",
            dependencies: ["EnvironmentSDK"],
            path: "Tests/SDKs/EnvironmentSDKTests"
        ),
        .testTarget(
            name: "EvalFeatureTests",
            dependencies: ["AIOutputSDK", "EvalFeature", "EvalSDK", "EvalService", "ProviderRegistryService"],
            path: "Tests/Features/EvalFeatureTests"
        ),
        .testTarget(
            name: "EvalIntegrationTests",
            dependencies: ["AIOutputSDK", "ClaudeCLISDK", "CodexCLISDK", "EvalFeature", "EvalSDK", "EvalService"]
        ),
        .testTarget(
            name: "EvalSDKTests",
            dependencies: ["AIOutputSDK", "ClaudeCLISDK", "CodexCLISDK", "EvalSDK"],
            path: "Tests/SDKs/EvalSDKTests"
        ),
        .testTarget(
            name: "EvalServiceTests",
            dependencies: ["AIOutputSDK", "EvalService", "SkillScannerSDK"],
            path: "Tests/Services/EvalServiceTests"
        ),
        .testTarget(
            name: "GitSDKTests",
            dependencies: ["GitSDK"],
            path: "Tests/SDKs/GitSDKTests"
        ),
        .testTarget(
            name: "MarkdownPlannerFeatureTests",
            dependencies: ["GitSDK", "MarkdownPlannerFeature", "MarkdownPlannerService", "RepositorySDK"],
            path: "Tests/Features/MarkdownPlannerFeatureTests"
        ),
        .testTarget(
            name: "MarkdownPlannerServiceTests",
            dependencies: ["MarkdownPlannerService"],
            path: "Tests/Services/MarkdownPlannerServiceTests"
        ),
        .testTarget(
            name: "RepositorySDKTests",
            dependencies: ["RepositorySDK"],
            path: "Tests/SDKs/RepositorySDKTests"
        ),
        .testTarget(
            name: "SkillBrowserFeatureTests",
            dependencies: ["RepositorySDK", "SkillBrowserFeature", "SkillScannerSDK", "SkillService"],
            path: "Tests/Features/SkillBrowserFeatureTests"
        ),
        .testTarget(
            name: "SkillScannerSDKTests",
            dependencies: ["SkillScannerSDK"],
            path: "Tests/SDKs/SkillScannerSDKTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
