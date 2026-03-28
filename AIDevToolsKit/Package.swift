// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIDevToolsKit",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ai-dev-tools-kit", targets: ["AIDevToolsKitCLI"]),
        .library(name: "AIDevToolsKitMac", targets: ["AIDevToolsKitMac"]),
        .library(name: "ArchitecturePlannerFeature", targets: ["ArchitecturePlannerFeature"]),
        .library(name: "ArchitecturePlannerService", targets: ["ArchitecturePlannerService"]),
        .library(name: "AnthropicChatFeature", targets: ["AnthropicChatFeature"]),
        .library(name: "AIOutputSDK", targets: ["AIOutputSDK"]),
        .library(name: "AnthropicChatService", targets: ["AnthropicChatService"]),
        .library(name: "AnthropicSDK", targets: ["AnthropicSDK"]),
        .library(name: "ChatService", targets: ["ChatService"]),
        .library(name: "ClaudeCodeChatFeature", targets: ["ClaudeCodeChatFeature"]),
        .library(name: "ClaudeCodeChatService", targets: ["ClaudeCodeChatService"]),
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
        .library(name: "PlanRunnerFeature", targets: ["PlanRunnerFeature"]),
        .library(name: "PlanRunnerService", targets: ["PlanRunnerService"]),
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
                "AnthropicChatFeature",
                "AnthropicSDK",
                "ArchitecturePlannerFeature",
                "ArchitecturePlannerService",
                "ClaudeCodeChatFeature",
                "ClaudeCodeChatService",
                "ClaudeCLISDK",
                "CodexCLISDK",
                "DataPathsService",
                "EvalFeature",
                "EvalSDK",
                "EvalService",
                "LoggingSDK",
                "PlanRunnerFeature",
                "PlanRunnerService",
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
                "AnthropicChatService",
                "AnthropicSDK",
                "ArchitecturePlannerFeature",
                "ArchitecturePlannerService",
                "ClaudeCodeChatService",
                "ClaudeCLISDK",
                "CodexCLISDK",
                "DataPathsService",
                "EvalFeature",
                "EvalSDK",
                "EvalService",
                "LoggingSDK",
                "PlanRunnerFeature",
                "PlanRunnerService",
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
            name: "AnthropicChatFeature",
            dependencies: [
                "AIOutputSDK",
            ],
            path: "Sources/Features/AnthropicChatFeature"
        ),
        .target(
            name: "ClaudeCodeChatFeature",
            dependencies: [
                "AIOutputSDK",
                "ClaudeCodeChatService",
                "SkillScannerSDK",
            ],
            path: "Sources/Features/ClaudeCodeChatFeature"
        ),
        .target(
            name: "EvalFeature",
            dependencies: [
                "EvalSDK",
                "EvalService",
                "ProviderRegistryService",
                "SkillScannerSDK",
            ],
            path: "Sources/Features/EvalFeature"
        ),
        .target(
            name: "PlanRunnerFeature",
            dependencies: [
                "AIOutputSDK",
                "GitSDK",
                "LoggingSDK",
                "PlanRunnerService",
                "RepositorySDK",
            ],
            path: "Sources/Features/PlanRunnerFeature"
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
            name: "AnthropicChatService",
            dependencies: [
                "AIOutputSDK",
            ],
            path: "Sources/Services/AnthropicChatService"
        ),
        .target(
            name: "ArchitecturePlannerService",
            dependencies: [],
            path: "Sources/Services/ArchitecturePlannerService"
        ),
        .target(
            name: "ChatService",
            dependencies: [
                "AIOutputSDK",
            ],
            path: "Sources/Services/ChatService"
        ),
        .target(
            name: "ClaudeCodeChatService",
            dependencies: [
                "AIOutputSDK",
            ],
            path: "Sources/Services/ClaudeCodeChatService"
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
            name: "PlanRunnerService",
            dependencies: [],
            path: "Sources/Services/PlanRunnerService"
        ),
        .target(
            name: "ProviderRegistryService",
            dependencies: ["AIOutputSDK", "EvalSDK", "EvalService"],
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
            dependencies: [],
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
                .product(name: "CLISDK", package: "SwiftCLI"),
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
            name: "ChatServiceTests",
            dependencies: ["AIOutputSDK", "ChatService"],
            path: "Tests/Services/ChatServiceTests"
        ),
        .testTarget(
            name: "ClaudeCodeChatFeatureTests",
            dependencies: ["ClaudeCodeChatFeature", "SkillScannerSDK"],
            path: "Tests/Features/ClaudeCodeChatFeatureTests"
        ),
        .testTarget(
            name: "ClaudeCodeChatServiceTests",
            dependencies: ["ClaudeCodeChatService"],
            path: "Tests/Services/ClaudeCodeChatServiceTests"
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
            dependencies: ["ClaudeCLISDK", "CodexCLISDK", "EvalFeature", "EvalSDK", "EvalService"]
        ),
        .testTarget(
            name: "EvalSDKTests",
            dependencies: ["AIOutputSDK", "EvalSDK"],
            path: "Tests/SDKs/EvalSDKTests"
        ),
        .testTarget(
            name: "EvalServiceTests",
            dependencies: ["EvalService", "SkillScannerSDK"],
            path: "Tests/Services/EvalServiceTests"
        ),
        .testTarget(
            name: "GitSDKTests",
            dependencies: ["GitSDK"],
            path: "Tests/SDKs/GitSDKTests"
        ),
        .testTarget(
            name: "PlanRunnerFeatureTests",
            dependencies: ["GitSDK", "PlanRunnerFeature", "PlanRunnerService", "RepositorySDK"],
            path: "Tests/Features/PlanRunnerFeatureTests"
        ),
        .testTarget(
            name: "PlanRunnerServiceTests",
            dependencies: ["PlanRunnerService"],
            path: "Tests/Services/PlanRunnerServiceTests"
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
