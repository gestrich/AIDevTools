## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `ai-dev-tools-debug` | File paths, CLI commands, and artifact structure for AIDevTools |

## Background

The `AIClient` protocol is the app's abstraction boundary for AI providers. Chat, architecture planning, and plan running are fully plugin-style — they call `AIClient.run()` / `runStructured()` and are completely unaware of which provider is behind the protocol. Add a new provider and these features work automatically.

**Evals are not plugin-style.** The eval system has provider-specific knowledge leaking outside the concrete SDKs:

1. **Output parsers in EvalSDK** — `ClaudeOutputParser` and `CodexOutputParser` live in EvalSDK, not in the provider SDKs. They understand each provider's raw output format (Claude's NDJSON stream-json, Codex's event format). This is provider-specific knowledge in the wrong layer.

2. **Raw stdout exposed outside the provider** — When `ClaudeAdapter.run()` calls `session.run()`, the raw stdout comes back in `AIClientResult.stdout`, leaves the provider SDK, enters EvalSDK, and gets fed back to a Claude-specific parser. The raw output round-trips out of and back into provider-specific code. There is no reason for raw output to leave the provider until it's parsed.

3. **Separate adapter types** — `ClaudeAdapter` and `CodexAdapter` in EvalSDK duplicate the same orchestration pattern (create session → run → parse → write artifacts) with provider-specific differences in parsing, schema passing, and error handling.

4. **Stream formatter selection via provider-name switches** — `ShowOutputCommand` and `EvalRunnerModel` switch on provider name strings to pick the right `StreamFormatter`. This is the App layer doing provider dispatch that should be handled by the protocol.

### Current flow (eval execution)

```
App layer creates ClaudeCLIClient + ClaudeAdapter
  → EvalProviderRegistry pairs them
    → RunEvalsUseCase calls adapter.run(config)
      → ClaudeAdapter creates AIRunSession
        → session.run() calls client.run() → AIClientResult with raw stdout
        → raw stdout LEAVES the provider SDK ← LEAK
        → ClaudeOutputParser in EvalSDK parses the raw stdout ← provider knowledge in wrong layer
        → OutputService.writeArtifacts() persists structured results
```

### Target flow (eval execution)

```
App layer creates ClaudeCLIClient (conforms to EvalCapable)
  → EvalProviderRegistry holds [any AIClient & EvalCapable]
    → RunEvalsUseCase calls client.runEval(config)
      → ClaudeCLIClient INTERNALLY:
        → executes CLI command
        → parses raw stdout with ClaudeOutputParser (in ClaudeCLISDK)
        → persists raw output for debugging
        → returns ProviderResult (already parsed)
      → EvalSDK just writes artifacts — no parsing, no provider knowledge
```

### Current flow (output reading/formatting)

```
ShowOutputCommand switches on provider name → picks ClaudeStreamFormatter or CodexStreamFormatter
  → ReadCaseOutputUseCase loads raw stdout from disk
    → applies StreamFormatter to produce display text
```

### Target flow (output reading/formatting)

```
ReadCaseOutputUseCase gets client from registry
  → client.streamFormatter (owned by provider)
    → loads raw stdout, formats internally
    → returns display text — no provider-name switches
```

### Design principle

`AIClient` is the **port** — the single gateway to a provider's entire world. Everything provider-specific (execution, parsing, formatting, capabilities, invocation detection) lives behind the port. Features and the eval system only know the protocol. Add a new provider, implement the protocol, and everything works.

## Phases

## - [ ] Phase 1: Move provider-facing eval types to AIOutputSDK

**Skills to read**: `swift-architecture`

Eval result types currently live in `EvalService` (Services layer). For providers to return `ProviderResult` from their SDK-layer conformance, these types need to be at the SDK level. Move the provider-facing types to `AIOutputSDK`:

### Types to move from EvalService to AIOutputSDK

