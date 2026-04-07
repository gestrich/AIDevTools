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
        .library(name: "AppIPCSDK", targets: ["AppIPCSDK"]),
        .library(name: "ClaudeAgentSDK", targets: ["ClaudeAgentSDK"]),
        .library(name: "ChatFeature", targets: ["ChatFeature"]),
        .library(name: "ChatService", targets: ["ChatService"]),
        .library(name: "ClaudeChainCLI", targets: ["ClaudeChainCLI"]),
        .library(name: "ClaudeChainService", targets: ["ClaudeChainService"]),
        .library(name: "ClaudeChainSDK", targets: ["ClaudeChainSDK"]),
        .library(name: "ClaudeChainFeature", targets: ["ClaudeChainFeature"]),
        .library(name: "ClaudeCLISDK", targets: ["ClaudeCLISDK"]),
        .library(name: "ClaudePythonSDK", targets: ["ClaudePythonSDK"]),
        .library(name: "CodexCLISDK", targets: ["CodexCLISDK"]),
        .library(name: "ConcurrencySDK", targets: ["ConcurrencySDK"]),
        .library(name: "CredentialFeature", targets: ["CredentialFeature"]),
        .library(name: "CredentialService", targets: ["CredentialService"]),
        .library(name: "DataPathsService", targets: ["DataPathsService"]),
        .library(name: "EnvironmentSDK", targets: ["EnvironmentSDK"]),
        .library(name: "EvalFeature", targets: ["EvalFeature"]),
        .library(name: "EvalSDK", targets: ["EvalSDK"]),
        .library(name: "EvalService", targets: ["EvalService"]),
        .library(name: "GitHubService", targets: ["GitHubService"]),
        .library(name: "GitSDK", targets: ["GitSDK"]),
        .library(name: "KeychainSDK", targets: ["KeychainSDK"]),
        .library(name: "LoggingSDK", targets: ["LoggingSDK"]),
        .library(name: "SweepFeature", targets: ["SweepFeature"]),
        .library(name: "SweepService", targets: ["SweepService"]),
        .library(name: "PlanFeature", targets: ["PlanFeature"]),
        .library(name: "PlanService", targets: ["PlanService"]),
        .library(name: "OctokitSDK", targets: ["OctokitSDK"]),
        .library(name: "PipelineFeature", targets: ["PipelineFeature"]),
        .library(name: "PipelineSDK", targets: ["PipelineSDK"]),
        .library(name: "PipelineService", targets: ["PipelineService"]),
        .library(name: "PRRadarCLIService", targets: ["PRRadarCLIService"]),
        .library(name: "PRRadarConfigService", targets: ["PRRadarConfigService"]),
        .library(name: "PRRadarModelsService", targets: ["PRRadarModelsService"]),
        .library(name: "PRReviewFeature", targets: ["PRReviewFeature"]),
        .library(name: "ProviderRegistryService", targets: ["ProviderRegistryService"]),
        .library(name: "RepositorySDK", targets: ["RepositorySDK"]),
        .library(name: "SettingsService", targets: ["SettingsService"]),
        .library(name: "SkillBrowserFeature", targets: ["SkillBrowserFeature"]),
        .library(name: "SkillScannerSDK", targets: ["SkillScannerSDK"]),
        .library(name: "SkillService", targets: ["SkillService"]),
        .library(name: "UseCaseSDK", targets: ["UseCaseSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
        .package(url: "https://github.com/gestrich/SwiftCLI", branch: "main"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.0.0"),
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic", from: "2.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/nerdishbynature/octokit.swift", from: "0.14.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
    ],
    targets: [
        // Apps Layer
        .executableTarget(
            name: "AIDevToolsKitCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "AIOutputSDK",
                "AnthropicSDK",
                "AppIPCSDK",
                "ArchitecturePlannerFeature",
                "ArchitecturePlannerService",
                "ChatFeature",
                "ClaudeChainCLI",
                "ClaudeChainFeature",
                "ClaudeChainService",
                "ClaudeCLISDK",
                "CodexCLISDK",
                "CredentialFeature",
                "CredentialService",
                "DataPathsService",
                "EnvironmentSDK",
                "EvalFeature",
                "EvalSDK",
                "EvalService",
                "GitHubService",
                "LoggingSDK",
                "PlanFeature",
                "PlanService",
                .product(name: "MCP", package: "swift-sdk"),
                "PRRadarCLIService",
                "PRRadarConfigService",
                "PRRadarModelsService",
                "PRReviewFeature",
                "ProviderRegistryService",
                "RepositorySDK",
                "SettingsService",
                "SkillBrowserFeature",
                "SweepFeature",
            ],
            path: "Sources/Apps/AIDevToolsKitCLI"
        ),
        .target(
            name: "AIDevToolsKitMac",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                "AIOutputSDK",
                "AnthropicSDK",
                "AppIPCSDK",
                "ArchitecturePlannerFeature",
                "ArchitecturePlannerService",
                "ChatFeature",
                "ClaudeChainFeature",
                "ClaudeChainService",
                "ClaudeCLISDK",
                "CodexCLISDK",
                "CredentialFeature",
                "CredentialService",
                "DataPathsService",
                "EvalFeature",
                "EvalSDK",
                "EvalService",
                "GitHubService",
                "GitSDK",
                "LoggingSDK",
                "LogsFeature",
                "PlanFeature",
                "PlanService",
                "OctokitSDK",
                "PipelineFeature",
                "PipelineSDK",
                "PipelineService",
                "PRRadarCLIService",
                "PRRadarConfigService",
                "PRRadarModelsService",
                "PRReviewFeature",
                "ProviderRegistryService",
                "RepositorySDK",
                "SettingsService",
                "SkillBrowserFeature",
                "SkillScannerSDK",
                "SkillService",
                "SweepFeature",
            ],
            path: "Sources/Apps/AIDevToolsKitMac"
        ),

        // Features Layer
        .target(
            name: "ArchitecturePlannerFeature",
            dependencies: [
                "AIOutputSDK",
                "ArchitecturePlannerService",
                "DataPathsService",
                "RepositorySDK",
                "UseCaseSDK",
            ],
            path: "Sources/Features/ArchitecturePlannerFeature"
        ),
        .target(
            name: "ChatFeature",
            dependencies: [
                "AIOutputSDK",
                "SkillScannerSDK",
                "UseCaseSDK",
            ],
            path: "Sources/Features/ChatFeature"
        ),
        .target(
            name: "CredentialFeature",
            dependencies: [
                "CredentialService",
                "UseCaseSDK",
            ],
            path: "Sources/Features/CredentialFeature"
        ),
        .target(
            name: "EvalFeature",
            dependencies: [
                "AIOutputSDK",
                "EvalSDK",
                "EvalService",
                "ProviderRegistryService",
                "SkillScannerSDK",
                "UseCaseSDK",
            ],
            path: "Sources/Features/EvalFeature"
        ),
        .target(
            name: "LogsFeature",
            dependencies: [
                "LoggingSDK",
                "UseCaseSDK",
            ],
            path: "Sources/Features/LogsFeature"
        ),
        .target(
            name: "PlanFeature",
            dependencies: [
                "AIOutputSDK",
                "CredentialService",
                "GitSDK",
                "LoggingSDK",
                "PlanService",
                "PipelineSDK",
                "RepositorySDK",
                "UseCaseSDK",
            ],
            path: "Sources/Features/PlanFeature"
        ),
        .target(
            name: "PipelineFeature",
            dependencies: [
                "PipelineSDK",
                "PipelineService",
                "UseCaseSDK",
            ],
            path: "Sources/Features/PipelineFeature"
        ),
        .target(
            name: "PRReviewFeature",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
                "ClaudeAgentSDK",
                "EnvironmentSDK",
                "GitHubService",
                "LoggingSDK",
                "PRRadarCLIService",
                "PRRadarConfigService",
                "PRRadarModelsService",
                "RepositorySDK",
                "UseCaseSDK",
            ],
            path: "Sources/Features/PRReviewFeature"
        ),
        .target(
            name: "SkillBrowserFeature",
            dependencies: [
                "RepositorySDK",
                "SkillScannerSDK",
                "UseCaseSDK",
            ],
            path: "Sources/Features/SkillBrowserFeature"
        ),
        .target(
            name: "SweepFeature",
            dependencies: [
                "AIOutputSDK",
                "ClaudeChainService",
                .product(name: "CLISDK", package: "SwiftCLI"),
                "GitHubService",
                "GitSDK",
                .product(name: "Logging", package: "swift-log"),
                "PipelineSDK",
                "PipelineService",
                "PRRadarCLIService",
                "PRRadarModelsService",
                "UseCaseSDK",
            ],
            path: "Sources/Features/SweepFeature"
        ),

        // Services Layer
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
            name: "CredentialService",
            dependencies: [
                "EnvironmentSDK",
                "KeychainSDK",
            ],
            path: "Sources/Services/CredentialService"
        ),
        .target(
            name: "DataPathsService",
            dependencies: [
                "UseCaseSDK",
            ],
            path: "Sources/Services/DataPathsService"
        ),
        .target(
            name: "EvalService",
            dependencies: ["AIOutputSDK", "RepositorySDK", "SkillScannerSDK"],
            path: "Sources/Services/EvalService"
        ),
        .target(
            name: "GitHubService",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "OctokitSDK",
                "PRRadarModelsService",
            ],
            path: "Sources/Services/GitHubService"
        ),
        .target(
            name: "SweepService",
            dependencies: [],
            path: "Sources/Services/SweepService"
        ),
        .target(
            name: "PlanService",
            dependencies: ["RepositorySDK"],
            path: "Sources/Services/PlanService"
        ),
        .target(
            name: "PipelineService",
            dependencies: [
                "AIOutputSDK",
                .product(name: "CLISDK", package: "SwiftCLI"),
                "GitHubService",
                "GitSDK",
                .product(name: "Logging", package: "swift-log"),
                "OctokitSDK",
                "PipelineSDK",
                "PRRadarCLIService",
                "PRRadarModelsService",
            ],
            path: "Sources/Services/PipelineService"
        ),
        .target(
            name: "PRRadarCLIService",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
                "ClaudeAgentSDK",
                "CredentialService",
                "DataPathsService",
                "EnvironmentSDK",
                "GitHubService",
                "GitSDK",
                "OctokitSDK",
                "PRRadarConfigService",
                "PRRadarModelsService",
                "RepositorySDK",
            ],
            path: "Sources/Services/PRRadarCLIService"
        ),
        .target(
            name: "PRRadarConfigService",
            dependencies: [
                "DataPathsService",
                "EnvironmentSDK",
                "KeychainSDK",
                "PRRadarModelsService",
                "RepositorySDK",
            ],
            path: "Sources/Services/PRRadarConfigService"
        ),
        .target(
            name: "PRRadarModelsService",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/Services/PRRadarModelsService"
        ),
        .target(
            name: "ProviderRegistryService",
            dependencies: ["AIOutputSDK"],
            path: "Sources/Services/ProviderRegistryService"
        ),
        .target(
            name: "SettingsService",
            dependencies: [
                "DataPathsService",
                "RepositorySDK",
            ],
            path: "Sources/Services/SettingsService"
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
            name: "AppIPCSDK",
            dependencies: [],
            path: "Sources/SDKs/AppIPCSDK"
        ),
        .target(
            name: "ClaudeAgentSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
                "ConcurrencySDK",
                "EnvironmentSDK",
            ],
            path: "Sources/SDKs/ClaudeAgentSDK"
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
            name: "KeychainSDK",
            path: "Sources/SDKs/KeychainSDK"
        ),
        .target(
            name: "LoggingSDK",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SDKs/LoggingSDK"
        ),
        .target(
            name: "OctokitSDK",
            dependencies: [
                .product(name: "OctoKit", package: "octokit.swift"),
            ],
            path: "Sources/SDKs/OctokitSDK"
        ),
        .target(
            name: "PipelineSDK",
            dependencies: [
                "AIOutputSDK",
                "GitSDK",
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/SDKs/PipelineSDK"
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
        .target(
            name: "UseCaseSDK",
            path: "Sources/SDKs/UseCaseSDK"
        ),

        // ClaudeChain Targets
        .target(
            name: "ClaudeChainCLI",
            dependencies: [
                "AIOutputSDK",
                "AnthropicSDK",
                "ClaudeChainSDK",
                "ClaudeChainService",
                "ClaudeChainFeature",
                "ClaudeCLISDK",
                "CodexCLISDK",
                "CredentialService",
                "DataPathsService",
                "GitHubService",
                "GitSDK",
                "PRRadarCLIService",
                "ProviderRegistryService",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Apps/ClaudeChainCLI"
        ),
        .target(
            name: "ClaudeChainSDK",
            dependencies: [],
            path: "Sources/SDKs/ClaudeChainSDK"
        ),
        .target(
            name: "ClaudeChainService",
            dependencies: [
                "AIOutputSDK",
                "ClaudeChainSDK",
                "GitHubService",
                "GitSDK",
                .product(name: "Logging", package: "swift-log"),
                "OctokitSDK",
                "PipelineSDK",
                "PipelineService",
                "PRRadarCLIService",
                "PRRadarModelsService",
                "SweepService",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/Services/ClaudeChainService"
        ),
        .target(
            name: "ClaudeChainFeature",
            dependencies: ["AIOutputSDK", "ClaudeChainSDK", "ClaudeChainService", "CredentialService", "GitHubService", "GitSDK", "OctokitSDK", "PipelineSDK", "PipelineService", "PRRadarCLIService", "PRRadarModelsService", "SweepFeature", "UseCaseSDK"],
            path: "Sources/Features/ClaudeChainFeature"
        ),

        // Test Targets (alphabetical)
        .testTarget(
            name: "AIDevToolsKitMacTests",
            dependencies: ["AIDevToolsKitMac", "ClaudeChainFeature", "ClaudeChainService", "DataPathsService"],
            path: "Tests/Apps/AIDevToolsKitMacTests"
        ),
        .testTarget(
            name: "AIOutputSDKTests",
            dependencies: ["AIOutputSDK"],
            path: "Tests/SDKs/AIOutputSDKTests"
        ),
        .testTarget(
            name: "AIDevToolsKitCLITests",
            dependencies: [
                "AIDevToolsKitCLI",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "AppIPCSDKTests",
            dependencies: ["AppIPCSDK"],
            path: "Tests/SDKs/AppIPCSDKTests"
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
            name: "ClaudeChainCLITests",
            dependencies: ["ClaudeChainCLI"],
            path: "Tests/Apps/ClaudeChainCLITests"
        ),
        .testTarget(
            name: "ClaudeChainSDKTests",
            dependencies: ["ClaudeChainSDK", "ClaudeChainService"],
            path: "Tests/SDKs/ClaudeChainSDKTests"
        ),
        .testTarget(
            name: "ClaudeChainServiceTests",
            dependencies: ["ClaudeChainFeature", "ClaudeChainSDK", "ClaudeChainService"],
            path: "Tests/Services/ClaudeChainServiceTests"
        ),
        .testTarget(
            name: "ClaudeChainFeatureTests",
            dependencies: [
                "AIOutputSDK",
                "ClaudeChainFeature",
                "ClaudeChainSDK",
                "ClaudeChainService",
                "GitHubService",
                "OctokitSDK",
                "PRRadarModelsService",
            ],
            path: "Tests/Features/ClaudeChainFeatureTests"
        ),
        .testTarget(
            name: "ChatFeatureTests",
            dependencies: ["ChatFeature", "SkillScannerSDK"],
            path: "Tests/Features/ChatFeatureTests"
        ),
        .testTarget(
            name: "ChatServiceTests",
            dependencies: ["AIOutputSDK", "ChatService"],
            path: "Tests/Services/ChatServiceTests"
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
            name: "CredentialFeatureTests",
            dependencies: ["CredentialFeature", "CredentialService", "KeychainSDK"],
            path: "Tests/Features/CredentialFeatureTests"
        ),
        .testTarget(
            name: "CredentialServiceTests",
            dependencies: ["CredentialService", "KeychainSDK"],
            path: "Tests/Services/CredentialServiceTests"
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
            dependencies: ["AIOutputSDK", "EvalService", "RepositorySDK", "SkillScannerSDK"],
            path: "Tests/Services/EvalServiceTests"
        ),
        .testTarget(
            name: "GitSDKTests",
            dependencies: ["GitSDK"],
            path: "Tests/SDKs/GitSDKTests"
        ),
        .testTarget(
            name: "KeychainSDKTests",
            dependencies: ["KeychainSDK"],
            path: "Tests/SDKs/KeychainSDKTests"
        ),
        .testTarget(
            name: "LoggingSDKTests",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "LoggingSDK",
            ],
            path: "Tests/SDKs/LoggingSDKTests"
        ),
        .testTarget(
            name: "PlanFeatureTests",
            dependencies: ["GitSDK", "PlanFeature", "PlanService", "RepositorySDK"],
            path: "Tests/Features/PlanFeatureTests"
        ),
        .testTarget(
            name: "PlanServiceTests",
            dependencies: ["PlanService", "RepositorySDK"],
            path: "Tests/Services/PlanServiceTests"
        ),
        .testTarget(
            name: "PipelineFeatureTests",
            dependencies: ["PipelineFeature", "PipelineSDK", "PipelineService"],
            path: "Tests/Features/PipelineFeatureTests"
        ),
        .testTarget(
            name: "PipelineSDKTests",
            dependencies: ["AIOutputSDK", "GitSDK", "PipelineSDK", "PipelineService"],
            path: "Tests/SDKs/PipelineSDKTests"
        ),
        .testTarget(
            name: "PRRadarModelsServiceTests",
            dependencies: [
                "ClaudeAgentSDK",
                "EnvironmentSDK",
                "KeychainSDK",
                "PRRadarCLIService",
                "PRRadarConfigService",
                "PRRadarModelsService",
                "PRReviewFeature",
                "RepositorySDK",
            ],
            path: "Tests/Services/PRRadarModelsServiceTests",
            resources: [
                .copy("EffectiveDiffFixtures"),
            ]
        ),
        .testTarget(
            name: "RepositorySDKTests",
            dependencies: ["RepositorySDK"],
            path: "Tests/SDKs/RepositorySDKTests"
        ),
        .testTarget(
            name: "SkillBrowserFeatureTests",
            dependencies: ["RepositorySDK", "SkillBrowserFeature", "SkillScannerSDK"],
            path: "Tests/Features/SkillBrowserFeatureTests"
        ),
        .testTarget(
            name: "SkillScannerSDKTests",
            dependencies: ["SkillScannerSDK"],
            path: "Tests/SDKs/SkillScannerSDKTests"
        ),
        .testTarget(
            name: "SweepServiceTests",
            dependencies: ["SweepService"],
            path: "Tests/Services/SweepServiceTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
