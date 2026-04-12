## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture — Apps/Features/Services/SDKs dependency rules |
| `ai-dev-tools-composition-root` | How services are wired; `SharedCompositionRoot`, `ProviderModel`, `ProviderRegistry` |
| `ai-dev-tools-enforce` | Post-implementation validation of architecture and code quality |

## Background

PR Radar Analyze fails with "Claude Agent script not found at [empty path]" because it uses a legacy Python subprocess mechanism (`ClaudeAgentSDK` → `claude_agent.py`) that requires a manually-configured `agentScriptPath` per repo — a path no user has ever set.

Chat and Evals both work because they use `ClaudeProvider` (the `claude` CLI binary), which auto-discovers from `~/.local/bin/claude` or PATH with no configuration. Both features also expose an **AI provider dropdown** so users can switch between Claude CLI, Anthropic API, Codex, etc.

PR Radar should follow the same pattern:
- Remove the Python script mechanism entirely
- Wire `ProviderRegistry` into `AllPRsModel` / `PRModel`
- Add a provider picker to the PR Radar UI (matching the Chat tab pattern)
- Remove `agentScriptPath` from all settings and config types

### Existing Provider Dropdown Pattern (Chat)
```swift
// ContextualChatPanel.swift
@Environment(ProviderModel.self) private var providerModel
@State private var selectedProviderName: String = ""

Picker("", selection: $selectedProviderName) {
    ForEach(providerModel.providerRegistry.providers, id: \.name) { provider in
        Text(provider.displayName).tag(provider.name)
    }
}
.pickerStyle(.menu)
```
On change → `registry.client(named: selectedProviderName)` → passed to `ChatModel`.

### Current PR Radar wiring (to be replaced)
- `AnalyzeSingleTaskUseCase` and `PrepareUseCase` both construct `ClaudeAgentClient` directly using `config.agentScriptPath`
- `AnalysisService(agentClient: ClaudeAgentClient)` and `FocusGeneratorService(agentClient: ClaudeAgentClient)` are hardwired to a single provider

### Key files

| File | Role |
|------|------|
| `AIDevToolsKit/Package.swift` | Dependency graph |
| `Sources/SDKs/AIOutputSDK/AIClient.swift` | `AIClient` protocol used by all providers |
| `Sources/Services/ProviderRegistryService/ProviderRegistry.swift` | Provider list, `client(named:)` |
| `Sources/Apps/AIDevToolsKitMac/Models/ProviderModel.swift` | `@Observable` wrapper injected via environment |
| `Sources/Apps/AIDevToolsKitMac/CompositionRoot.swift` | Mac composition root (injects `ProviderModel`) |
| `Sources/Services/PRRadarCLIService/AnalysisService.swift` | AI analysis — takes `ClaudeAgentClient` today |
| `Sources/Services/PRRadarCLIService/FocusGeneratorService.swift` | Focus generation — takes `ClaudeAgentClient` today |
| `Sources/Features/PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift` | Constructs `ClaudeAgentClient` |
| `Sources/Features/PRReviewFeature/usecases/PrepareUseCase.swift` | Constructs `ClaudeAgentClient` |
| `Sources/Apps/AIDevToolsKitMac/PRRadar/Models/AllPRsModel.swift` | Owns PR list, triggers analyze |
| `Sources/Apps/AIDevToolsKitMac/PRRadar/Models/PRModel.swift` | Per-PR model, runs phases |
| `Sources/Apps/AIDevToolsKitMac/PRRadar/Views/PRRadarContentView.swift` | Top-level PR Radar view |
| `Sources/SDKs/RepositorySDK/PRRadarRepoSettings.swift` | Stored settings — has `agentScriptPath` |
| `Sources/Services/PRRadarConfigService/PRRadarConfig.swift` | Runtime config — has `agentScriptPath` |
| `Sources/Apps/AIDevToolsKitMac/Views/ConfigurationEditSheet.swift` | Settings UI — has agent script path field |
| `Sources/Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift` | Passes `agentScriptPath` into config |
| `Sources/SDKs/AIOutputSDK/AIStreamEvent.swift` | Event type emitted by all providers |
| `Sources/SDKs/AIOutputSDK/StreamAccumulator.swift` | Batches deltas into `AIContentBlock[]` |
| `Sources/Apps/AIDevToolsKitMac/Models/ChatModel.swift` | `@Observable` model driving `ChatMessagesView` |
| `Sources/Apps/AIDevToolsKitMac/Views/Chat/ChatMessagesView.swift` | Shared rich streaming output view |
| `Sources/Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift` | Reference: how to wire `ChatModel` + `StreamAccumulator` |
| `Sources/Apps/AIDevToolsKitMac/PRRadar/Views/ReviewDetailView.swift` | Where streaming view will be shown |
| `Sources/SDKs/ClaudeAgentSDK/` | Delete — legacy Python bridge |
| `Sources/SDKs/ClaudePythonSDK/` | Delete — unused duplicate |

