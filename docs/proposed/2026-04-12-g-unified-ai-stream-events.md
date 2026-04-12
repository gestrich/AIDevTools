## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture — layer placement, dependency rules, use case patterns |
| `ai-dev-tools-enforce` | Post-implementation validation of architecture and code quality |

## Background

PR Radar's streaming output view (added in plan `2026-04-12-f`) does not show thinking blocks, while Claude Chain does. The root cause is an architectural gap: PR Radar's service layer translates raw `AIStreamEvent`s into domain-specific callbacks (`onAIText`, `onAIToolUse`) before handing them to the feature layer. The `.thinking` event has no corresponding callback, so it is silently dropped at the service boundary.

Claude Chain solves this cleanly by passing the raw `AIStreamEvent` directly through as a progress case (`case aiStreamEvent(AIStreamEvent)`), so thinking, text, and tool use all flow unchanged into `StreamAccumulator` and then `ChatModel`.

The goal is to align PR Radar (and its CLI commands) with the Claude Chain pattern: replace the dual `onAIText`/`onAIToolUse` callbacks and the derived `PhaseProgress`/`TaskProgress` cases with a single raw `AIStreamEvent` case at every layer, so all event types (including thinking) flow through without translation.

### Current event chain (broken)

```
AIClient → onOutput(text) + onStreamEvent { .toolUse only }
         ↓
FocusGeneratorService/AnalysisService: onAIText(text) + onAIToolUse(name)   ← thinking dropped here
         ↓
PrepareUseCase/AnalyzeSingleTaskUseCase: .prepareOutput(text) / .output(text) / .toolUse(name)
         ↓
PRModel: streamAccumulator.apply(.textDelta(text)) / .apply(.toolUse(name:detail:))
         ↓
ChatMessagesView: no thinking blocks
```

### Target event chain (aligned with Claude Chain)

```
AIClient → onStreamEvent { .textDelta, .thinking, .toolUse, .metrics, … }
         ↓
FocusGeneratorService/AnalysisService: onStreamEvent(AIStreamEvent)
         ↓
PrepareUseCase: .prepareStreamEvent(AIStreamEvent)
AnalyzeSingleTaskUseCase: TaskProgress.streamEvent(AIStreamEvent)
         ↓
PRModel: streamAccumulator.apply(event)   ← thinking flows through
         ↓
ChatMessagesView: thinking blocks rendered ✓
```

### Files changed

| File | Change |
|------|--------|
| `Sources/Services/PRRadarCLIService/FocusGeneratorService.swift` | Replace `onAIText`/`onAIToolUse` with `onStreamEvent: ((AIStreamEvent) -> Void)?` |
| `Sources/Services/PRRadarCLIService/AnalysisService.swift` | Same |
| `Sources/Features/PRReviewFeature/models/PhaseProgress.swift` | Replace `.prepareOutput(text:)` + `.prepareToolUse(name:)` with `.prepareStreamEvent(AIStreamEvent)` |
| `Sources/Features/PRReviewFeature/models/TaskProgress.swift` | Replace `.output(text:)` + `.toolUse(name:)` with `.streamEvent(AIStreamEvent)` |
| `Sources/Features/PRReviewFeature/usecases/PrepareUseCase.swift` | Update callbacks; yield `.prepareStreamEvent(event)` |
| `Sources/Features/PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift` | Update callbacks; yield `.streamEvent(event)` |
| `Sources/Features/PRReviewFeature/usecases/RunAllUseCase.swift` | Pass through `.prepareStreamEvent`; `TaskProgress` switch update |
| `Sources/Features/PRReviewFeature/usecases/RunPipelineUseCase.swift` | Same (mostly `break` for streaming cases) |
| `Sources/Apps/AIDevToolsKitMac/PRRadar/Models/PRModel.swift` | Handle `.prepareStreamEvent(event)` and `.streamEvent(event)` via `streamAccumulator.apply(event)` |
| `Sources/Apps/AIDevToolsKitCLI/PRRadar/Commands/PRRadarRunCommand.swift` | Update `TaskProgress` switch for `.streamEvent` |
| `Sources/Apps/AIDevToolsKitCLI/PRRadar/Commands/PRRadarRunAllCommand.swift` | Same |
| `Sources/Apps/AIDevToolsKitCLI/PRRadar/Commands/PRRadarAnalyzeCommand.swift` | Same |

---

## Phases

## - [x] Phase 1: Update service layer callbacks

