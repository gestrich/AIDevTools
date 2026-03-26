## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `ai-dev-tools-debug` | File paths, CLI commands, and artifact structure for AIDevTools |

## Background

The previous spec (`2026-03-25-a-unified-ai-output-storage`) created `AIOutputStore` (a key-value file store) and a shared `OutputPanel` view. However, clients still manually wire up storage: the eval `ClaudeAdapter` calls `outputService.write()` after execution, and the architecture planner calls `aiOutputStore.write()` after each step. Both features also independently accumulate output strings during streaming callbacks.

The goal is to push output persistence INTO the AI prompting layer so that:
1. Clients start a "run session" and get back a streaming interface — persistence happens transparently
2. The same interface works for both live streaming (in-progress) and historical retrieval (completed)
3. `OutputPanel` consumes this interface without knowing whether the output is live or stored
4. New AI-running features get auto-persistence for free by using the session

### Current patterns being replaced

**Eval (ClaudeAdapter):**
```
claudeClient.run(onOutput: { onOutput($0) })  // callback for live UI
→ execution completes, returns stdout string
→ outputService.write(stdout: stdout, ...)     // manual persistence
```

**Architecture Planner (ExecuteImplementationUseCase):**
```
claudeClient.runStructured(onFormattedOutput: { onOutput($0) })  // callback for live UI
→ execution completes
→ aiOutputStore.write(output: currentOutput, key: key)           // manual persistence
```

**Target pattern:**
```
let session = AIRunSession(key: "eval/claude/my-case", store: outputStore)
try await session.run(onOutput: { chunk in /* live UI */ }) { handler in
    try await claudeClient.run(command: cmd, onFormattedOutput: handler)
}
// output is auto-persisted — no manual write call needed

// Later, historical retrieval:
let previousOutput = session.loadOutput()  // String? from store
```

## Phases

## - [x] Phase 1: Create `AIRunSession` in `AIOutputSDK`

**Skills to read**: `swift-architecture`

Extend the existing `AIOutputSDK` module with `AIRunSession` — a lightweight struct that wraps AI execution with automatic output persistence. It does NOT depend on `ClaudeCLISDK` or any specific AI provider — it's provider-agnostic, working through a closure-based execution pattern.

### API Design

```swift
/// A session that automatically persists AI output during execution.
/// Wraps any AI execution that produces streaming text output.
public struct AIRunSession: Sendable {
    public let key: String
    public let store: AIOutputStore

    public init(key: String, store: AIOutputStore)

    /// Execute work that produces streaming output, automatically persisting the result.
    ///
    /// - `onOutput`: Called with each output chunk for live UI updates
    /// - `work`: Closure that receives an output handler to pass to the AI client.
    ///           All text sent to the handler is accumulated and persisted on completion.
    ///
    /// The accumulated output is written to the store when `work` completes (success or failure).
    /// On failure, partial output is still persisted (valuable for debugging).
    @discardableResult
    public func run(
        onOutput: (@Sendable (String) -> Void)? = nil,
        work: @Sendable (_ outputHandler: @Sendable (String) -> Void) async throws -> Void
    ) async throws -> String

    /// Load previously stored output for this session.
    public func loadOutput() -> String?

    /// Delete stored output for this session.
    public func deleteOutput() throws
}
```

### Behavior

- The `run()` method creates an internal accumulator. Each chunk sent to `outputHandler` is:
  1. Appended to the accumulator (thread-safe via `Mutex` or `OSAllocatedUnfairLock`)
  2. Forwarded to `onOutput` (if provided) for live UI display
- When `work` completes (or throws), the accumulated text is written to the store via `AIOutputStore.write(output:key:)`
- `run()` returns the full accumulated output string (useful for callers that need it inline)
- `loadOutput()` delegates to `AIOutputStore.read(key:)`
- `deleteOutput()` delegates to `AIOutputStore.delete(key:)`

### Thread safety

The accumulator must be `Sendable` since `outputHandler` is marked `@Sendable`. Use `Mutex<String>` (Foundation) or `OSAllocatedUnfairLock` to protect the accumulated string.

### Tasks

- Add `AIRunSession` struct to `AIOutputSDK`
- Add internal `OutputAccumulator` (Sendable, thread-safe string accumulator) — or inline the lock in `AIRunSession.run()`
- Unit tests:
  - `run()` accumulates output and persists to store
  - `run()` forwards chunks to `onOutput` callback
  - `run()` persists partial output on failure (work throws)
  - `loadOutput()` returns persisted output after `run()` completes
  - `loadOutput()` returns `nil` for unknown key
  - `deleteOutput()` removes stored output
  - `run()` return value matches accumulated output

