> **2026-03-29 Obsolescence Evaluation:** Completed. All phases marked [x] complete and RunChainTaskUseCase exists in the codebase. ClaudeChain now has inline AI execution instead of relying on external GitHub Actions, with streaming output, provider swappability, and single-command operation.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) with placement guidance |
| `swift-swiftui` | SwiftUI Model-View architecture patterns including enum-based state and observable models |

## Background

Claude chain currently relies on a multi-step GitHub Actions workflow to execute AI tasks. The flow is: `PrepareCommand` generates a prompt and outputs it → an external `claude-code-action` GitHub Action runs Claude with that prompt → `FinalizeCommand` reads the result and creates a PR. The AI invocation happens entirely outside our app.

We want to bring AI execution inside the app using our existing `AIClient` protocol, the same way the Markdown Planner (`ExecutePlanUseCase`) and Evals (`RunCaseUseCase`) already do. This gives us:

1. **Provider swappability** — use any configured AI provider (Claude, Codex, etc.) via `ProviderRegistry`
2. **Single-command execution** — one CLI command does everything: prepare → run AI → run scripts → finalize → create PR
3. **Rich streaming output** — reuse `ChatMessagesView` and `StreamAccumulator` to show live AI output in the Mac app
4. **Local or workflow execution** — the same command works locally or invoked from a GitHub workflow

The existing `ExecuteChainUseCase` already does a simplified version of this (prepare → shell out to `claude` CLI → create PR), but it uses `Process` directly instead of `AIClient`, has no streaming, no pre/post scripts, and no progress reporting.

**Phases in the new unified flow** (matching the original Python claude-chain workflow):

1. **Prepare** — load project, check capacity, find next task, create branch
2. **Pre-action script** — run optional `pre-action.sh`
3. **AI execution** — call `AIClient.run()` with the task prompt, streaming output
4. **Post-action script** — run optional `post-action.sh`
5. **Finalize** — commit changes, mark task complete in spec.md, push branch, create PR
6. **PR Summary** — second AI call to analyze the PR diff and generate a summary
7. **Post PR Comment** — post AI-generated summary + cost breakdown as a PR comment
8. **Notify** — format and send Slack notification (if webhook configured)

The Mac app will show each of these phases in the `ClaudeChainView` with a `ChatMessagesView` at the bottom (same pattern as `MarkdownPlannerDetailView`), with status messages for each phase and streaming AI output during the AI execution phase.

## Phases

## - [x] Phase 1: Create `RunChainTaskUseCase` in ClaudeChainFeature

**Skills used**: `swift-architecture`
**Principles applied**: Use case struct in Features layer with AIClient injected as dependency. Progress enum follows ExecutePlanUseCase pattern with @Sendable callback. Reused existing SDK/Service types (ProjectRepository, ScriptRunner, GitOperations, GitHubOperations, PRService, TaskService). Summary and comment posting are non-fatal to avoid blocking the main task flow.

**Skills to read**: `swift-architecture`

Create a new use case `RunChainTaskUseCase` in `Sources/Features/ClaudeChainFeature/usecases/` that orchestrates the full chain execution internally. This is the core change — it replaces the split `PrepareCommand` → external AI → `FinalizeCommand` flow with a single use case that calls `AIClient`.