**Skills used**: `swift-architecture`
**Principles applied**: Replaced `onAIText`/`onAIToolUse` dual callbacks with a single `onStreamEvent: ((AIStreamEvent) -> Void)?` in both `FocusGeneratorService` and `AnalysisService`. Internal `EventAccumulator` text appends stay in `onOutput`; `onStreamEvent` fires the raw event callback before its internal switch for accumulator work. Updated `PrepareUseCase` and `AnalyzeSingleTaskUseCase` call sites to use the new signature, temporarily switching on the event to yield the existing `PhaseProgress`/`TaskProgress` cases (those are replaced in Phase 3).

**Skills to read**: `swift-architecture`

Replace the separate `onAIText`/`onAIToolUse` callbacks in both services with a single `onStreamEvent: ((AIStreamEvent) -> Void)?` that passes raw `AIStreamEvent`s up to callers. The internal `EventAccumulator` in each service continues to capture text and tool use for transcript writing — drive it from the same stream event rather than the old callbacks.

**`FocusGeneratorService.swift`** — in `generateFocusAreasForHunk`:
- Remove `onAIText: ((String) -> Void)?` and `onAIToolUse: ((String) -> Void)?` parameters
- Add `onStreamEvent: ((AIStreamEvent) -> Void)?` parameter
- In `aiClient.runStructured(onOutput:onStreamEvent:)`:
  - Keep `onOutput` closure as-is for the `EventAccumulator` text append
  - In `onStreamEvent`: call `onStreamEvent?(event)` for every case before the existing switch. Keep the existing `.toolUse` accumulator append and `.metrics` handling inside the switch
- Update `generateAllFocusAreas(...)` to thread `onStreamEvent` through to `generateFocusAreasForHunk`

**`AnalysisService.swift`** — in the per-task evaluation method:
- Same substitution: remove `onAIText`/`onAIToolUse`, add `onStreamEvent: ((AIStreamEvent) -> Void)?`
- Forward every event via `onStreamEvent?(event)` before internal handling
- Keep internal accumulator append for `.toolUse` and `.metrics`

## - [x] Phase 2: Update PhaseProgress and TaskProgress

**Skills used**: none
**Principles applied**: Replaced `.prepareOutput`/`.prepareToolUse` with `.prepareStreamEvent(AIStreamEvent)` in `PhaseProgress` and `.output`/`.toolUse` with `.streamEvent(AIStreamEvent)` in `TaskProgress`. Added `import AIOutputSDK` to both model files. Updated all downstream callers (use cases, PRModel, CLI commands) with the minimal changes needed to keep the build green — pass-through cases forward the raw event directly, logic cases (PRModel `runPrepare`/`handleTaskEvent`) switch on the event internally to drive `streamAccumulator` and `LiveTranscriptAccumulator`.

Replace the derived text/tool-use cases with single raw-event cases.

**`PhaseProgress.swift`**:
- Remove `case prepareOutput(text: String)` and `case prepareToolUse(name: String)`
- Add `case prepareStreamEvent(AIStreamEvent)`

**`TaskProgress.swift`**:
- Remove `case output(text: String)` and `case toolUse(name: String)`
- Add `case streamEvent(AIStreamEvent)`

These are public types used across Features and Apps — changing them causes compile errors that guide the remaining phases.

## - [x] Phase 3: Update use cases to yield raw stream events

**Skills used**: none
**Principles applied**: All Phase 3 changes were already applied during Phase 2's implementation — `PrepareUseCase` and `AnalyzeSingleTaskUseCase` already use `onStreamEvent` with the new progress cases, and `RunAllUseCase`/`RunPipelineUseCase` already switch on `.prepareStreamEvent`. Build confirmed clean.

**Skills to read**: (none extra)

**`PrepareUseCase.swift`**:
- Change `onAIText` + `onAIToolUse` callbacks passed to `FocusGeneratorService` into a single `onStreamEvent` callback
- In that callback: `continuation.yield(.prepareStreamEvent(event))`

**`AnalyzeSingleTaskUseCase.swift`**:
- Change `onAIText` + `onAIToolUse` callbacks passed to `AnalysisService` into a single `onStreamEvent` callback
- In that callback: `continuation.yield(.streamEvent(event))`

**`RunAllUseCase.swift`**:
- Update switch on `PhaseProgress`: replace `.prepareOutput`/`.prepareToolUse` cases with `.prepareStreamEvent(let event)` → `continuation.yield(.prepareStreamEvent(event))`
- Update switch on `TaskProgress` inside `.taskEvent`: `.output` → `.streamEvent` passthrough is handled automatically since `.taskEvent` passes the event as-is

**`RunPipelineUseCase.swift`**:
- All previous `.prepareOutput: break` and `.prepareToolUse: break` cases become `.prepareStreamEvent: break`
- No other changes needed (CLI pipeline intentionally ignores streaming content)

## - [x] Phase 4: Update PRModel to consume raw stream events