## - [x] Phase 2: Migrate eval `ClaudeAdapter` to use `AIRunSession`

**Skills to read**: `swift-architecture`, `ai-dev-tools-debug`

Replace the manual output persistence in `ClaudeAdapter` with `AIRunSession`. The adapter currently:
1. Calls `claudeClient.run(onOutput:)` with a callback
2. Gets back `ExecutionResult` with complete `stdout`/`stderr`
3. Calls `outputService.write(result:stdout:stderr:configuration:)` to persist

After this phase, the raw stdout persistence moves into `AIRunSession.run()`. `OutputService` retains responsibility for:
- Structured JSON output (eval-specific grading artifacts)
- Stderr persistence (separate from stdout — keep using `AIOutputStore` directly for stderr, or add a second session)
- Summary files

### Tasks

- Update `ClaudeAdapter.run()` to create an `AIRunSession` with key `"<provider>/<caseId>"`
- Wrap the `claudeClient.run()` call inside `session.run(onOutput:work:)`
- Remove the manual `outputService.write()` call for raw stdout — the session handles it
- Keep stderr persistence in `OutputService` (or create a separate `AIRunSession` for stderr if cleaner)
- Keep structured JSON writing in `OutputService` — it's eval-specific
- Update `OutputService` to remove raw stdout write logic (now handled by session), keeping only structured output and stderr
- Update `ProviderResult.rawStdoutPath` — set it from `session.store.url(for: key)` instead of from `OutputService`
- Run eval CLI commands to verify no regression in artifact output

## - [x] Phase 3: Migrate Architecture Planner to use `AIRunSession`

**Skills to read**: `swift-architecture`

Replace the manual `AIOutputStore.write()` call in `ExecuteImplementationUseCase` with `AIRunSession`.

Currently the use case:
1. Calls `claudeClient.runStructured(onFormattedOutput:)` with a callback that forwards to `onOutput`
2. After completion, manually writes `currentOutput` to `AIOutputStore`

### Tasks

- Update `ExecuteImplementationUseCase.run()` to create an `AIRunSession` with key `"<jobId>/<stepIndex>"`
- Wrap the `claudeClient.runStructured()` call inside `session.run(onOutput:work:)`
- Remove the manual `aiOutputStore.write()` call — session handles it
- For loading historical output in the detail view, use `AIRunSession(key:store:).loadOutput()` instead of `AIOutputStore.read(key:)` directly
- Verify the architecture planner UI still streams live output and loads historical output correctly

## - [x] Phase 4: Update `OutputPanel` to accept session-based loading

**Skills to read**: `swift-architecture`

Currently `OutputPanel` takes a raw `String` for display. Update it to also support loading from an `AIRunSession`, so the view doesn't need to manage storage calls.

### Design

The `OutputPanel` already takes a `text: String` binding. The session integration happens in the `@Observable` models at the Apps layer, not in the view itself. This phase is about making the models use sessions consistently.

### Tasks

- In the eval Mac app model (`EvalRunnerModel` or similar), when showing case output:
  - For completed cases: use `AIRunSession(key:store:).loadOutput()` to get the text
  - Remove any direct `AIOutputStore.read()` or `OutputService.readFormattedOutput()` calls for raw output
- In the architecture planner Mac app model:
  - For completed steps: use `AIRunSession(key:store:).loadOutput()` to get the text
  - For in-progress steps: the live `onOutput` callback feeds the model's text property (unchanged)
  - Remove direct `AIOutputStore.read()` calls
- Verify both features' output panels display correctly for live and historical output

## - [x] Phase 5: Validation

**Skills to read**: `swift-testing`

### Automated tests

- `AIRunSession` unit tests (from Phase 1): run/persist round-trip, partial output on failure, thread safety
- Existing `OutputService` tests still pass after refactor
- Existing `AIOutputStore` tests still pass

### Manual verification

- Run an eval via CLI (`swift run ai-dev-tools-kit run-evals ...`) — confirm artifacts written correctly, raw stdout at expected path
- Open Mac app → run eval → verify live streaming in OutputPanel → close and reopen → verify historical output loads
- Open Mac app → run architecture planner step → verify live streaming → close and reopen → verify historical output loads
- Build both Mac app and CLI with no compile errors