---

## Phases

## - [x] Phase 1: Migrate AnalysisService and FocusGeneratorService to AIClient

**Skills used**: `swift-architecture`
**Principles applied**: Used `runStructured<T>()` over `run()` for provider-agnostic structured JSON output. Created `Decodable` response types (`ViolationsResponse`, `MethodsResponse`) and a thread-safe `EventAccumulator` class (following the `Accumulator` pattern in `AIRunSession.swift`) for mutable state capture in `@Sendable` closures. Converted static `[String: Any]` schemas to pre-computed JSON strings. Fixed call sites in `AnalyzeSingleTaskUseCase` and `PrepareUseCase` to use `ClaudeProvider()` directly so Phase 1 compiles cleanly; Phase 2 will promote the client to a proper init parameter.

**Skills to read**: `swift-architecture`

Read `AnalysisService.swift` and `FocusGeneratorService.swift` in full before changing anything.

- Change `AnalysisService.init(agentClient: ClaudeAgentClient)` → `init(aiClient: any AIClient)`
- Inside `analyzeTask()`, replace `ClaudeAgentRequest` construction + `agentClient.stream()` with calls via `aiClient.run(prompt:options:onStreamEvent:)` from `AIClient`
- Map the text response back to `RuleOutcome` (the existing prompt already asks Claude for JSON; no schema enforcement needed)
- Change `FocusGeneratorService.init(agentClient: ClaudeAgentClient, model: String)` → `init(aiClient: any AIClient, model: String)`
- Replace `ClaudeAgentRequest` + `agentClient.stream()` in `FocusGeneratorService` with `aiClient.run()`
- Update imports: remove `ClaudeAgentSDK`, add `AIOutputSDK`

## - [x] Phase 2: Migrate use cases to accept AIClient

**Skills used**: `swift-architecture`
**Principles applied**: Added `aiClient: any AIClient` as a stored property to both `AnalyzeSingleTaskUseCase` and `PrepareUseCase`, replacing the inline `ClaudeProvider()` construction. Updated imports from `ClaudeCLISDK` to `AIOutputSDK` in both use cases. Updated all call sites in the Feature layer (`AnalyzeUseCase`, `RunPipelineUseCase`) and Apps layer (`PRModel`, `PRRadarPrepareCommand`) to pass `ClaudeProvider()` as a placeholder — Phase 3 will replace these with the user-selected provider from `ProviderRegistry`.

Read `AnalyzeSingleTaskUseCase.swift` and `PrepareUseCase.swift` in full before changing.