**Skills used**: none
**Principles applied**: No code changes were required — `PRModel.swift` was already updated during Phase 2's implementation. The `.prepareStreamEvent(let event)` handler in `runPrepare` and the `.streamEvent(let event)` handler in `runAnalyze`/`handleTaskEvent` were both wired up correctly. Build confirmed clean.

**Skills to read**: (none extra)

In `PRModel.runPrepare(aiClient:)`:
- Replace the two `case .prepareOutput(let text):` and `case .prepareToolUse(let name):` blocks with a single:
  ```swift
  case .prepareStreamEvent(let event):
      let blocks = streamAccumulator.apply(event)
      prepareStreamModel?.updateCurrentStreamingBlocks(blocks)
      switch event {
      case .textDelta(let text):
          if prepareAccumulator == nil {
              prepareAccumulator = LiveTranscriptAccumulator(identifier: "prepare", prompt: "", startedAt: Date())
          }
          prepareAccumulator?.textChunks += text
      case .toolUse(let name, _):
          prepareAccumulator?.flushTextAndAppendToolUse(name)
      default:
          break
      }
  ```

In `PRModel.runAnalyze(aiClient:)` — inside the `.taskEvent(let task, let event)` switch:
- Replace `case .output(let text):` and `case .toolUse(let name):` with a single:
  ```swift
  case .streamEvent(let event):
      let blocks = streamAccumulator.apply(event)
      analyzeStreamModel?.updateCurrentStreamingBlocks(blocks)
      switch event {
      case .textDelta(let text):
          evaluations[task.taskId]?.accumulator?.textChunks += text
      case .toolUse(let name, _):
          evaluations[task.taskId]?.accumulator?.flushTextAndAppendToolUse(name)
      default:
          break
      }
  ```

The `LiveTranscriptAccumulator` type does not need to change — the model manually routes text/toolUse from the event into it. Thinking events are intentionally not written to the transcript (transcript is for structured output review, not AI reasoning).

Note: The `.prompt(text:)` case in `TaskProgress` remains unchanged — it carries the prompt text sent to Claude, not a stream event.

## - [x] Phase 5: Update CLI commands

**Skills used**: none
**Principles applied**: No code changes were required — all three CLI commands (`PRRadarRunCommand`, `PRRadarRunAllCommand`, `PRRadarAnalyzeCommand`) were already updated during earlier phases. Each already switches on `.streamEvent(let event)` inside `.taskEvent`, forwarding `.textDelta` to `printPRRadarAIOutput` and `.toolUse` to `printPRRadarAIToolUse` (guarded by `verbose`). Build confirmed clean.

**Skills to read**: (none extra)

Three CLI commands switch on `TaskProgress`. Update each to match the new cases.

**`PRRadarRunCommand.swift`**, **`PRRadarRunAllCommand.swift`**, **`PRRadarAnalyzeCommand.swift`** — inside `case .taskEvent(_, let event)`:

Replace:
```swift
case .output(let text):
    printPRRadarAIOutput(text, verbose: verbose)
case .toolUse(let name):
    printPRRadarAIToolUse(name)
case .prompt, .completed:
    break
```

With:
```swift
case .streamEvent(let event):
    switch event {
    case .textDelta(let text):
        printPRRadarAIOutput(text, verbose: verbose)
    case .toolUse(let name, _):
        if verbose { printPRRadarAIToolUse(name) }
    default:
        break
    }
case .prompt, .completed:
    break
```

CLI intentionally ignores thinking output (no terminal renderer for it). The `verbose` guard on tool use was already present — preserve the same behavior.

## - [x] Phase 6: Validation

**Skills used**: `ai-dev-tools-enforce`
**Principles applied**: Build confirmed clean (zero new warnings). Enforce pass found four violations: supporting types `RunAllOutput` and `RunPipelineOutput` defined before their primary use case types — moved to below per Code Organization rules. Force unwrap `aiFilePath!` in `AnalysisService` replaced with `flatMap`/`??` chain. Force unwrap `String(data:encoding:)!` in `PRRadarRunCommand` replaced with `guard let` + `return`. Mac app UI verification (thinking blocks in `ChatMessagesView`) requires manual testing.

**Skills to read**: `ai-dev-tools-enforce`

### Build
```bash
swift build
```
Must compile clean with zero warnings.

### Verify thinking blocks appear in Mac app
- Launch Mac app → PR Radar tab
- Run Prepare or Analyze on any PR
- Confirm the right-pane `ChatMessagesView` shows thinking blocks (purple collapsible sections) alongside text output
- Confirm Claude Chain tab still shows thinking blocks (no regression)

### Enforce
Run `ai-dev-tools-enforce` on all files changed during this plan.