- `ProviderResult` — what a provider returns from an eval run
- `ProviderError`, `ProviderErrorSubtype` — error reporting
- `ProviderMetrics` — duration, cost, turns
- `ProviderCapabilities` — what a provider supports
- `ToolEvent` — tool usage tracking
- `ToolCallSummary` — tool usage statistics
- `InvocationMethod` — how a skill was invoked (explicit/discovered/inferred)
- `SkillCheckResult` — skill invocation validation
- `JSONValue` — generic JSON representation (used in ProviderResult)

### Types that stay in EvalService

- `EvalCase`, `EvalSuite` — eval orchestration
- `EvalSummary`, `GradingResult` — grading/scoring
- `Provider` struct — can stay (it's just a string wrapper, already works with AIClient)
- `EvalMode` — eval-specific configuration

### Why AIOutputSDK

These types describe what a provider can produce, which is part of the output contract. They're analogous to `AIClientResult` (already in AIOutputSDK) — just richer for eval scenarios.

### Files to modify

- `AIOutputSDK/` — add new files for moved types
- `EvalService/Models/ProviderTypes.swift` — remove moved types, keep eval-specific types
- All importers of these types — verify they still compile

## - [ ] Phase 2: Add EvalCapable protocol to AIOutputSDK

**Skills to read**: `swift-architecture`

Define the eval capability as an optional protocol conformance, similar to `SessionListable`:

```swift
public protocol EvalCapable: Sendable {
    var evalCapabilities: ProviderCapabilities { get }
    var streamFormatter: any StreamFormatter { get }

    func runEval(
        prompt: String,
        outputSchemaPath: URL,
        artifactsDirectory: URL,
        caseId: String,
        model: String?,
        workingDirectory: URL?,
        evalMode: EvalMode,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> EvalRunOutput

    func invocationMethod(
        for skillName: String,
        toolEvents: [ToolEvent],
        traceCommands: [String],
        skills: [SkillInfo],
        repoRoot: URL?
    ) -> InvocationMethod?
}
```

### EvalRunOutput

A new type that bundles the provider's parsed result with the raw output path (for artifact persistence):

```swift
public struct EvalRunOutput: Sendable {
    public let result: ProviderResult
    public let rawStdout: String   // persisted by caller for debugging
    public let stderr: String
}
```

The key insight: `rawStdout` is still available for persistence/debugging, but the provider has already parsed it into `ProviderResult`. The caller never needs to parse it — it's opaque data for storage.

### Why a separate protocol (not on AIClient)

Not all providers need eval support. `AnthropicAIClient` may not implement evals. Same pattern as `SessionListable` — features check `client is EvalCapable` to decide what's available.

### Files to create

- `AIOutputSDK/EvalCapable.swift`
- `AIOutputSDK/EvalRunOutput.swift`

### Files to modify

- `AIOutputSDK/StreamFormatter.swift` — already exists, no changes needed

## - [ ] Phase 3: Establish clean provider plugin types

**Skills to read**: `swift-architecture`

Each provider SDK already has one type that conforms to `AIClient`, but the naming is inconsistent and the "plugin adapter" role isn't explicit. These types are the **plugin entry points** — thin wrappers that convert from provider-internal domains to the `AIClient` protocol. They should be clearly named and structured.

### Current state

| SDK | Plugin type | Conforms via | Internal domain types |
|-----|-----------|-------------|----------------------|
| ClaudeCLISDK | `ClaudeCLIClient` (struct) | `+AIClient.swift`, `+SessionListable.swift` extensions | `Claude` (CLI command struct), `ClaudeStreamFormatter`, `ClaudeStructuredOutputParser` |
| CodexCLISDK | `CodexCLIClient` (struct) | `+AIClient.swift` extension (AIClient + SessionListable) | `Codex.Exec` (CLI command), `CodexStreamFormatter`, `CodexSessionStorage` |
| AnthropicSDK | `AnthropicAIClient` (actor) | Declared directly on the class | `AnthropicAPIClient` (HTTP wrapper), `MessageBuilder`, `ConversationContext` |

### Rename to `*Provider`

The plugin types are not just "clients" — they're adapters that bridge a provider's internal world to the `AIClient` protocol. Rename for clarity:

- `ClaudeCLIClient` → `ClaudeProvider`
- `CodexCLIClient` → `CodexProvider`
- `AnthropicAIClient` → `AnthropicProvider`

The internal types keep their current names — `AnthropicAPIClient` is the HTTP client, `Claude` is the CLI command struct, etc. The `*Provider` is the thin wrapper that converts between those domains and `AIClient`.

### Consistent extension file pattern

Each provider should follow the same structure:

```
ClaudeCLISDK/
  ClaudeProvider.swift              — base struct + internal run methods
  ClaudeProvider+AIClient.swift     — AIClient conformance (run, runStructured)
  ClaudeProvider+SessionListable.swift  — SessionListable conformance
  ClaudeProvider+EvalCapable.swift  — EvalCapable conformance (new in Phase 4)
  Claude.swift                      — CLI command definition (internal domain)
  ClaudeStreamFormatter.swift       — StreamFormatter (internal, exposed via EvalCapable)
  ...
```

### Files to rename

- `ClaudeCLIClient.swift` → `ClaudeProvider.swift` (rename type inside)
- `ClaudeCLIClient+AIClient.swift` → `ClaudeProvider+AIClient.swift`
- `ClaudeCLIClient+SessionListable.swift` → `ClaudeProvider+SessionListable.swift`
- `CodexCLIClient.swift` → `CodexProvider.swift`
- `CodexCLIClient+AIClient.swift` → `CodexProvider+AIClient.swift`
- `AnthropicAIClient.swift` → `AnthropicProvider.swift`

### Update all references

Search for `ClaudeCLIClient`, `CodexCLIClient`, `AnthropicAIClient` across the codebase and update to new names. Most references are in:
- App layer (CompositionRoot, CLIRegistryFactory, ChatCommand)
- Tests
- `ChatSessionDetailView` (creates `ClaudeCLIClient()` directly — should use registry instead, but rename for now)

## - [ ] Phase 4: Move output parsers into provider SDKs

**Skills to read**: `swift-architecture`

Move the output parsing logic from EvalSDK into the provider SDKs where it belongs. Each provider owns its output format.

### ClaudeCLISDK gets:

- `ClaudeOutputParser.swift` (from `EvalSDK/OutputParsing/`)
- `ClaudeResultEvent.swift` (from `EvalSDK/OutputParsing/`)
- `ClaudeStreamModels.swift` (from `EvalSDK/OutputParsing/`)

### CodexCLISDK gets:

- `CodexOutputParser.swift` (from `EvalSDK/OutputParsing/`)
- `CodexStreamModels.swift` (from `EvalSDK/OutputParsing/`)

### ParserConstants

`ParserConstants.swift` contains shared constants (like `StructuredOutputKey`). Check whether these are truly shared or provider-specific. If shared, keep in AIOutputSDK. If provider-specific, split.

### Files to delete from EvalSDK

- `EvalSDK/OutputParsing/` directory (entire thing — all parsers moved to providers)

### Package.swift

- `ClaudeCLISDK` adds dependency on `AIOutputSDK` (already has it) — verify the moved types compile
- `CodexCLISDK` same
- `EvalSDK` removes whatever was only needed for parsing

## - [ ] Phase 5: Implement EvalCapable on providers

**Skills to read**: `swift-architecture`

### ClaudeProvider conforms to EvalCapable

```swift
extension ClaudeProvider: EvalCapable {
    public var evalCapabilities: ProviderCapabilities {
        ProviderCapabilities(supportsToolEventAssertions: true, supportsEventStream: true, supportsMetrics: true)
    }

    public var streamFormatter: any StreamFormatter {
        ClaudeStreamFormatter()
    }

    public func runEval(prompt:outputSchemaPath:...) async throws -> EvalRunOutput {
        // 1. Build AIClientOptions from eval parameters
        // 2. Call self.run(prompt:options:onOutput:)
        // 3. Parse raw stdout with ClaudeOutputParser (now local to this SDK)
        // 4. Return EvalRunOutput(result: parsedResult, rawStdout: result.stdout, stderr: result.stderr)
    }

    public func invocationMethod(for:toolEvents:traceCommands:skills:repoRoot:) -> InvocationMethod? {
        // Move logic from current ClaudeAdapter.invocationMethod
    }
}
```

### CodexProvider conforms to EvalCapable

Same pattern, using `CodexOutputParser` (now local to CodexCLISDK) and Codex-specific environment variable handling for schema/output paths.

### Key change: raw stdout stays internal

`runEval()` calls `self.run()`, gets raw stdout, parses it internally, and returns a `ProviderResult`. The raw output in `EvalRunOutput.rawStdout` is still available for the caller to persist for debugging, but the caller never needs to interpret it.

### Files to modify

- `ClaudeCLISDK/ClaudeProvider+EvalCapable.swift` (new extension file)
- `CodexCLISDK/CodexProvider+EvalCapable.swift` (new extension file)

## - [ ] Phase 6: Make EvalSDK provider-agnostic

**Skills to read**: `swift-architecture`

### Delete adapters

Remove `ClaudeAdapter.swift` and `CodexAdapter.swift` from EvalSDK. Their logic has been absorbed into the provider conformances.

### Delete ProviderAdapterProtocol

`ProviderAdapterProtocol` is replaced by `EvalCapable`. Remove it and `RunConfiguration` (eval parameters are now passed directly to `runEval()`).

### Update EvalProviderRegistry

`EvalProviderEntry` currently pairs `(client: any AIClient, adapter: any ProviderAdapterProtocol)`. Change to hold `any AIClient & EvalCapable`:

```swift
public struct EvalProviderEntry: Sendable {
    public let client: any AIClient & EvalCapable
    public var provider: Provider { Provider(client: client) }
    public var name: String { client.name }
    public var displayName: String { client.displayName }
}
```

No separate adapter needed — the client IS the adapter.

### Update OutputService

`OutputService` keeps its artifact writing responsibility but becomes simpler:
- `writeArtifacts(evalOutput:caseId:provider:artifactsDirectory:)` — takes `EvalRunOutput`, persists raw stdout + stderr + structured JSON
- No longer needs to know about adapters or parsers

### Update ReadCaseOutputUseCase

For the output reading path, the use case gets the `StreamFormatter` from the client instead of receiving it as a parameter:

```swift
// Old: caller switches on provider name to pick formatter
let formatter = formatterForProvider(provider)  // provider-name switch

// New: formatter comes from the client
let formatter = client.streamFormatter  // no switch needed
```

### Files to delete

- `EvalSDK/ClaudeAdapter.swift`
- `EvalSDK/CodexAdapter.swift`
- `EvalSDK/ProviderAdapterProtocol.swift` (or keep RunConfiguration if useful as a value object)

### Files to modify

- `ProviderRegistryService/EvalProviderRegistry.swift` — simplified entry type
- `EvalSDK/OutputService.swift` — simplified write method
- `EvalFeature/RunEvalsUseCase.swift` — call `client.runEval()` instead of `adapter.run()`
- `EvalFeature/ReadCaseOutputUseCase.swift` — get formatter from client
- `EvalFeature/RunCaseUseCase.swift` — if exists, update similarly

## - [ ] Phase 7: Remove provider-name switches from App layer

**Skills to read**: `swift-architecture`

### ShowOutputCommand

Currently:
```swift
private static func formatter(for provider: Provider) -> any StreamFormatter {
    switch provider.rawValue {
    case "codex": CodexStreamFormatter()
    default: ClaudeStreamFormatter()
    }
}
```

Replace with registry lookup:
```swift
let client = registry.evalEntries.first(where: { $0.name == provider })?.client
let formatter = client?.streamFormatter ?? ClaudeStreamFormatter() // fallback for unknown
```

Remove `import ClaudeCLISDK` and `import CodexCLISDK` from `ShowOutputCommand`.

### EvalRunnerModel

Same pattern — replace `formatterForProvider(_:)` switch with `client.streamFormatter` from registry.

### CompositionRoot / CLIRegistryFactory

Simplify eval registration — no longer need to create separate adapter objects:

```swift
// Old:
let claude = ClaudeCLIClient()
let claudeAdapter = ClaudeAdapter(client: claude)
let entry = EvalProviderEntry(client: claude, adapter: claudeAdapter)

// New:
let claude = ClaudeProvider()
let entry = EvalProviderEntry(client: claude)  // provider IS the adapter
```

### Files to modify

- `ShowOutputCommand.swift` — remove formatter switch, remove concrete SDK imports
- `EvalRunnerModel.swift` — remove formatter switch
- `CompositionRoot.swift` — simplify eval registration
- `CLIRegistryFactory.swift` — simplify eval registration

## - [ ] Phase 8: Clean up Package.swift dependencies

**Skills to read**: `swift-architecture`

### EvalSDK no longer needs concrete SDK knowledge

Before: EvalSDK contained ClaudeOutputParser, CodexOutputParser, ClaudeAdapter, CodexAdapter.
After: EvalSDK only contains OutputService and generic eval infrastructure.

Remove any concrete SDK dependencies from EvalSDK (verify current deps — it may already only depend on AIOutputSDK and EvalService).

### Verify dependency graph

```
Concrete SDKs (ClaudeCLISDK, CodexCLISDK)
  └── AIOutputSDK (for AIClient, EvalCapable, ProviderResult, etc.)

EvalSDK
  └── AIOutputSDK (for OutputService, generic types)
  └── EvalService (for eval orchestration types)

EvalFeature
  └── EvalSDK, EvalService, ProviderRegistryService

App layer
  └── Concrete SDKs (for DI wiring only)
  └── Features
```

No concrete SDK imports should exist outside the App layer.

### Grep verification

```bash
grep -r "import ClaudeCLISDK\|import CodexCLISDK" --include="*.swift" \
  Sources/Features/ Sources/Services/ Sources/SDKs/EvalSDK/
```

Expected: zero matches.

## - [ ] Phase 9: Validation

**Skills to read**: `ai-dev-tools-debug`

### Automated

- Build both CLI and Mac app targets — no compile errors
- Run full test suite — all existing tests pass
- Grep checks:
  - `grep -r "ClaudeOutputParser\|CodexOutputParser" --include="*.swift" Sources/SDKs/EvalSDK/` — zero matches (parsers moved to providers)
  - `grep -r "ClaudeAdapter\|CodexAdapter" --include="*.swift" Sources/` — zero matches (adapters deleted)
  - `grep -r "ProviderAdapterProtocol" --include="*.swift" Sources/` — zero matches (replaced by EvalCapable)
  - `grep -r "import ClaudeCLISDK\|import CodexCLISDK" --include="*.swift" Sources/Features/ Sources/Services/ Sources/SDKs/EvalSDK/` — zero matches
  - Provider-name formatter switches removed from App layer

### Manual

- CLI: `ai-dev-tools-kit run-evals --provider claude` — unchanged behavior
- CLI: `ai-dev-tools-kit run-evals --provider codex` — unchanged behavior
- CLI: `ai-dev-tools-kit run-evals --provider all` — runs all registered providers
- CLI: `ai-dev-tools-kit show-output --provider claude --case-id ...` — formatted output displays correctly
- Mac app: eval runs work for all providers
- Mac app: output viewer shows formatted results

### Plugin test

Create a mock provider conforming to `AIClient & EvalCapable` with stub implementations. Register it → it should appear in eval menus and run without any code changes to EvalSDK, EvalFeature, or the App layer.