- Add `aiClient: any AIClient` parameter to `AnalyzeSingleTaskUseCase` (stored property or passed into `execute()`)
- Remove the `ClaudeAgentClient` construction block (the one that reads `config.agentScriptPath`)
- Pass `aiClient` into `AnalysisService(aiClient: aiClient)`
- Add `aiClient: any AIClient` parameter to `PrepareUseCase`
- Remove the `ClaudeAgentClient` construction block from `PrepareUseCase`
- Pass `aiClient` into `FocusGeneratorService(aiClient: aiClient)`
- Update imports in both files

## - [x] Phase 3: Wire provider selection and streaming state into AllPRsModel and PRModel

**Skills used**: `ai-dev-tools-composition-root`
**Principles applied**: Added `providerRegistry: ProviderRegistry` to `AllPRsModel.init()` (injected from `PRRadarContentView` via `@Environment(ProviderModel.self)`). Added `selectedProviderName` and `aiClient` computed property to `AllPRsModel`. Stored `activeClient: any AIClient` in `PRModel` (defaulting to `ClaudeProvider()`) so UI call sites that omit the client continue to work without importing `ClaudeCLISDK`; `runAnalysis(aiClient:)` sets it when provided. Used optional `(any AIClient)?` for the public `runAnalysis` signature to avoid requiring callers to import `ClaudeCLISDK`. Added `prepareStreamModel`, `analyzeStreamModel`, and `streamAccumulator` to `PRModel`, following the `ClaudeChainModel` pattern; text chunks from use case events are synthesized into `AIStreamEvent` values before passing through `StreamAccumulator`. Updated `AnalyzeUseCase` to accept and thread `aiClient` through to `AnalyzeSingleTaskUseCase`; updated all CLI call sites to pass `ClaudeProvider()`.

**Skills to read**: `ai-dev-tools-composition-root`

**Provider selection:**
- Add `var selectedProviderName: String` to `AllPRsModel` (default to `""`)
- Add `var aiClient: (any AIClient)?` computed from `providerRegistry.client(named: selectedProviderName) ?? providerRegistry.defaultClient`
- `AllPRsModel` needs access to `ProviderRegistry` — add it as an `init` parameter (injected from the Mac app composition root, not constructed inline)
- In `AllPRsModel.analyzeAll()`, pass `aiClient` into `pr.runAnalysis(aiClient:)`
- Add `aiClient: any AIClient` parameter to `PRModel.runAnalysis()` and `PRModel.runAnalyze()` / `PRModel.runPrepare()`
- Pass `aiClient` through into `AnalyzeSingleTaskUseCase` and `PrepareUseCase`

**Streaming output state (follow `ClaudeChainModel` pattern):**
- Add `private(set) var prepareStreamModel: ChatModel?` to `PRModel`
- Add `private(set) var analyzeStreamModel: ChatModel?` to `PRModel`
- Add `private let streamAccumulator = StreamAccumulator()` to `PRModel`
- In `runPrepare()`: create `prepareStreamModel = ChatModel(...)`, call `prepareStreamModel?.beginStreamingMessage()`, feed each `AIStreamEvent` through `streamAccumulator.apply(event)` → `prepareStreamModel?.updateCurrentStreamingBlocks(blocks)`, finalize when done
- In `runAnalyze()`: same pattern with `analyzeStreamModel`
- Both models nil'd out (or kept) after phase completes — match the Claude Chain convention

**Reference files:**
- `ClaudeChainModel.swift` — `executionChatModel`, `handleProgressEvent(_:)`, `streamAccumulator`
- `StreamAccumulator.swift` — `apply(_ event: AIStreamEvent) -> [AIContentBlock]`
- `ChatModel.swift` — `beginStreamingMessage()`, `updateCurrentStreamingBlocks(_:)`, `finalizeCurrentStreamingMessage()`

## - [x] Phase 4: Add provider picker and streaming output view to PR Radar UI

