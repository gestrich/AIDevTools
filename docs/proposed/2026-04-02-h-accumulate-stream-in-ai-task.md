## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture reference — validates that moving accumulation into PipelineSDK stays within the correct layer |
| `ai-dev-tools-review` | Reviews Swift files for architecture conformance — use during validation |

## Background

After the Plans tab was migrated to `PipelineSDK`, AI stream events travel through a long callback chain before reaching `ChatModel` for rendering. Thinking blocks (purple boxes in the UI) broke because `ChatModel.consumeStream` — which uses `StreamAccumulator` to convert `AIStreamEvent`s into structured `[AIContentBlock]` — was no longer in the path.

The fix that was applied reconstructed an `AsyncStream<AIStreamEvent>` in the view layer using a `StreamContinuationHolder` class and `AsyncStream.Continuation`, so events could be piped back to `consumeStream`. This works but is needlessly complex: the view is rebuilding a stream just to feed the accumulator that should have been downstream of `AITask` in the first place.

The root cause: `AITask` executes the AI stream but doesn't accumulate it. The accumulation belongs in `AITask` — it owns the stream and already has access to `AIOutputSDK` (where `StreamAccumulator` lives). Moving accumulation there eliminates the entire bridge in the view.

The only blocker is that `StreamAccumulator` is currently an `actor` (making `apply` async), which can't be called synchronously in `AITask`'s `onStreamEvent` callback. Changing it to a `final class` with `NSLock` — the same pattern already used by `TextBox` and `MetricsBox` inside `AITask` — resolves this cleanly.

## Phases

## - [x] Phase 1: Change `StreamAccumulator` from actor to class

**Skills used**: `swift-architecture`
**Principles applied**: Changed `public actor` to `public final class: @unchecked Sendable`, added `NSLock` to protect `blocks` mutation in `reset()` and `apply(_:)`, matching the `TextBox`/`MetricsBox` pattern already in `AITask.swift`. Methods are now synchronous.

**Skills to read**: `swift-architecture`

Change `StreamAccumulator` in `Sources/SDKs/AIOutputSDK/StreamAccumulator.swift` from `public actor` to `public final class: @unchecked Sendable`. Replace actor isolation with `NSLock` on the `blocks` array, matching the `TextBox`/`MetricsBox` pattern in `AITask.swift`.

- `reset()` and `apply(_:)` become synchronous (no `async`, no `await` at call sites)
- All existing logic inside each method stays identical — only the isolation mechanism changes
- `public private(set) var blocks` becomes a regular stored property (lock-protected)

## - [x] Phase 2: Replace `.streamEvent` with `.contentBlocks` in `PipelineNodeProgress`

**Skills used**: `swift-architecture`
**Principles applied**: Changed `PipelineNodeProgress.streamEvent(AIStreamEvent)` to `.contentBlocks([AIContentBlock])` — `AIContentBlock` is already available via the existing `AIOutputSDK` import so no new dependency needed. Updated all three `PipelineNodeProgress` callers (`AITask.swift`, `MarkdownPlannerDetailView.swift`, `ClaudeChainModel.swift`) with placeholder `.contentBlocks` handling so the build succeeds; Phase 3 will add real accumulation in `AITask` and Phase 4 will wire the view.

**Skills to read**: `swift-architecture`

In `Sources/SDKs/PipelineSDK/PipelineNode.swift`, replace:
```swift
case streamEvent(AIStreamEvent)
```
with:
```swift
case contentBlocks([AIContentBlock])
```

`AIContentBlock` is in `AIOutputSDK` which `PipelineSDK` already imports — no new dependency.

## - [x] Phase 3: Accumulate in `AITask` and emit `.contentBlocks`

**Skills used**: `swift-architecture`
**Principles applied**: Created `StreamAccumulator()` at the top of `run()` (one accumulator per task invocation). In both `onStreamEvent` closures (structured and unstructured branches), replaced `onProgress(.contentBlocks([]))` with `let blocks = accumulator.apply(event); onProgress(.contentBlocks(blocks))`. The `metricsBox` is retained for populating the return-value context. `textBox.append(text)` in `onOutput` is unchanged — it exists solely for accumulating the final `Output` return value, not for streaming UI.

