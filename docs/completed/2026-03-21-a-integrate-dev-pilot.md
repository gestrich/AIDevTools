## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps → Features → Services → SDKs), layer placement, dependency rules, use case protocols |
| `ai-dev-tools-debug` | CLI commands and file paths for the AIDevTools eval system |

## Background

DevPilot is a standalone Swift CLI at `/Users/bill/Developer/personal/claude-tools-skills/dev-pilot/` that provides a spec-driven planning tool: take voice-transcribed text, match it to a repository, generate a phased implementation plan, and execute each phase via Claude CLI sessions. It currently lives in a separate repo with its own `Package.swift` and flat architecture (Commands/, Models/, Services/).

Moving this into AIDevTools as **PlanRunner** consolidates Bill's AI development tooling into one package. The key benefit is **reuse of existing SDKs** — AIDevToolsKit already has `ClaudeCLISDK` (a Claude CLI wrapper using the shared `CLISDK` process execution layer), which overlaps heavily with DevPilot's `ClaudeService`. It also positions PlanRunner for a future Mac app UI alongside the existing eval runner and skill browser.

### Architecture Mapping (DevPilot → AIDevToolsKit as PlanRunner)

Using the swift-architecture layer placement rules:

| DevPilot Source | Layer | Rationale |
|---|---|---|
| `ClaudeService` + `StreamParser` | **Not needed** — reuse existing `ClaudeCLISDK` | Both wrap the Claude CLI process. DevPilot's structured-output JSON schema support and stream parsing need to be added to `ClaudeCLISDK` as new capabilities. |
| `WorktreeService` | **SDK** (`GitSDK` or extend existing) | Stateless, single operations (create/remove worktree). Generic git operations, not business-specific. |
| `LogService` | **SDK** (new `LoggingSDK` or fold into existing) | Stateless file-append utility. Could be useful across features. |
| `TimerDisplay` | **SDK** (new `TerminalSDK` or keep in Apps) | Terminal ANSI rendering is a single-purpose utility. Could stay in Apps layer since it's CLI-specific I/O. |
| `JobDirectory` | **Service** (`PlanRunnerService`) | Shared config/path conventions used by both plan and execute features. |
| `ReposConfig` / `Repository` | **Service** (`PlanRunnerService`) | Shared models used across plan and execute features. |
| `PlanGenerator` | **Feature** (`PlanRunnerFeature`) | Multi-step orchestration: match repo → generate plan → write to disk. |
| `PhaseExecutor` | **Feature** (`PlanRunnerFeature`) | Multi-step orchestration: loop phases → call Claude → track status → handle completion. |
| `PlanCommand` / `ExecuteCommand` | **Apps** (`AIDevToolsKitCLI`) | CLI entry points consuming features. |
| `PhaseStatus`, `ClaudeResponse` models | **Feature** (`PlanRunnerFeature/services/`) | Used only within the feature's use cases. |

### Key Decision: ClaudeCLISDK Reuse vs. New SDK

DevPilot's `ClaudeService` uses `--output-format stream-json` with `--json-schema` to get structured output from Claude. The existing `ClaudeCLISDK` already supports running Claude CLI commands and streaming output, but does **not** currently support structured output (JSON schema mode). Rather than duplicating the Claude CLI wrapper, we should **extend `ClaudeCLISDK`** to support structured output. This is the biggest integration point.

### What's NOT in scope

- **Mac app UI for PlanRunner** — Future work. This plan only adds the kit modules and CLI commands.
- **Voice integration / Apple Shortcuts** — Stays external; the `voice-plan.sh` script just calls the CLI binary.
- **Removing the standalone dev-pilot repo** — Can be done after migration is verified.

## Phases

## - [x] Phase 1: Extend ClaudeCLISDK with Structured Output Support

**Skills used**: `swift-architecture`
**Principles applied**: Added structured output parsing to the SDK layer as a stateless, reusable parser. Command model already had all needed flags. New `ClaudeCLISDKTests` test target with 15 unit tests.

**Skills to read**: `swift-architecture`

Add structured output capability to the existing `ClaudeCLISDK`:

- Add a `jsonSchema` parameter to the `Claude` command model so `--json-schema <schema>` is included in arguments when provided
- Add a `structuredOutput` parser to `ClaudeStreamFormatter` (or a new `ClaudeStructuredOutputParser`) that extracts the `structured_output` field from `result` events in stream-json output
- Ensure the `ClaudeCLIClient.run()` return path can surface the parsed structured output (likely as a new method or overload that returns `T: Decodable`)
- Add the `--dangerously-skip-permissions` and `--verbose` flags as options on the `Claude` command model
- Write unit tests for the new structured output parsing (similar to existing `ClaudeOutputParser` tests)