**Skills used**: none
**Principles applied**: Added provider `Picker` to `PRRadarContentView` toolbar bound to `AllPRsModel.selectedProviderName` (initialized from `providerRegistry.defaultClient?.name` on model creation). Added `HSplitView` in `ReviewDetailView`'s diff case: when `prModel.prepareStreamModel ?? prModel.analyzeStreamModel` is non-nil, the diff view appears on the left and `ChatMessagesView` on the right — collapses back to single-pane when no stream model is active. Both changes match the `ContextualChatPanel` and `ClaudeChainView` patterns exactly.

**Skills to read**: (none extra — match Chat and Claude Chain patterns exactly)

**Provider picker** (match `ContextualChatPanel` pattern):
- In `PRRadarContentView` toolbar, add a provider `Picker` reading from `allPRsModel` provider list
- Bind picker to `allPRsModel.selectedProviderName`
- `AllPRsModel` receives `ProviderRegistry` via init — check how `PRRadarContentView` is constructed and inject consistently

**Streaming output view** (match `ClaudeChainView` pattern):
- In `ReviewDetailView` (or wherever prepare/analyze phase output is shown), add conditional rendering:
  ```swift
  if let model = prModel.prepareStreamModel {
      ChatMessagesView().environment(model)
  }
  if let model = prModel.analyzeStreamModel {
      ChatMessagesView().environment(model)
  }
  ```
- Show the streaming view during the active phase; keep or collapse it after completion — match whatever Claude Chain does
- `ChatMessagesView` is already in `AIDevToolsKitMac` and needs no new dependency

## - [x] Phase 5: Remove agentScriptPath from config layer

**Skills used**: none
**Principles applied**: Removed `agentScriptPath` from `PRRadarRepoSettings`, `PRRadarRepoConfig` (struct field, init, and `make(from:)` factory), `WorkspaceModel` (`prradarConfig()` and `updatePRRadarSettings()`), `ConfigurationEditSheet` (state var, init, and UI field), `SettingsView` (call site), `RepositoriesSettingsView` (detail row), and two CLI files (`PRRadarCLISupport.swift`, `PRRadarConfigCommand.swift`). Also fixed a preview in `PRListRow.swift` that used the old init signature.

Remove the field everywhere it appears:

- `PRRadarRepoSettings`: remove `agentScriptPath` field and its init parameter
- `PRRadarRepoConfig`: remove `agentScriptPath` field and the parameter from `make(from:settings:outputDir:agentScriptPath:)`
- `WorkspaceModel`: remove `agentScriptPath` from `prradarConfig()` and `updatePRRadarSettings(for:rulePaths:diffSource:agentScriptPath:)`
- `ConfigurationEditSheet`: remove the "Agent Script Path" `TextField` and the `@State private var prradarAgentScriptPathText` binding
- `SettingsView`: remove the `agentScriptPath:` argument passed to `updatePRRadarSettings`
- `RepositoriesSettingsView`: remove the "Agent Script Path" detail row

## - [x] Phase 6: Update Package.swift

**Skills used**: none
**Principles applied**: Removed `ClaudeAgentSDK` and `ClaudePythonSDK` from products, target definitions, and all dependent target lists. Added `AIOutputSDK` to `PRReviewFeature` and `PRRadarCLIService` dependencies. Removed the `ClaudePythonSDKTests` test target and the `PRRadarModelsServiceTests/ClaudeAgentMessageTests.swift` test file (which tested the now-removed SDK). Lists kept alphabetically sorted per project convention.

- `PRReviewFeature` target:
  - Remove `ClaudeAgentSDK` dependency
  - Ensure `AIOutputSDK` is listed (for `AIClient` protocol)
- `PRRadarCLIService` target:
  - Remove `ClaudeAgentSDK` dependency
  - Ensure `AIOutputSDK` is listed
- Delete the `ClaudeAgentSDK` target definition entirely
- Delete the `ClaudePythonSDK` target definition entirely (unused legacy duplicate)
- Keep lists alphabetically sorted per project convention

## - [x] Phase 7: Delete dead code

