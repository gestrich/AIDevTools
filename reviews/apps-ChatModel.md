# Architecture Review: ChatModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ChatModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 7/10] Model directly calls AIClient for session management instead of use cases

**Location:** Lines 35-36, 62-68, 169-175, 177-186, 197-209

### Guidance

> **Depth over width** — one user action = one use case call
>
> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
>
> **Rule:** If code coordinates multiple SDK/service calls, it belongs in a use case, not in an app-layer model or service.

### Interpretation

The model holds both a `sendMessageUseCase` (correct) and a raw `client: any AIClient` reference. Five methods call `client` directly: `init` (list + load), `listSessions()`, `loadSessionDetails()`, `resumeSession()`, and `setWorkingDirectory()` (list + load). A `ListSessionsUseCase` already exists in ChatFeature but is not used. The remaining client methods (`loadSessionMessages`, `getSessionDetails`) have no corresponding use cases. This rates 7/10 because it means the model bypasses the feature layer for session operations, preventing CLI reuse and mixing orchestration with UI state management.

### Resolution

1. Use the existing `ListSessionsUseCase` instead of calling `client.listSessions()` directly.
2. Create `LoadSessionMessagesUseCase` in ChatFeature to wrap `client.loadSessionMessages()` and convert results to `[ChatMessage]`.
3. Create `GetSessionDetailsUseCase` in ChatFeature to wrap `client.getSessionDetails()`.
4. Remove the raw `client` property from ChatModel. Store `providerName` at init time like `providerDisplayName`.

---

## Finding 2 — [Severity: 6/10] Multiple independent state properties instead of enum-based state

**Location:** Lines 24-26

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties.
>
> Enum-based `ModelState` with `prior` for retaining last-known data. View switches on model state — no separate loading/error properties.

### Interpretation

The model uses three independent properties for state: `isProcessing: Bool`, `isLoadingHistory: Bool`, and implicitly an error state embedded in message content. These booleans can theoretically both be `true` simultaneously, creating an impossible state combination. There is no explicit error state — errors are silently folded into the messages array as text. Severity 6/10 because it creates maintenance burden and makes state transitions harder to reason about, though the current usage happens to avoid the impossible states.

### Resolution

Introduce a `ModelState` enum:

```swift
enum ModelState {
    case idle
    case loadingHistory
    case processing
}
```

Replace `isProcessing` and `isLoadingHistory` with a single `state` property. Add computed properties for backward compatibility with existing views.

---

## Finding 3 — [Severity: 3/10] StreamAccumulator actor defined inside a method

**Location:** Lines 238-260

### Guidance

> App-layer models should have clean, readable structure with types defined at appropriate scope.

### Interpretation

The `StreamAccumulator` actor is defined inline inside `sendMessageInternal()`. While functional, this makes the method body longer and harder to scan. Nested type definitions inside methods are unusual in Swift and obscure the type from the rest of the file. Severity 3/10 because it's a style/readability issue with no architectural impact.

### Resolution

Extract `StreamAccumulator` to a file-level `private actor` above or below the `ChatModel` class.

---

## Finding 4 — [Severity: 2/10] QueuedMessage defined in model file

**Location:** Lines 6-18

### Guidance

> Model files should contain the model. Supporting types that are purely used by the model are acceptable but should be minimal.

### Interpretation

`QueuedMessage` is a simple data struct used by ChatModel and referenced by `ChatQueueViewerSheet`. It's small and closely tied to the model, so co-location is reasonable. However, it's defined before the class, which is slightly unconventional. Severity 2/10 — very minor.

### Resolution

Move `QueuedMessage` below the `ChatModel` class definition, or leave as-is given it's small and closely related.

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 4 |
| **Highest severity** | 7/10 |
| **Overall health** | Model correctly uses `SendChatMessageUseCase` for its primary operation but bypasses the feature layer for all session management. State is scattered across independent booleans. |
| **Top priority** | Replace direct `client` calls with use cases and remove the raw AIClient dependency from the model. |