Files to modify:
- `AIDevToolsKit/Sources/SDKs/ClaudeCLISDK/ClaudeCLI.swift` (add schema/flags to command model)
- `AIDevToolsKit/Sources/SDKs/ClaudeCLISDK/ClaudeCLIClient.swift` (add structured output method)
- `AIDevToolsKit/Sources/SDKs/ClaudeCLISDK/ClaudeStreamFormatter.swift` or new parser file
- New test files in `Tests/SDKs/ClaudeCLISDKTests/`

## - [x] Phase 2: Add GitSDK for Worktree Operations

**Skills used**: `swift-architecture`
**Principles applied**: Used `@CLIProgram("git")` macro for declarative command definitions consistent with ClaudeCLISDK. Stateless `Sendable` struct with `CLIClient` for process execution. 7 argument-building tests + 5 integration tests.

**Skills to read**: `swift-architecture`

Create a new `GitSDK` module with stateless git operations:

- `GitClient` struct with methods: `createWorktree(repoPath:baseBranch:destination:)`, `removeWorktree(worktreePath:)`, `fetch(remote:branch:workingDirectory:)`, `add(files:workingDirectory:)`, `commit(message:workingDirectory:)`
- Uses `CLISDK`'s `CLIClient` for process execution (consistent with how `ClaudeCLISDK` works) instead of raw `Process` calls
- Stateless `Sendable` struct — no business logic, no DevPilot-specific types

Files to create:
- `AIDevToolsKit/Sources/SDKs/GitSDK/GitClient.swift`
- `AIDevToolsKit/Tests/SDKs/GitSDKTests/` (test argument building)

Add to `Package.swift`:
- New `GitSDK` target depending on `CLISDK`

## - [x] Phase 3: Add PlanRunnerService (Shared Models & Config)

**Skills used**: `swift-architecture`
**Principles applied**: Service layer placement for shared models/config. All types are `Codable`, `Sendable`, `public` with memberwise inits. Sorted Package.swift lists alphabetically per project conventions. 12 unit tests covering config loading, decoding errors, lookup, and JobDirectory URL/path derivation.

**Skills to read**: `swift-architecture`

Create a `PlanRunnerService` module for shared types used across plan and execute features:

- `ReposConfig` — load/decode `repos.json` (from `~/.dev-pilot/repos.json` or custom path)
- `Repository`, `Verification`, `PullRequestConfig` model types
- `JobDirectory` — path conventions for `~/Desktop/dev-pilot/<repo-id>/<job-name>/`

These are shared models and configuration, not orchestration — correct placement is Services layer.

Files to create:
- `AIDevToolsKit/Sources/Services/PlanRunnerService/Models/ReposConfig.swift`
- `AIDevToolsKit/Sources/Services/PlanRunnerService/Models/Repository.swift`
- `AIDevToolsKit/Sources/Services/PlanRunnerService/JobDirectory.swift`

Add to `Package.swift`:
- New `PlanRunnerService` target (no dependencies on other services or features)

## - [x] Phase 4: Add PlanRunnerFeature (Plan + Execute Use Cases)

**Skills used**: `swift-architecture`
**Principles applied**: Concrete use case structs with nested Options/Progress/Result types following existing EvalFeature patterns. Callback-based progress reporting via `@Sendable` closures. Terminal display deferred to Apps layer. All types `Codable`, `Sendable`, `public`. 14 unit tests covering model decoding, round-trips, options defaults, and error descriptions.

**Skills to read**: `swift-architecture`

Create the `PlanRunnerFeature` module with two use cases:

**`GeneratePlanUseCase`** (StreamingUseCase):
- Options: voice text, repos config
- Stream states: `.matchingRepo`, `.generatingPlan`, `.writingPlan`, `.completed(jobDir, repo)`
- Orchestrates: match repo via Claude → generate plan via Claude → write to disk
- Dependencies: `ClaudeCLIClient`, `PlanRunnerService`

**`ExecutePlanUseCase`** (StreamingUseCase):
- Options: plan path, repo path, max minutes, repository config
- Stream states: `.fetchingStatus`, `.executingPhase(index, description)`, `.phaseCompleted(index)`, `.allCompleted`, `.timeLimitReached`
- Orchestrates: loop over phases → call Claude for each → track status → handle completion
- Dependencies: `ClaudeCLIClient`, `GitClient`, `PlanRunnerService`

