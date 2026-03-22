# Architecture

## Layers

Ordered from highest (closest to user) to lowest (foundational). Higher layers may depend on lower layers but not the reverse.

### Apps
Entry points, UI, and CLI. Depends on: Features, Services, SDKs.
- **AIDevToolsKitCLI** — Command-line interface for evals, planning, and chat
- **AIDevToolsKitMac** — macOS SwiftUI application

### Features
Business logic orchestration and use cases. Depends on: Services, SDKs.
- **AnthropicChatFeature** — Anthropic API chat orchestration
- **ClaudeCodeChatFeature** — Claude Code CLI chat orchestration
- **EvalFeature** — Eval execution, grading, and result analysis
- **PlanRunnerFeature** — Plan generation and phase execution
- **SkillBrowserFeature** — Repository and skill browsing

### Services
Domain services and data persistence. Depends on: SDKs.
- **AnthropicChatService** — Anthropic chat session and message persistence
- **ClaudeCodeChatService** — Claude Code chat session persistence
- **EvalService** — Eval case storage and artifact management
- **PlanRunnerService** — Plan settings, plan entry model, architecture diagram model
- **SkillService** — Skill configuration and repository settings

### SDKs
Foundational utilities and external system interfaces. No internal dependencies.
- **AnthropicSDK** — Anthropic API client wrapper
- **ClaudeCLISDK** — Claude CLI process management
- **ClaudePythonSDK** — Claude Python SDK process management
- **CodexCLISDK** — Codex CLI process management
- **ConcurrencySDK** — Concurrency utilities
- **EnvironmentSDK** — Environment variable access
- **EvalSDK** — Eval case and assertion data models
- **GitSDK** — Git operations
- **LoggingSDK** — Logging configuration
- **RepositorySDK** — Repository configuration and storage
- **SkillScannerSDK** — Skill file scanning and parsing

## Dependency Rules
- Apps → Features, Services, SDKs
- Features → Services, SDKs
- Services → SDKs
- SDKs → (none)
