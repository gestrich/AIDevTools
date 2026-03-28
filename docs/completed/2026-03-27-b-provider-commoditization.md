## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `ai-dev-tools-debug` | File paths, CLI commands, and artifact structure for AIDevTools |

## Background

The previous spec (2026-03-27-a) moved concrete SDK imports out of Features and EvalSDK so they only depend on `AIOutputSDK`. That was the first step — Features no longer *import* concrete SDKs.

But Features still **know which providers exist**. The `Provider` enum is hardcoded with `.claude` and `.codex`. CLI commands define `ProviderChoice` enums that mirror these cases. Mac app views define `ProviderSelection` and `ChatMode` enums that hardcode provider names into UI labels. Every adapter factory is a `switch` statement over known providers.

The goal is to **treat providers as complete commodities**. No Feature, SDK, or UI should know what providers exist. Instead:

1. The `AIClient` protocol exposes identity (name/display name) so providers self-describe
2. A `ProviderRegistry` service returns the list of available providers at runtime
3. Features and UIs iterate over that list dynamically — if a 4th provider is added, it appears everywhere automatically
4. Only the App layer (CLI entry point, Mac composition root) registers concrete providers

### Current hardcoded provider references

| Location | What's hardcoded |
|----------|-----------------|
| `Provider` enum (`ProviderTypes.swift`) | Two cases: `.claude`, `.codex` |
| `ProviderChoice` enum (`RunEvalsCommand.swift`) | CLI `--provider` flag options |
| `ProviderSelection` enum (`EvalResultsView.swift`) | Mac eval run menu labels |
| `ChatMode` enum (`WorkspaceView.swift`) | Mac chat mode picker ("API" / "CLI") |
| `RunEvalsCommand.run()` | Adapter factory switch |
| `EvalRunnerModel.init()` | Adapter factory switch |
| `ArchitecturePlannerModel.init()` | Defaults to `ClaudeCLIClient()` for all use cases |
| `PlanRunnerExecuteCommand` | Hardcoded `ClaudeCLIClient()` |
| `ArchPlannerExecuteCommand` | Hardcoded `ClaudeCLIClient()` |
| `ChatCommand` / `ClaudeChatCommand` | Two separate commands, each hardcoded to one provider |
| `WorkspaceView.chatPanelView` | Switch on `ChatMode` to build provider-specific views |
| `RunEvalMenu` / `RunEvalMenuCompact` | Hardcoded buttons per provider |

### Target state

```
AIClient protocol
  ├── name: String          (machine identifier, e.g. "claude")
  ├── displayName: String   (human label, e.g. "Claude CLI")
  └── run() / runStructured()

ProviderRegistry (Service layer)
  └── availableProviders() → [any AIClient]

EvalProviderRegistry (Service layer, extends for eval-specific adapters)
  └── availableAdapters(debug:) → [ProviderEntry]

Features / SDKs
  └── Accept [any AIClient] or [ProviderEntry] — never enumerate providers themselves

App layer (CLI / Mac)
  └── Creates registry, registers concrete providers, injects into features
```

## Phases

## - [x] Phase 1: Add identity to AIClient and make Provider extensible

**Skills used**: `swift-architecture`
**Principles applied**: Added identity at the SDK protocol level so providers self-describe; converted Provider to extensible struct with backward-compatible static constants

**Skills to read**: `swift-architecture`

### AIClient identity

Add two properties to the `AIClient` protocol in `AIOutputSDK`:

```swift
public protocol AIClient: Sendable {
    var name: String { get }         // machine id, used for artifact directories
    var displayName: String { get }  // human-readable, used in UI/CLI output
    // existing methods unchanged
}
```

Update all conformers:
- `ClaudeCLIClient` → `name: "claude"`, `displayName: "Claude CLI"`
- `CodexCLIClient` → `name: "codex"`, `displayName: "Codex CLI"`
- `AnthropicAIClient` → `name: "anthropic-api"`, `displayName: "Anthropic API"`

### Make Provider a struct

Replace the `Provider` enum in `ProviderTypes.swift` with an extensible struct:

```swift
public struct Provider: RawRepresentable, Codable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }
}
```

Remove the hardcoded `.claude` and `.codex` static constants — these should come from `AIClient.name` at the App layer. If callers need to construct a `Provider` from an `AIClient`, add a convenience:

```swift
extension Provider {
    public init(client: any AIClient) {
        self.init(rawValue: client.name)
    }
}
```

This preserves backward compatibility: existing JSON artifacts with `"claude"` or `"codex"` decode correctly since `RawRepresentable<String>` handles arbitrary strings.

### Files to modify

- `AIOutputSDK/AIClient.swift` — add `name` and `displayName` protocol requirements
- `ClaudeCLISDK/ClaudeCLIClient.swift` — implement `name` / `displayName`
- `CodexCLISDK/CodexCLIClient.swift` — implement `name` / `displayName`
- `AnthropicSDK/AnthropicAIClient.swift` — implement `name` / `displayName`
- `EvalService/Models/ProviderTypes.swift` — change `Provider` from enum to struct, remove `CaseIterable`
- All call sites using `Provider.allCases` or switching on `Provider` — update to use registry (later phases)

### Migration note

`CaseIterable` goes away. Any code doing `Provider.allCases` will break intentionally — those sites must be migrated to use the registry in later phases.

## - [x] Phase 2: Create ProviderRegistry service

**Skills to read**: `swift-architecture`

Create a `ProviderRegistry` in the Services layer that returns available providers. This is the single source of truth for "what providers are available."

### Design

```swift
// Services/ProviderRegistryService/ProviderRegistry.swift

public struct ProviderRegistry: Sendable {
    public let providers: [any AIClient]

    public init(providers: [any AIClient]) {
        self.providers = providers
    }

    public var providerNames: [String] {
        providers.map(\.name)
    }

    public func client(named name: String) -> (any AIClient)? {
        providers.first { $0.name == name }
    }
}
```

### For evals — adapter registration

Evals need `ProviderAdapterProtocol`, not just `AIClient`. Extend the pattern:

```swift
public struct EvalProviderEntry: Sendable {
    public let client: any AIClient
    public let adapter: any ProviderAdapterProtocol

    public var provider: Provider { Provider(client: client) }
    public var name: String { client.name }
    public var displayName: String { client.displayName }
}

public struct EvalProviderRegistry: Sendable {
    public let entries: [EvalProviderEntry]

    public init(entries: [EvalProviderEntry]) {
        self.entries = entries
    }
}
```

### Files to create

- `Services/ProviderRegistryService/ProviderRegistry.swift`

### Files to modify

- `Package.swift` — add `ProviderRegistryService` target, depend on `AIOutputSDK`
- `EvalSDK` or `EvalFeature` — update `ProviderEntry` to use `EvalProviderEntry` (or alias it)

### Design note

The registry is a simple value type, not a singleton. The App layer creates it and injects it into features. This follows the existing DI pattern (same as how `DataPathsService` is created at the App layer and threaded through).

## - [x] Phase 3: Update EvalFeature and EvalSDK to use registry

**Skills to read**: `swift-architecture`

### RunEvalsUseCase

Replace the two init patterns (factory closure / provider list) with a single init that takes an `EvalProviderRegistry`:

```swift
public init(
    registry: EvalProviderRegistry,
    // other deps unchanged
)
```

The `Options.providers` field changes from `[Provider]` to `[String]` (provider names) or is removed entirely if running all providers. Add an optional filter:

```swift
public struct Options {
    // ...
    public let providerFilter: [String]?  // nil = all registered, ["claude"] = just claude
}
```

The `run()` method resolves entries from the registry, filtered by `providerFilter`.

### ProviderAdapterProtocol

Update `ProviderAdapterProtocol` so adapters self-describe via their `AIClient`:

- `RunConfiguration.provider` stays as `Provider` (struct), but is now derived from the adapter's client
- Remove the need for callers to pass `Provider` explicitly

### Files to modify

- `EvalFeature/RunEvalsUseCase.swift` — new init taking registry, updated `Options`, updated `run()`
- `EvalSDK/ProviderAdapterProtocol.swift` — `RunConfiguration` derives provider from client
- `EvalSDK/ClaudeAdapter.swift` — derive provider from injected client
- `EvalSDK/CodexAdapter.swift` — derive provider from injected client

### Backward compatibility

`OutputService` uses `provider.rawValue` for directory names. Since `Provider` is now a struct with string `rawValue`, and `AIClient.name` returns the same strings (`"claude"`, `"codex"`), existing artifact directories are compatible.

