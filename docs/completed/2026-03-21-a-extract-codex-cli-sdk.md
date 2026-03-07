## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Eval system debugging — artifact paths, CLI commands, grading layers |
| `swift-testing` | Test style guide and conventions |

## Background

Following the `ClaudeCLISDK` extraction (completed 2026-03-21), the same separation should be applied to the Codex CLI code. Currently, EvalSDK bundles Codex CLI interaction (program definition, stream parsing, execution) alongside eval-domain logic (adapter, output parsing into `ProviderResult`). The CLI interaction code should live in its own `CodexCLISDK` target so it can be reused outside the eval context.

The pattern mirrors `ClaudeCLISDK` exactly:

### What moves to CodexCLISDK

| File | Current Location | Purpose in SDK |
|------|-----------------|----------------|
| `CodexCLI.swift` | EvalSDK | `@CLIProgram("codex")` struct — CLI command definition |
| `CodexStreamModels.swift` | EvalSDK/OutputParsing | Codable event types for Codex's JSON stream (`CodexStreamEvent`, `CodexEventItem`) |
| `CodexStreamFormatter.swift` | EvalSDK/OutputParsing | Formats raw Codex JSON stream into human-readable text |
| *(new)* `CodexCLIClient.swift` | Extracted from `CodexAdapter` | Environment setup, PATH enrichment, execution → raw stdout/stderr/exitCode |

### What stays in EvalSDK

| File | Reason |
|------|--------|
| `CodexAdapter.swift` | Bridges `CodexCLISDK` → eval domain; builds commands from `RunConfiguration`, maps results to `ProviderResult` |
| `CodexOutputParser.swift` | Interprets Codex stdout → `ProviderResult`, `ToolEvent`, `ToolCallSummary` (all eval domain types) |

### Difference from ClaudeCLISDK extraction

The Codex extraction is simpler:
- No `JSONValue` copy needed — `CodexStreamModels` uses only `Foundation` types
- No `ClaudeEnvironmentKey` equivalent — Codex doesn't have environment variables to clear
- The `CodexCLIClient` will still do PATH enrichment (matching `ClaudeCLIClient`) and resolve the `codex` binary path

### Dependency graph after refactor

```
CodexCLISDK (new)
  └── CLISDK (external)

ClaudeCLISDK (existing)
  └── CLISDK (external)

EvalSDK
  ├── EvalService
  ├── ClaudeCLISDK
  ├── CodexCLISDK (new)
  └── CLISDK

OutputService (in EvalSDK)
  ├── imports ClaudeCLISDK (for ClaudeStreamFormatter)
  └── imports CodexCLISDK (new, for CodexStreamFormatter)
```

## Phases

## - [x] Phase 1: Create CodexCLISDK with CLI definition and stream types

**Principles applied**: Mirrored ClaudeCLISDK extraction pattern; made types public for cross-module access

**Skills to read**: none

Create the `CodexCLISDK` target with the Codex CLI program definition and stream models.

- Create `Sources/SDKs/CodexCLISDK/`
- Move `EvalSDK/CodexCLI.swift` → `CodexCLISDK/CodexCLI.swift`
- Move `EvalSDK/OutputParsing/CodexStreamModels.swift` → `CodexCLISDK/CodexStreamModels.swift`
- Move `EvalSDK/OutputParsing/CodexStreamFormatter.swift` → `CodexCLISDK/CodexStreamFormatter.swift`
- Make types `public` as needed for cross-module access
- Add `CodexCLISDK` target to `Package.swift` with dependency on `CLISDK` only
- Add `CodexCLISDK` library product
- Add `CodexCLISDK` as a dependency of `EvalSDK`
- Update `EvalSDK` files that reference moved types (`CodexAdapter`, `CodexOutputParser`, `OutputService`) to `import CodexCLISDK`
- Verify `swift build` compiles

## - [x] Phase 2: Extract Codex execution logic into CodexCLIClient

**Principles applied**: Mirrored ClaudeCLIClient pattern with PATH enrichment, binary resolution, and raw/formatted output overloads; simplified CodexAdapter to delegate execution

**Skills to read**: none

Extract the CLI execution logic from `CodexAdapter` into a reusable `CodexCLIClient` in `CodexCLISDK`, mirroring the `ClaudeCLIClient` pattern.

Create `Sources/SDKs/CodexCLISDK/CodexCLIClient.swift`:
- Move execution boilerplate from `CodexAdapter`: `CLIClient` wrapping, `CLIOutputStream` setup, stream formatting callback, `finishAll`/cancel cleanup
- Provide `func run(command: Codex, workingDirectory: String?, environment: [String: String]?, onOutput: (@Sendable (StreamOutput) -> Void)?) async throws -> ExecutionResult` for raw output
- Provide a convenience `func run(command: Codex, ..., onFormattedOutput: (@Sendable (String) -> Void)?) async throws -> ExecutionResult` that uses `CodexStreamFormatter` internally
- Include PATH enrichment (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`) and `resolveCodexPath()` for binary resolution

Update `CodexAdapter`:
- Replace inline execution logic with a call to `CodexCLIClient.run()`
- Adapter becomes: build `Codex.Exec` command from `RunConfiguration` → call `CodexCLIClient.run()` → parse with `CodexOutputParser` → write with `OutputService`
- Verify `swift build` compiles

## - [x] Phase 3: Clean up and verify dependency graph

**Principles applied**: Verified dependency graph integrity — no orphaned files, no circular deps, clean build

**Skills to read**: none

- Verify `CodexCLISDK` depends only on `CLISDK` (no `EvalService` or `EvalSDK`)
- Verify no circular dependencies
- Verify `OutputService` imports both `ClaudeCLISDK` and `CodexCLISDK` and uses each formatter correctly
- Remove any orphaned files from `EvalSDK/OutputParsing/` (the moved Codex stream files)
- Verify `swift build` compiles cleanly

## - [x] Phase 4: Validation

**Skills used**: `swift-testing`
**Principles applied**: Verified clean build, all 189 unit tests pass, all 38 EvalSDK tests pass; integration test failures are pre-existing (no CLI binaries)

**Skills to read**: `swift-testing`

- Run `swift build` to verify clean compilation of all targets
- Run `swift test` to verify no regressions across all targets
- Run `swift test --filter EvalSDKTests` specifically — these tests exercise the adapters and parsers
- Verify `CodexCLISDK` has no dependency on `EvalService` or `EvalSDK`
- Verify `CodexCLISDK` depends only on `CLISDK` (and Foundation)
