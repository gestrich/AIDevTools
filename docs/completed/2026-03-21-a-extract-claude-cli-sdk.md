## Relevant Skills

| Skill | Description |
|-------|-------------|
| `/swift-architecture` | 4-layer Swift app architecture with layer placement, dependency rules, and code style conventions |
| `/swift-testing` | Test style guide and conventions |

## Background

EvalSDK currently bundles two concerns: (1) Claude/Codex CLI interaction (program definitions, stream parsing, execution) and (2) eval orchestration (adapters, output writing, rubric evaluation). The CLI interaction code should live in its own SDK target so it can be reused outside of the eval context.

The new `ClaudeCLISDK` should be **standalone and focused on Claude** — it handles defining, executing, and formatting output from the `claude` CLI. It should not contain eval domain types like `ProviderResult`, `ProviderError`, `ToolEvent`, etc.

The output **interpretation** (parsing Claude output into `ProviderResult`, extracting tool events, grading) stays in EvalSDK — that's the adapter layer mapping Claude-specific output into our eval domain.

Additionally, the existing `ClaudeSDK` target (Python Agent SDK) should be renamed to `ClaudePythonSDK` to clearly distinguish between the two Claude integration approaches: CLI (`ClaudeCLISDK`) vs Python Agent (`ClaudePythonSDK`).

### What moves to ClaudeCLISDK

| File | Current Location | Purpose in SDK |
|------|-----------------|----------------|
| `ClaudeCLI.swift` | EvalSDK | `@CLIProgram("claude")` struct — CLI command definition |
| `ClaudeStreamModels.swift` | EvalSDK/OutputParsing | Raw Codable event types for stream-json (`ClaudeAssistantEvent`, `ClaudeUserEvent`, content blocks) |
| `ClaudeStreamFormatter.swift` | EvalSDK/OutputParsing | Formats raw stream-json output into human-readable text for display |
| *(new)* `ClaudeCLIClient.swift` | Extracted from `ClaudeAdapter` | Environment setup, PATH enrichment, path resolution, execution → raw stdout/stderr/exitCode |

### What stays in EvalSDK

| File | Reason |
|------|--------|
| `ClaudeAdapter.swift` | Bridges `ClaudeCLISDK` → eval domain; builds commands from `RunConfiguration`, maps results to `ProviderResult` |
| `ClaudeOutputParser.swift` | Interprets Claude stdout → `ProviderResult`, `ToolEvent`, `ToolCallSummary` (all eval domain types) |
| `ClaudeResultEvent.swift` | Produces `ProviderError`, `ProviderMetrics` — eval domain mappings |
| `ParserConstants.swift` | `StructuredOutputKey`, `ProviderErrorSubtype` — used by both Claude and Codex adapters |
| `CodexCLI.swift` | Codex CLI definition |
| `CodexAdapter.swift` | Codex adapter |
| `CodexOutputParser.swift` | Codex parsing |
| `CodexStreamFormatter.swift` | Codex formatting |
| `CodexStreamModels.swift` | Codex stream models |
| `ProviderAdapterProtocol.swift` | Eval-specific protocol |
| `OutputService.swift` | Eval artifact writing |
| `RubricEvaluator.swift` | Eval-specific rubric grading |
| `GitClient.swift` | General git utility |

### JSONValue in ClaudeStreamModels/Formatter

`ClaudeStreamModels.swift` uses `JSONValue` for `ClaudeContentBlock.input: [String: JSONValue]?` and `ToolResultContent.array([[String: JSONValue]])`. `ClaudeStreamFormatter` uses it for decoding raw events and reading tool input fields.

Since `JSONValue` is a generic utility (recursive Codable JSON enum) and the SDK needs it for arbitrary JSON fields in Claude's stream output, `ClaudeCLISDK` will include its own copy. EvalService keeps its existing `JSONValue` — the two are identical but decoupled. The alternative (a shared micro-target) adds complexity for one small file.

### Dependency graph after refactor

```
ClaudeCLISDK (new)
  └── CLISDK (external)

EvalService (unchanged)
  └── SkillScannerSDK

EvalSDK
  ├── EvalService
  ├── ClaudeCLISDK (new)
  └── CLISDK
```

## Phases

## - [x] Phase 1: Create ClaudeCLISDK with CLI definition

**Skills used**: `swift-architecture`
**Principles applied**: SDK target depends only on CLISDK (no upward dependencies); standalone JSONValue copy avoids coupling to EvalService

**Skills to read**: `/swift-architecture`

Create the `ClaudeCLISDK` target with the Claude CLI program definition.

- Create `Sources/SDKs/ClaudeCLISDK/`
- Move `EvalSDK/ClaudeCLI.swift` → `Sources/SDKs/ClaudeCLISDK/ClaudeCLI.swift`
- Add a local `JSONValue.swift` to `Sources/SDKs/ClaudeCLISDK/` (copy from `EvalService/Models/JSONValue.swift`). This gives the SDK its own JSON type for decoding arbitrary fields in Claude's stream output without depending on EvalService.
- Add `ClaudeCLISDK` target to Package.swift with dependency on `CLISDK` only
- Add `ClaudeCLISDK` library product
- Verify `swift build` compiles

## - [x] Phase 2: Move stream models and formatter