## - [x] Phase 4: Update CLI commands to use registry

**Skills to read**: `swift-architecture`

### Eval CLI

Replace `ProviderChoice` enum in `RunEvalsCommand` with a dynamic `--provider` option:

```swift
@Option(help: "Provider name(s), comma-separated, or 'all' (default: all)")
var provider: String = "all"
```

The command creates the registry at startup and filters by the flag value. If the user types `--provider claude`, it filters to just claude. `--provider all` (or omitting the flag) runs all registered providers.

Remove the `ProviderChoice` enum entirely.

### Chat CLI

Unify `ChatCommand` and `ClaudeChatCommand` into a single command with a `--provider` flag:

```swift
struct ChatCommand: AsyncParsableCommand {
    @Option(help: "Provider to use for chat")
    var provider: String?

    @Option(help: "API key (required for anthropic-api provider)")
    var apiKey: String?

    // ... rest of options
}
```

If `--provider` is omitted, the command lists available providers and prompts, or uses a default. Provider-specific options (like `--api-key`, `--resume`, `--working-dir`) remain but are only validated when relevant.

Remove `ClaudeChatCommand` as a separate subcommand.

### Planning CLI

Add a `--provider` flag to `PlanRunnerExecuteCommand` and `ArchPlannerExecuteCommand`:

```swift
@Option(help: "Provider to use (default: first registered)")
var provider: String?
```

Replace hardcoded `ClaudeCLIClient()` with a lookup from the registry.

### Files to modify

- `RunEvalsCommand.swift` — replace `ProviderChoice` with string-based `--provider`, create registry
- `ChatCommand.swift` — add `--provider` flag, absorb `ClaudeChatCommand` functionality
- `ClaudeChatCommand.swift` — delete (merged into `ChatCommand`)
- `PlanRunnerExecuteCommand.swift` — add `--provider` flag
- `ArchPlannerExecuteCommand2.swift` — add `--provider` flag
- `EntryPoint.swift` — remove `ClaudeChatCommand` from subcommands list

### Design note

The CLI creates the registry in each command's `run()`. This could be extracted to a shared helper:

```swift
func makeRegistry() -> ProviderRegistry {
    ProviderRegistry(providers: [
        ClaudeCLIClient(),
        CodexCLIClient(),
        AnthropicAIClient(apiClient: ...)
    ])
}
```

The `AnthropicAIClient` requires an API key, so it may be conditionally registered (only when the key is available).

## - [x] Phase 5: Update Mac app to use registry

**Skills to read**: `swift-architecture`

### Composition root

Create the `ProviderRegistry` and `EvalProviderRegistry` in the Mac app's composition root and inject them into models.

### Chat panel

Replace `ChatMode` enum in `WorkspaceView` with a dynamic list from the registry:

```swift
// Instead of:
enum ChatMode: String, CaseIterable {
    case anthropicAPI = "API"
    case claudeCode = "CLI"
}

// Use:
// The picker iterates over registry.providers, displaying each provider's displayName
Picker("", selection: $selectedProviderName) {
    ForEach(registry.providers, id: \.name) { provider in
        Text(provider.displayName).tag(provider.name)
    }
}
```

The chat panel view becomes generic — given a selected `AIClient`, it builds the appropriate chat view. Since both `AnthropicChatFeature` and `ClaudeCodeChatFeature` already accept `any AIClient`, the switching logic simplifies.

### Eval run menu

Replace `ProviderSelection` enum and hardcoded `RunEvalMenu` buttons with dynamic iteration:

```swift
struct RunEvalMenu: View {
    let providers: [any AIClient]
    let onRun: ([any AIClient]) -> Void

    var body: some View {
        Menu {
            ForEach(providers, id: \.name) { provider in
                Button { onRun([provider]) } label: {
                    Label(provider.displayName, systemImage: "play.fill")
                }
            }
            if providers.count > 1 {
                Divider()
                Button { onRun(providers) } label: {
                    Label("All", systemImage: "play.fill")
                }
            }
        } label: {
            Label("Run", systemImage: "play.fill")
        }
    }
}
```

Delete `ProviderSelection` enum.

### Architecture planner model