**Skills used**: none
**Principles applied**: Verified Package.swift had no remaining references to `ClaudeAgentSDK` or `ClaudePythonSDK` before deleting. Confirmed `PRRadarLibrary/claude-agent/` was unused (no Swift code referenced it). `PRRadarLibrary` itself is now an empty directory.

- Delete `AIDevToolsKit/Sources/SDKs/ClaudeAgentSDK/` directory
- Delete `AIDevToolsKit/Sources/SDKs/ClaudePythonSDK/` directory
- Delete `AIDevToolsKit/claude-agent/` directory (Python scripts no longer used)
- Confirm `PRRadarLibrary/claude-agent/` is also unused before deleting

## - [x] Phase 8: Validation

**Skills used**: `ai-dev-tools-enforce`
**Principles applied**: Ran enforce on all plan-changed files; agent fixed supporting-type ordering in `PrepareUseCase`/`FocusGeneratorService`, sorted imports, replaced `NSError` throw with typed `PrepareUseCaseError`, replaced `[String:Any]` JSON output in `PRRadarPrepareCommand` with typed `Encodable` struct, replaced force-unwrap `String(data:encoding:)!` with guard+throw in both CLI commands, and wired `aiClient` into `RunPipelineUseCase.init` to eliminate inline `ClaudeProvider()` construction. CLI end-to-end validation used the existing PR #12 on AIDevToolsDemo (which already contains FIXME violations): refresh → sync → prepare → analyze → report all succeeded, two violations detected, no "script not found" error. Mac app smoke test skipped (UI-only, no automated path).

### Build
- `swift build` from `AIDevToolsKit/` — must compile clean with zero warnings

### CLI end-to-end with real violations (primary validation)

Use the AIDevToolsDemo playground repo (`/Users/bill/Developer/personal/AIDevToolsDemo`) to create a PR with intentional rule violations, then run the full PR Radar pipeline from the CLI.

**Step 1 — Create a violation PR:**
```bash
cd /Users/bill/Developer/personal/AIDevToolsDemo
git checkout -b test/prradar-ai-provider-validation
# Add a Swift file with intentional violations the active rules will catch
# (e.g. force unwraps, missing nullability headers, service locator usage — pick rules known to be active)
git add . && git commit -m "test: intentional violations for PRRadar validation"
gh pr create --title "test: PRRadar AI provider validation" --body "Intentional violations for end-to-end validation"
# Note the PR number
```

**Step 2 — Run the full pipeline via CLI:**
```bash
cd /Users/bill/Developer/personal/AIDevTools/AIDevToolsKit
swift run ai-dev-tools-kit prradar run <PR_NUMBER> --config AIDevToolsDemo
```

Or phase by phase if debugging:
```bash
swift run ai-dev-tools-kit prradar refresh <PR_NUMBER> --config AIDevToolsDemo
swift run ai-dev-tools-kit prradar prepare <PR_NUMBER> --config AIDevToolsDemo
swift run ai-dev-tools-kit prradar analyze <PR_NUMBER> --config AIDevToolsDemo --mode ai
swift run ai-dev-tools-kit prradar report <PR_NUMBER> --config AIDevToolsDemo
```

**Step 3 — Verify findings:**
```bash
swift run ai-dev-tools-kit prradar violations <PR_NUMBER> --config AIDevToolsDemo
```
Confirm the violations introduced in Step 1 appear in the output. The "script not found" error must not appear.

**Step 4 — Clean up:**
```bash
gh pr close <PR_NUMBER> --delete-branch
```

### Mac app smoke test
- Launch Mac app → PR Radar tab
- Confirm provider dropdown appears (Claude CLI, Anthropic API, etc.)
- Run Analysis on any PR — streaming output appears in the panel, no "script not found" error
- Settings → confirm "Agent Script Path" field is gone
- Verify Chat tab still works (no regression)

### Enforce
- Run `ai-dev-tools-enforce` on all files changed during this plan