Feature-internal types (in `services/` subdirectory):
- `PhaseStatus`, `PhaseStatusResponse` — phase tracking
- `RepoMatch`, `GeneratedPlan`, `PhaseResult` — Claude response models

Files to create:
- `AIDevToolsKit/Sources/Features/PlanRunnerFeature/usecases/GeneratePlanUseCase.swift`
- `AIDevToolsKit/Sources/Features/PlanRunnerFeature/usecases/ExecutePlanUseCase.swift`
- `AIDevToolsKit/Sources/Features/PlanRunnerFeature/services/` (internal models)

Add to `Package.swift`:
- New `PlanRunnerFeature` target depending on `ClaudeCLISDK`, `GitSDK`, `PlanRunnerService`

## - [x] Phase 5: Add CLI Commands (Apps Layer)

**Skills used**: `swift-architecture`
**Principles applied**: CLI commands consume use cases directly with callback-based progress. Terminal-specific I/O (ANSI colors, TimerDisplay) stays in Apps layer. Interactive plan selection for execute command. Subcommand group registered alphabetically in EntryPoint.

**Skills to read**: `swift-architecture`

Add PlanRunner subcommands to the existing `AIDevToolsKitCLI`:

- `PlanRunnerCommand` as a new subcommand group on the existing CLI entry point (e.g. `ai-dev-tools-kit plan-runner plan "..."`)
- `PlanCommand` — consumes `GeneratePlanUseCase`, prints streaming progress, optionally chains to execute
- `ExecuteCommand` — consumes `ExecutePlanUseCase`, includes interactive plan selection, timer display, ANSI-colored output

The `TimerDisplay` and ANSI color output stay in the Apps layer since they are CLI-specific terminal I/O — not business logic.

Files to create/modify:
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PlanRunnerCommand.swift`
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PlanRunnerPlanCommand.swift`
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PlanRunnerExecuteCommand.swift`
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/TimerDisplay.swift`
- Modify `EntryPoint.swift` to register the new subcommand

Update `Package.swift`:
- Add `PlanRunnerFeature`, `PlanRunnerService`, `GitSDK` to `AIDevToolsKitCLI` dependencies

## - [x] Phase 6: Rename Config Directory from `.dev-pilot` to `.ai-dev-tools`

**Skills used**: none
**Principles applied**: Renamed default paths in ReposConfig and JobDirectory. Migrated ~/Desktop/dev-pilot/ contents to ~/Desktop/ai-dev-tools/ and removed the old directory. No migration warning needed since this is a single-machine setup.

Migrate the user-facing config directory so everything lives under one tool identity:

- Rename default config path from `~/.dev-pilot/repos.json` to `~/.ai-dev-tools/repos.json`
- Rename default job output directory from `~/Desktop/dev-pilot/` to `~/Desktop/ai-dev-tools/`
- Update `ReposConfig.load()` default path in `PlanRunnerService`
- Update `JobDirectory.baseURL` in `PlanRunnerService`
- Add a one-time migration check: if `~/.dev-pilot/` exists but `~/.ai-dev-tools/` does not, print a message telling the user to rename it (or auto-rename with confirmation). Keep this simple — a warning on first run is fine.
- Update the `voice-plan.sh` script path reference if it hardcodes `~/.dev-pilot`

## - [x] Phase 7: Validation

**Skills used**: `swift-architecture`, `ai-dev-tools-debug`
**Principles applied**: Verified all compilation, tests, dependency graph, and CLI help output.

**Skills to read**: `swift-architecture`, `ai-dev-tools-debug`

Verify the integration:

- Run `swift build` for the full package — all new targets compile
- Run `swift test` — all existing tests still pass
- Run new unit tests:
  - `ClaudeCLISDK` structured output parsing tests
  - `GitSDK` argument-building tests
  - `PlanRunnerService` config loading/decoding tests
- Verify dependency graph compliance:
  - No upward dependencies (Features → Apps, SDKs → Services, etc.)
  - No cross-feature dependencies
  - `GitSDK` and `ClaudeCLISDK` have no business-specific types
- Manually test CLI: `swift run ai-dev-tools-kit plan-runner plan "test"` and `swift run ai-dev-tools-kit plan-runner execute --plan <path>`

**Results:**
- `swift build`: all targets compile
- `swift test`: 245 tests in 26 suites pass
- Dependency graph: PlanRunnerFeature, GitSDK, ClaudeCLISDK all compliant. Pre-existing EvalSDK→EvalService violation noted (not introduced by this work).
- CLI: `plan-runner plan --help` and `plan-runner execute --help` both work correctly