**Skills to read**: `swift-architecture`

In `Sources/SDKs/PipelineSDK/AITask.swift`:

- Create a `StreamAccumulator()` at the top of `run()`
- In `onStreamEvent`, call `accumulator.apply(event)` synchronously and emit `onProgress(.contentBlocks(blocks))`
- Remove `onProgress(.output(text))` from the `onOutput` closure (keep `textBox.append(text)` for return-value accumulation)
- Apply the same change to both branches of the `if let schema = jsonSchema` block

Result: every `AIStreamEvent` (including `.thinking`) becomes a `.contentBlocks` progress update carrying the full accumulated block state.

## - [x] Phase 4: Simplify `MarkdownPlannerDetailView`

**Skills used**: `swift-architecture`
**Principles applied**: Removed `StreamContinuationHolder`, `continuationHolder` state, and the `AsyncStream`/`consumeStream` bridge from `startExecution()`. Replaced the no-op `.nodeProgress` handler with a direct call to `executionModel.updateCurrentStreamingBlocks(blocks)`. Removed continuation cleanup from `handleExecutionComplete()`. The view now receives pre-accumulated `[AIContentBlock]` directly from `AITask` via `.contentBlocks`.

**Skills to read**: `swift-architecture`

In `Sources/Apps/AIDevToolsKitMac/Views/MarkdownPlannerDetailView.swift`, remove entirely:
- The `private final class StreamContinuationHolder` definition
- `@State private var continuationHolder`
- The `AsyncStream<AIStreamEvent>.makeStream()` call and `Task { await consumeStream(...) }` in `startExecution()`
- Continuation `finish()` / nil-out in `.nodeStarted`, `.nodeCompleted`, and `handleExecutionComplete()`

Replace the `onEvent` handler's progress case with a direct call:
```swift
case .nodeProgress(_, let progress):
    if case .contentBlocks(let blocks) = progress {
        executionModel.updateCurrentStreamingBlocks(blocks)
    }
```

`.nodeStarted` and `.nodeCompleted` keep their `finalizeCurrentStreamingMessage` / `beginStreamingMessage` calls unchanged.

## - [x] Phase 5: Fix remaining `StreamAccumulator` callers

**Skills used**: none
**Principles applied**: Removed `await` and wrapping `Task {}` from all `StreamAccumulator` call sites in `ChatModel.swift` and `ClaudeChainView.swift`. Since `apply` and `reset` are now synchronous, the calls inline directly — no async dispatch needed.

Remove `await` from all `StreamAccumulator` call sites now that `apply` and `reset` are synchronous:

**`Sources/Apps/AIDevToolsKitMac/Models/ChatModel.swift` — `consumeStream`:**
- `let updatedBlocks = await accumulator.apply(event)` → `let updatedBlocks = accumulator.apply(event)`

**`Sources/Apps/AIDevToolsKitMac/Views/ClaudeChainView.swift` — `startExecution`:**
- `Task { await accumulator.reset() }` → `accumulator.reset()`
- `Task { let updatedBlocks = await accumulator.apply(event); ... }` → call `apply` synchronously and call `chatModel.updateCurrentStreamingBlocks(updatedBlocks)` directly (no wrapping `Task`)

## - [x] Phase 6: Validation

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Ran `swift build` — build complete with no errors. Confirmed `MarkdownPlannerDetailView` contains no `StreamContinuationHolder`, `AsyncStream`, or continuation references.

Build:
```bash
swift build
```
Should compile with no errors.

Manual runtime check:
- Run the Mac app
- Open the Plans tab, select a plan, execute a phase
- Confirm that streaming AI output appears in the chat panel (thinking blocks in purple, tool use blocks styled correctly, text output rendering normally)
- Confirm no `StreamContinuationHolder`, `AsyncStream`, or continuation references remain in `MarkdownPlannerDetailView`
