## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | File paths, output structure, and CLI commands for the eval system |
| `swift-testing` | Test style guide and conventions |

## Background

After an eval run completes, the formatted streaming output (thinking, tool calls, results) is lost. During a run, `EvalRunnerModel.RunProgress.currentOutput` accumulates the formatted text and the UI displays it in a scrollable view — but once the run finishes, `currentOutput` is cleared and the "Last Run" section only shows `CaseResult.providerResponse` (the final response text).

The raw JSONL stdout IS already saved to disk at `{outputDir}/artifacts/raw/{caseId}.stdout`, and the stream formatters (`ClaudeStreamFormatter`/`CodexStreamFormatter`) already know how to convert that JSONL into human-readable text. We just need to:

1. Save the **formatted** output alongside the raw output (or re-format on demand)
2. Expose it in the UI using the same `outputSection` pattern used during streaming
3. Expose it via CLI through a shared use case

**Rubric evaluation output:** Rubric grading also runs through the provider adapter with `caseId: "{caseId}.rubric"`, so `ResultWriter` saves `{caseId}.rubric.stdout` to the raw directory. The rubric adapter call currently passes no `onOutput` callback (so rubric output is never streamed live), but the raw JSONL is still persisted to disk. The `ReadCaseOutputUseCase` should handle both the main run output and the rubric output.

## Phases

## - [x] Phase 1: Create `ReadCaseOutputUseCase` in EvalFeature

**Skills used**: `swift-architecture`
**Principles applied**: Extracted path construction and file I/O into `OutputService` (SDK layer) per service-layer conventions; consolidated `ResultWriter` into same service; use case is pure orchestration delegating to the service

Create a use case that reads raw stdout from disk and re-formats it through the appropriate stream formatter.

**Location:** `AIDevToolsKit/Sources/EvalFeature/ReadCaseOutputUseCase.swift`

**Interface:**
```swift
public struct ReadCaseOutputUseCase {
    public struct Options {
        let caseId: String        // e.g. "feature-flags.add-bool-flag-structured"
        let provider: Provider
        let outputDirectory: URL  // e.g. ~/Desktop/ai-dev-tools/sample-app/
    }

    public struct Output {
        let mainOutput: String     // Formatted output from the provider run
        let rubricOutput: String?  // Formatted output from rubric evaluation (if exists)
    }

    public func run(_ options: Options) throws -> Output
}
```

**Logic:**
1. Derive the raw stdout path: `{outputDirectory}/artifacts/raw/{caseId}.stdout`
2. Read the file contents
3. Determine the provider from `options.provider`
4. Pass each line through `ClaudeStreamFormatter` or `CodexStreamFormatter` (they're in `EvalSDK`)
5. Also check for `{caseId}.rubric.stdout` — if it exists, format it the same way
6. Return both as `Output`

**Note:** The formatters are in `EvalSDK`, so `EvalFeature` already depends on `EvalSDK`. The use case just needs to instantiate the right formatter based on provider. Rubric runs always use Claude (via the same adapter), so use `ClaudeStreamFormatter` for rubric output regardless of the original provider.

## - [x] Phase 2: Add `show-output` CLI subcommand

**Skills used**: `swift-architecture`
**Principles applied**: Followed existing command patterns (ClearArtifactsCommand) for path resolution and mutual exclusivity validation; reused ProviderChoice enum; delegated to ReadCaseOutputUseCase

Add a new `ShowOutputCommand` that uses `ReadCaseOutputUseCase` to print formatted output to the terminal.

**Location:** `AIDevToolsKit/Sources/AIDevToolsKitApp/ShowOutputCommand.swift`

**Usage:**
```bash
swift run ai-dev-tools-kit show-output --repo /path/to/repo --case-id feature-flags.add-bool-flag-structured --provider claude
```

**Implementation:**
- Accept `--repo` or `--output-dir`, `--case-id`, `--provider` options (same pattern as `RunEvalsCommand` for path resolution)
- Call `ReadCaseOutputUseCase.run(options)` and print `output.mainOutput` to stdout
- If `output.rubricOutput` is non-nil, print a separator header (e.g. `\n--- Rubric Evaluation ---\n`) followed by the rubric output
- Register in `EntryPoint.swift` subcommands array

## - [x] Phase 3: Display saved output in the Mac app UI

**Skills used**: `swift-architecture`
**Principles applied**: Reused `FormattedOutput` from SDK layer directly; lazy on-demand loading via DisclosureGroup; shared `outputTextView` helper matching live output style

Update `EvalResultsView` to show the formatted output for completed runs using the same `outputSection`-style view.

**Changes to `EvalRunnerModel`:**
- Add a method: `func loadCaseOutput(caseId: String, provider: String) throws -> String` that calls `ReadCaseOutputUseCase`
- This derives the qualified case ID and output directory from `evalConfig`

**Changes to `EvalResultsView`:**
- In the `lastRunSection` (around line 430), for each provider entry, add an expandable output section below the existing `providerResponse`
- Use a `DisclosureGroup` or similar pattern so the output loads on-demand (not all at once for every case)
- Reuse the same visual style as the live `outputSection`: monospaced caption font, 150px scrollable area, text selection enabled
- Load the output lazily when the user expands it (call the model method to read from disk)
- If rubric output exists, show a second expandable section labeled "Rubric Evaluation Output" below the main output

**Key detail:** The existing `outputSection` takes a `RunProgress` and reads `progress.currentOutput`. For the completed state, create a similar view that takes a plain `String` instead — or extract a shared `OutputTextView` that both the live and historical paths use.

## - [x] Phase 4: Validation

**Skills used**: `swift-testing`
**Principles applied**: Verified build, ran tests (pre-existing failures unrelated to changes), validated CLI show-output command with real eval artifacts

- Build the Swift package to verify compilation: `cd AIDevToolsKit && swift build`
- Run existing tests: `swift test`
- Manual verification:
  1. Run an eval from CLI: `swift run ai-dev-tools-kit run-evals --repo /path/to/sample-app --case-id add-bool-flag-structured --provider codex`
  2. After completion, run: `swift run ai-dev-tools-kit show-output --repo /path/to/sample-app --case-id feature-flags.add-bool-flag-structured --provider codex`
  3. Verify the CLI output matches what was seen during the streaming run
  4. Open the Mac app, expand a completed case, verify the output section appears with formatted content