**Structure:**
- `RunChainTaskUseCase` takes an `AIClient` dependency (injected, not created internally)
- `Options` struct: `repoPath: URL`, `projectName: String` (GitHub auth is resolved externally by the caller — the CLI command or Mac app model — and injected via `GH_TOKEN` env var before calling the use case, same as `ExecuteChainUseCase` does today)
- `Result` struct: `success: Bool`, `message: String`, `prURL: String?`, `prNumber: String?`, `taskDescription: String?`, `phasesCompleted: Int`
- `Progress` enum with cases for each phase (modeled after `ExecutePlanUseCase.Progress`, matching the original Python workflow's full step sequence):
  - `preparingProject` — loading config, checking capacity
  - `preparedTask(description: String, index: Int, total: Int)` — found task
  - `runningPreScript` — executing pre-action.sh
  - `preScriptCompleted(ActionResult)` — pre-script done (or skipped)
  - `runningAI(taskDescription: String)` — starting main AI execution
  - `aiStreamEvent(AIStreamEvent)` — streaming AI output (for UI)
  - `aiOutput(String)` — plain text AI output (for CLI)
  - `aiCompleted` — main AI task finished
  - `runningPostScript` — executing post-action.sh
  - `postScriptCompleted(ActionResult)` — post-script done (or skipped)
  - `finalizing` — committing, pushing, creating PR
  - `prCreated(prNumber: String, prURL: String)` — PR created successfully
  - `generatingSummary` — second AI call to analyze the PR diff
  - `summaryStreamEvent(AIStreamEvent)` — streaming summary AI output (for UI)
  - `summaryCompleted(summary: String)` — summary generated
  - `postingPRComment` — posting summary + cost breakdown as PR comment
  - `prCommentPosted` — comment posted
  - `completed(prURL: String?)` — all done
  - `failed(phase: String, error: String)` — a phase failed

**Implementation flow in `run(options:onProgress:)`:**

1. Load project from `claude-chain/{projectName}` directory using `ProjectRepository`
2. Load spec, find next available task using `TaskService` (reuse existing logic from `PrepareCommand`)
3. Create branch using `PRService.formatBranchName` + `GitOperations`
4. Emit `preparedTask` progress
5. Run pre-action script via `ScriptRunner` if it exists, emit progress
6. Build prompt (same as `PrepareCommand` step 6)
7. Call `client.run(prompt:options:onOutput:onStreamEvent:)` with the prompt, forwarding `onStreamEvent` as `aiStreamEvent` progress and `onOutput` as `aiOutput` progress. Set `workingDirectory` in `AIClientOptions` to `repoPath`.
8. Run post-action script via `ScriptRunner` if it exists, emit progress
9. Commit changes via `GitOperations` (reuse logic from `FinalizeCommand` step 1)
10. Push branch, create PR via `GitHubOperations` (reuse logic from `FinalizeCommand` step 2). Mark task complete in spec.md via `TaskService`. Emit `prCreated` progress.
11. **Generate PR summary** — build a summary prompt (same template as `PrepareSummaryCommand`) that asks AI to analyze the diff between the branch and base. Call `client.run()` with this prompt, streaming via `summaryStreamEvent`. The summary prompt should include the task description, PR number, and instruct Claude to review `git diff {baseBranch}...HEAD` and write a markdown summary. Use the existing summary prompt template from `src/claudechain/resources/prompts/summary_prompt.md` (port to a Swift string constant in `ClaudeChainService/Constants.swift` or load from a bundled resource).
12. **Post PR comment** — use the AI-generated summary + cost data (from `AIClientResult.cost`) to build a PR comment using `PullRequestCreatedReport` and `MarkdownReportFormatter` (already exist in `ClaudeChainService`). Post it via `GitHubOperations` (`gh pr comment`). Emit `prCommentPosted`.
13. Emit `completed` progress with PR URL

Use `CredentialResolver` for GitHub auth the same way `ExecuteChainUseCase` already does. Extract shared preparation logic (load project, find task, build prompt) into helper methods since `PrepareCommand` will still exist for the GitHub Actions flow.

Add `import AIOutputSDK` to `ClaudeChainFeature` target dependencies in `Package.swift` since it needs `AIClient` and `AIStreamEvent`.

## - [x] Phase 2: Add `run-task` CLI command

**Skills used**: `swift-architecture`
**Principles applied**: CLI command in Apps layer following existing patterns. Inline provider registry creation to avoid cross-app-layer dependency. Zero-flag auth via CredentialResolver auto-detection. Root command changed to AsyncParsableCommand to support async subcommands. Subcommand list sorted alphabetically per project conventions.

**Skills to read**: `swift-architecture`

Add a new `RunTaskCommand` to `ClaudeChainCLI` that is the single command for executing a chain task end-to-end. It should be easy to run with minimal flags — smart defaults handle auth and provider selection automatically.

```
claude-chain run-task --project <name>
```

**Arguments:**
- `--project` (required): project name within `claude-chain/` directory
- `--repo-path` (optional, defaults to current directory): path to the repository root
- `--provider` (optional): AI provider name to override the default
- `--github-account` (optional): credential account name to override auto-detection

**Zero-flag auth resolution** (follow existing patterns from `CLIRegistryFactory` and `CredentialResolver`):
- **GitHub token**: `CredentialResolver` already resolves automatically via its 3-tier chain: process env vars (`GITHUB_TOKEN` / `GH_TOKEN`) → `.env` file (searched upward from repo path) → macOS keychain. The account name defaults to `CredentialSettingsService().listCredentialAccounts().first ?? "default"`. No `--github-account` flag needed in the common case.
- **AI provider**: Use `ProviderRegistry.defaultClient` (first registered provider, typically `ClaudeProvider`). The `--provider` flag is only needed to override this. Follow the same pattern as `MarkdownPlannerExecuteCommand`: `provider.flatMap { registry.client(named: $0) } ?? registry.defaultClient!`
- **Repo path**: Defaults to current working directory, same as other CLI commands.

**Implementation:**
1. Build `ProviderRegistry` via `CLIRegistryFactory.makeProviderRegistry()` (already exists and handles Anthropic key resolution)
2. Resolve GitHub auth: create `CredentialResolver` with auto-detected account, call `getGitHubAuth()`, inject token via `setenv("GH_TOKEN", token, 1)` so child `gh` processes authenticate
3. Create and run `RunChainTaskUseCase` with an `onProgress` callback
4. The progress callback prints status updates to stdout (similar to how `MarkdownPlannerExecuteCommand.handleProgress` works):
   - Phase headers: `=== Phase: Preparing ===`, `=== Phase: AI Execution ===`, etc.
   - AI streaming output printed as it arrives
   - Script output printed
   - Final result with PR URL

Register `RunTaskCommand` in `ClaudeChainCLI.subcommands` (alphabetically).

The existing `prepare` and `finalize` commands remain unchanged for backward compatibility with the GitHub Actions workflow.

## - [x] Phase 3: Update `ExecuteChainUseCase` to use `RunChainTaskUseCase`

**Skills used**: `swift-architecture`
**Principles applied**: Delegated to `RunChainTaskUseCase` via composition rather than reimplementing. Re-exported `Progress` as typealias to avoid duplication. Updated `ClaudeChainModel` to accept `ProviderRegistry` following `MarkdownPlannerModel` pattern. Added `ChainTask` type and tasks list to `ListChainsUseCase`/`ChainProject` for Phase 5 UI needs.

**Skills to read**: `swift-architecture`

Refactor `ExecuteChainUseCase` to delegate to `RunChainTaskUseCase` instead of using `Process` directly. This ensures the Mac app model uses the same execution path.

**Changes:**
- Add `AIClient` as a required dependency of `ExecuteChainUseCase`
- Add a `Progress` enum to `ExecuteChainUseCase` (mirrors `RunChainTaskUseCase.Progress` or re-exports it)
- Add `onProgress` callback to the `run` method signature
- Internally create and delegate to `RunChainTaskUseCase`
- Update `ExecuteChainUseCase.Result` to include the additional fields from `RunChainTaskUseCase.Result`

Update `ListChainsUseCase` if needed to also return the tasks list (not just counts) so the Mac app can show individual tasks.

## - [x] Phase 4: Update `ClaudeChainModel` with streaming support

**Skills used**: `swift-swiftui`
**Principles applied**: Enum-based state machine following MarkdownPlannerModel pattern. ExecutionProgress struct with PhaseInfo tracks phase-by-phase status. executionProgressObserver callback bridges to ChatModel for streaming display. Provider switching via selectedProviderName. View updated minimally to handle new state cases (full redesign in Phase 5).

**Skills to read**: `swift-swiftui`

Rewrite `ClaudeChainModel` to support rich phase-by-phase execution with streaming AI output, following the same pattern as `MarkdownPlannerModel`.

**Updated state machine:**
```swift
enum State {
    case idle
    case loadingChains
    case loaded([ChainProject])
    case executing(progress: ExecutionProgress)
    case completed(result: ExecuteChainUseCase.Result)
    case error(Error)
}

struct ExecutionProgress {
    var currentPhase: String = ""
    var phases: [PhaseInfo] = []   // all phases with status
    var taskDescription: String = ""
    var taskIndex: Int = 0
    var totalTasks: Int = 0
}

struct PhaseInfo: Identifiable {
    let id: String            // e.g. "prepare", "preScript", "ai", "postScript", "finalize"
    let displayName: String
    var status: PhaseStatus   // pending, running, completed, failed, skipped
}
```

**New properties:**
- `executionProgressObserver: (@MainActor (RunChainTaskUseCase.Progress) -> Void)?` — bridge to ChatModel for streaming display (same pattern as `MarkdownPlannerModel`)
- Inject `AIClient` via `ProviderRegistry` (same as `MarkdownPlannerModel`)
- `selectedProviderName` with provider switching support

**Updated `executeChain` method:**
- Creates `ExecuteChainUseCase` with the active `AIClient`
- Passes `onProgress` callback that:
  - Updates `ExecutionProgress` state for phase transitions
  - Forwards to `executionProgressObserver` for ChatModel streaming

## - [x] Phase 5: Update `ClaudeChainView` with phase display and chat output

**Skills used**: `swift-swiftui`
**Principles applied**: Followed MarkdownPlannerDetailView pattern for VSplitView with ChatMessagesView. StreamAccumulator bridges aiStreamEvent/summaryStreamEvent to ChatModel for streaming display. Added lastLoadedProjects to model so project list persists during executing/completed states. Phase status icons use enum-based switching (pending/running/completed/failed/skipped). Task list shows in-progress indicator for currently executing task.

**Skills to read**: `swift-swiftui`

Redesign `ClaudeChainView` and `ChainProjectDetailView` to show phases and streaming AI output, following the `MarkdownPlannerDetailView` pattern.

**New `ChainProjectDetailView` layout:**

Top section (always visible):
- Project name, spec path, task progress (existing)
- Task list showing all tasks with status (completed/in-progress/pending)
- Phase progress during execution: list of phases with status indicators (checkmark, spinner, pending circle)
- "Run Next Task" button + provider picker (dropdown, same as planner)

Bottom section (appears during/after execution, using `VSplitView` like planner):
- `ChatMessagesView` showing streaming AI output
- Status messages inserted for each phase transition (e.g., "Running pre-action script...", "Creating PR...")

**Phase display during execution:**
Show all phases as a vertical list with icons:
- Pending: gray circle
- Running: blue spinner (ProgressView)
- Completed: green checkmark
- Failed: red X
- Skipped: gray dash

Phase list: Prepare → Pre-Script → AI Execution → Post-Script → Finalize/Create PR → PR Summary → Post PR Comment

**Streaming integration (same pattern as `MarkdownPlannerDetailView`):**
1. When execution starts, create a `ChatModel` for display
2. Set `model.executionProgressObserver` to relay progress to `ChatModel`:
   - Phase transitions → `chatModel.appendStatusMessage("Phase: ...")`
   - `aiStreamEvent` → `StreamAccumulator.apply()` → `chatModel.updateCurrentStreamingBlocks()` (main task AI)
   - `summaryStreamEvent` → same pattern but preceded by a status message "Generating PR summary..."
   - `prCreated` → `chatModel.appendStatusMessage("PR created: #N")`
   - `prCommentPosted` → `chatModel.appendStatusMessage("Summary posted to PR")`
   - Script output → `chatModel.appendStatusMessage()`
3. Show `ChatMessagesView(model: chatModel)` in the bottom panel

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: Used Swift Testing framework with @Test and #expect. Followed AAA pattern. Fixed pre-existing ClaudeChainModelTests compilation error (ExecutionProgress tuple mismatch from Phase 4 changes). Tests cover error paths (no spec, all tasks completed), progress emission through prepare/script/AI phases, and script-not-found behavior. Full end-to-end PR creation/summary/comment flow verified by code inspection (requires GitHub remote for integration testing).

**Skills to read**: `swift-testing`

1. Build all targets: `swift build`
2. Run existing ClaudeChain tests to verify no regressions:
   - `swift test --filter ClaudeChainServiceTests`
   - `swift test --filter ClaudeChainSDKTests`
   - `swift test --filter ClaudeChainFeatureTests`
   - `swift test --filter ClaudeChainCLITests`
3. Write tests for `RunChainTaskUseCase`:
   - Test progress emission sequence (prepare → preScript → ai → postScript → finalize → prCreated → summary → prComment → completed)
   - Test that a project with no pending tasks returns appropriate error
   - Test that pre/post scripts are skipped when not present (progress still emitted as `skipped`)
   - Test that PR summary generation and comment posting occur after PR creation
4. Verify the `run-task` CLI command exists and shows help: `swift run ClaudeChainMain run-task --help`
5. Verify no stale imports or unused code from the refactoring
6. Build the Mac app target to verify view compilation: `swift build --target AIDevToolsKitMac`