`ArchitecturePlannerModel.init()` currently defaults all use cases to `ClaudeCLIClient()`. Instead, accept a single `client: any AIClient` parameter (or a registry) and construct use cases from it:

```swift
init(
    dataPathsService: DataPathsService,
    client: any AIClient,
    // ...
) {
    self.compileArchInfoUseCase = CompileArchitectureInfoUseCase(client: client)
    self.executeUseCase = ExecuteImplementationUseCase(client: client)
    // etc.
}
```

The Mac app can then add a provider picker for planning, or use a default from the registry.

### Files to modify

- `WorkspaceView.swift` — replace `ChatMode` with dynamic picker from registry
- `EvalResultsView.swift` — delete `ProviderSelection`, make `RunEvalMenu`/`RunEvalMenuCompact` dynamic
- `EvalRunnerModel.swift` — accept registry instead of hardcoded adapter factory
- `ArchitecturePlannerModel.swift` — accept `any AIClient` instead of defaulting to `ClaudeCLIClient()`
- Mac composition root — create and inject registries

### Chat view considerations

The two chat views (`ChatView` for Anthropic API and `ClaudeCodeChatView` for CLI) have different UIs (session picker, settings for CLI). There are two approaches:

**Option A**: Keep both views, but select dynamically based on provider capabilities rather than provider identity. Add a capability flag to `AIClient` (e.g., `supportsSessionResume`).

**Option B**: Unify into a single chat view that works with any `AIClient`. Session features are conditionally shown based on the client type. This is the cleaner long-term approach but more work.

Recommend **Option A** for this spec — keep the views, but the picker is driven by the registry instead of a hardcoded enum. A full chat unification can be a follow-up.

## - [x] Phase 6: Clean up Provider enum usage across codebase

**Skills to read**: `swift-architecture`

With `Provider` now a struct and the registry in place, sweep through remaining code that assumed the enum:

### Pattern: `switch provider { case .claude: ... case .codex: ... }`

These switches no longer compile (struct has no exhaustive cases). Replace with:
- Registry lookups
- String-based dispatch
- Or remove entirely if the switch was just mapping provider → client

### Pattern: `Provider.allCases`

Replace with `registry.providers` or `registry.providerNames`.

### Pattern: `ProviderResult.provider`

This stays as `Provider` (struct). It's already set from adapter results. Verify it's populated from `AIClient.name` through the adapter flow.

### Files to audit

- `EvalRunnerModel.swift` — `Provider.allCases` iteration for loading summaries
- `OutputService.swift` — provider directory naming (should work unchanged since `rawValue` is the same)
- Any test files that reference `Provider.claude` or `Provider.codex` — update to use `Provider(rawValue: "claude")` or construct from test clients

## - [x] Phase 7: Validation

**Skills to read**: `ai-dev-tools-debug`

### Automated

- Build both CLI and Mac app targets with no compile errors
- Run full test suite — all existing tests pass
- Grep for hardcoded provider references in Features and SDKs:
  ```bash
  grep -rn "\.claude\b\|\.codex\b\|ClaudeCLIClient\|CodexCLIClient\|AnthropicAIClient" \
    --include="*.swift" \
    AIDevToolsKit/Sources/Features/ \
    AIDevToolsKit/Sources/SDKs/EvalSDK/
  ```
  Expected: zero matches (only `AIClient.name` returns these strings)

### Manual

- CLI: `ai-dev-tools-kit run-evals --provider claude` — runs only Claude
- CLI: `ai-dev-tools-kit run-evals --provider all` — runs all registered providers
- CLI: `ai-dev-tools-kit chat --provider claude` — opens Claude CLI chat
- CLI: `ai-dev-tools-kit chat --provider anthropic-api --api-key ...` — opens API chat
- CLI: plan runner with `--provider codex` — runs planning with Codex
- Mac app: eval run menu dynamically shows all registered providers
- Mac app: chat picker dynamically shows all registered providers
- Mac app: planner uses selected/default provider

### Adding a test provider

To verify true commoditization, create a mock provider and confirm it appears everywhere without code changes:

```swift
struct MockAIClient: AIClient {
    var name: String { "mock" }
    var displayName: String { "Mock Provider" }
    // stub methods
}
```

Register it in the App layer → it should appear in eval menus, chat pickers, and planning options automatically.