**Skills used**: `swift-architecture`
**Principles applied**: Made all moved types `public` for cross-module access; introduced `ClaudeResultSummary` to avoid upward dependency from ClaudeCLISDK → EvalService; qualified `EvalService.JSONValue` in ClaudeOutputParser to resolve type ambiguity

**Skills to read**: `/swift-architecture`

Move the Claude stream event types and human-readable formatter.

Files to move:
- `EvalSDK/OutputParsing/ClaudeStreamModels.swift` → `Sources/SDKs/ClaudeCLISDK/ClaudeStreamModels.swift`
- `EvalSDK/OutputParsing/ClaudeStreamFormatter.swift` → `Sources/SDKs/ClaudeCLISDK/ClaudeStreamFormatter.swift`

Changes needed:
- Remove `import EvalService` — replaced by local `JSONValue`
- Make types `public` as needed for cross-module access (stream models are currently `internal`; `ClaudeStreamFormatter` is already `public`)
- EvalSDK files that reference these types (`ClaudeOutputParser`, `ClaudeResultEvent`, `ClaudeAdapter`, `OutputService`) add `import ClaudeCLISDK`
- `ClaudeOutputParser` and `ClaudeResultEvent` remain in EvalSDK but now import stream models from `ClaudeCLISDK`
- Handle `JSONValue` type ambiguity: EvalSDK files that use both `EvalService.JSONValue` and `ClaudeCLISDK.JSONValue` will need typealiases or explicit module qualification. Since `ClaudeOutputParser` consumes Claude stream types and produces `EvalService.ProviderResult`, it may need to map between the two `JSONValue` types.
- Verify `swift build` compiles

## - [x] Phase 3: Extract Claude execution logic into ClaudeCLIClient

**Skills used**: `swift-architecture`
**Principles applied**: SDK is stateless Sendable struct wrapping CLIClient; two `run` overloads (raw StreamOutput vs formatted String) follow single-operation SDK pattern; adapter delegates to SDK for execution

**Skills to read**: `/swift-architecture`

Extract the CLI execution logic from `ClaudeAdapter` into a reusable `ClaudeCLIClient` in `ClaudeCLISDK`.

Create `Sources/SDKs/ClaudeCLISDK/ClaudeCLIClient.swift`:
- Move environment setup logic from `ClaudeAdapter`: PATH enrichment (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`), `CLAUDECODE` env var clearing, `resolveClaudePath()`
- Provide a method like `func run(command: Claude, workingDirectory: String?, environment: [String: String]?, onOutput: (@Sendable (CLIOutputStream.Item) -> Void)?) async throws -> CLIExecutionResult` that executes the CLI and returns raw results
- Optionally provide a convenience `run` overload that uses the formatter to deliver human-readable output strings

Update `ClaudeAdapter`:
- Replace inline execution logic with a call to `ClaudeCLIClient.run()`
- Adapter becomes: build `Claude` command from `RunConfiguration` → call `ClaudeCLIClient.run()` → parse with `ClaudeOutputParser` → write with `OutputService`

## - [x] Phase 4: Update Package.swift and clean up

**Skills used**: `swift-architecture`
**Principles applied**: Verified dependency graph — ClaudeCLISDK depends only on CLISDK, EvalSDK depends on ClaudeCLISDK. All items were completed in prior phases.

**Skills to read**: `/swift-architecture`

- Add `ClaudeCLISDK` as dependency of `EvalSDK`
- Remove moved files from EvalSDK (`ClaudeCLI.swift`, `OutputParsing/ClaudeStreamModels.swift`, `OutputParsing/ClaudeStreamFormatter.swift`)
- Verify no circular dependencies
- Verify `ClaudeCLISDK` depends only on `CLISDK`

## - [x] Phase 5: Rename ClaudeSDK → ClaudePythonSDK

**Skills used**: `swift-architecture`
**Principles applied**: Renamed directories, Package.swift targets/products, and imports to clearly distinguish CLI SDK from Python Agent SDK

**Skills to read**: `/swift-architecture`

Rename the existing Python Agent SDK target to distinguish it from the new CLI SDK.

- Rename directory `Sources/SDKs/ClaudeSDK/` → `Sources/SDKs/ClaudePythonSDK/`
- Rename directory `Tests/SDKs/ClaudeSDKTests/` → `Tests/SDKs/ClaudePythonSDKTests/`
- Update `Package.swift`:
  - Rename target `ClaudeSDK` → `ClaudePythonSDK` and update its path
  - Rename test target `ClaudeSDKTests` → `ClaudePythonSDKTests` and update its dependency and path
  - Rename library product `ClaudeSDK` → `ClaudePythonSDK`
- Update any `import ClaudeSDK` to `import ClaudePythonSDK` (check all source and test files)
- Verify `swift build` compiles

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: Verified clean build, all EvalSDKTests (38) and ClaudePythonSDKTests (18) pass, ClaudeCLISDK has no upward dependencies

**Skills to read**: `/swift-testing`

- Run `swift build` to verify clean compilation of all targets
- Run `swift test` to verify no regressions across all targets
- Run `swift test --filter EvalSDKTests` specifically
- Run `swift test --filter ClaudePythonSDKTests` to verify Python Agent SDK is unaffected
- Verify `ClaudeCLISDK` has no dependency on `EvalService` or `EvalSDK`
- Verify `ClaudeCLISDK` depends only on `CLISDK` (and Foundation)
