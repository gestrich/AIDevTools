---
name: ai-dev-tools-architecture
description: >
  Checks and fixes Swift code for architecture violations in this project's 4-layer system
  (Apps → Features → Services → SDKs). Covers layer placement, upward dependencies,
  @Observable outside the Apps layer, multi-step orchestration in models, feature-to-feature
  imports, SDK coupling to app-specific types, SDK mutable state, use case struct convention,
  type naming, CLI parity, and error swallowing across layers. Use this whenever reviewing or
  refactoring Swift code for architecture compliance, when code is being added to any layer,
  when someone asks if code follows the layered architecture, or when ai-dev-tools-enforce is
  running.
user-invocable: true
---

# Architecture Compliance

Your job is to **fix** architecture violations, not write a review. When you find a violation, make the change. Reference the layer docs when you need the detailed rules:
- Apps → `.agents/skills/ai-dev-tools-architecture/references/apps-layer.md`
- Features → `.agents/skills/ai-dev-tools-architecture/references/features-layer.md`
- Services → `.agents/skills/ai-dev-tools-architecture/references/services-layer.md`
- SDKs → `.agents/skills/ai-dev-tools-architecture/references/sdks-layer.md`

---

## App-Layer Model State Conventions

These patterns appear across every app-layer model in this codebase and are the most common violations.

### Enum-based state — independent booleans belong in the State enum

**Look for:** `isLoading: Bool`, `isProcessing: Bool`, `isLoadingSkills: Bool`, `currentOutput: String`, `lastResults: [T]` as independent stored properties alongside a `State` enum. These can be `true`/non-nil simultaneously with any state case, creating impossible combinations.

**Fix (fold into state):**
```swift
// BEFORE
var state: State = .idle
var isLoadingSkills: Bool = false
var lastResults: [EvalSummary] = []

// AFTER — use prior pattern to retain last-known data
enum State {
    case idle(prior: [EvalSummary]?)
    case loadingSkills(prior: [EvalSummary]?)
    case loaded([EvalSummary])
    case error(Error, prior: [EvalSummary]?)
}

var lastResults: [EvalSummary]? {
    switch state {
    case .loaded(let r): return r
    case .idle(let p), .loadingSkills(let p), .error(_, let p): return p
    }
}
```

If the data is truly orthogonal to the main state (e.g., background loading of a secondary list), the minimum fix is `private(set)`.

### `private(set)` on state properties

**Look for:** `var repositories`, `var selectedRepository`, `var skills`, `var isLoadingSkills` etc. with implicit internal access — views can mutate them directly, bypassing model methods.

**Fix:** Add `private(set)` to all observable state properties:
```swift
private(set) var repositories: [RepositoryInfo] = []
private(set) var selectedRepository: RepositoryInfo?
private(set) var skills: [SkillInfo] = []
```

### Derived properties stored independently

**Look for:** A property always computed from another (e.g., `phases` always set by parsing `content` on every update). Storing both creates a theoretical risk of going out of sync.

**Fix:** Make it a computed property, or fold both into the state enum so they're always in sync.

### Multiple use case instances rebuilt via parallel mutable vars

**Look for:** Six `var` use case properties all reconstructed together in a `rebuildUseCases()` method when a dependency (e.g., provider) changes. Both `init` and `rebuildUseCases()` must stay in sync.

**Fix:** Group into a private struct so `rebuildUseCases()` is one assignment and can't drift from `init`:
```swift
private struct UseCases {
    let foo: FooUseCase
    let bar: BarUseCase
    init(client: any AIClient) {
        self.foo = FooUseCase(client: client)
        self.bar = BarUseCase(client: client)
    }
}
private var useCases: UseCases
```

---

## New Features Architected as Afterthoughts

**Look for:**
- New capability that requires callers to call an extra setup method before using it
- New type that parallels an existing type rather than extending it (e.g., `NewImportManager` alongside `ImportUseCase`)
- Feature flags or `isNewBehaviorEnabled` booleans scattered across unrelated call sites
- Extra parameters added to existing methods solely to activate new behavior

**Fix:** Treat the new feature as a first-class citizen of the existing design. If a protocol or pattern already exists for this kind of capability, conform to it. Clients should not know whether a capability is "new" or "old."

---

## Identifying the Layer

For every changed file, determine its layer before checking anything else. If the file's directory (e.g., `Apps/`) disagrees with its contents (e.g., a use case struct), that disagreement is itself a violation.

| Signal | Layer |
|--------|-------|
| `@Observable`, `@MainActor`, SwiftUI views, `AsyncParsableCommand` | **Apps** |
| `UseCase` / `StreamingUseCase` conformance, multi-step orchestration | **Features** |
| Shared models, configuration, stateful utilities across features | **Services** |
| Stateless `Sendable` structs, single-operation methods | **SDKs** |

---

## Code in the Wrong Layer

**Look for:**
- `UseCase`/`StreamingUseCase` struct defined inside an Apps-layer file
- Business logic or filtering computed inside a SwiftUI view body
- App-specific types (domain models, config structs) defined inside an SDK
- Multi-step orchestration in a Service (it belongs in a Feature use case)

**Fix:** Move the type to the correct layer. Use cases → `features/<Name>Feature/usecases/`. Value-type models → `Services/`. Stateless wrappers → SDKs.

---

## Upward Dependencies

Dependency flow must be strictly downward: Apps → Features → Services → SDKs.

**Look for:**
- Any `import` in an SDK target referencing a Service, Feature, or App module (severity 10/10)
- Any `import` in a Service target referencing a Feature or App module (severity 10/10)
- SDK method parameters or return types defined in a higher layer

**Fix:** Define shared types at the lowest layer that needs them, or push mapping responsibility up to the Feature/App layer.

---

## `@Observable` / `@MainActor` Outside the Apps Layer

`@Observable` belongs **only** in the Apps layer.

**Look for:** `@Observable` or `@MainActor` on types in Feature, Service, or SDK files.

**Fix:** Convert to a plain struct. Yield progress via `AsyncThrowingStream` instead of observable properties. The App-layer model provides the observable surface.

---

## Multi-Step Orchestration Belonging in a Use Case

An Apps-layer model or Service that calls two or more SDK/service methods in sequence is doing the Features layer's job.

**Look for:**
- `Task { }` blocks in `@Observable` models chaining multiple `await` calls
- Service methods named `prepare*`, `perform*`, `process*` coordinating multiple steps
- "Manager" or "Controller" classes orchestrating workflows without `UseCase`/`StreamingUseCase`

**Fix:** Extract into a `StreamingUseCase` struct in `features/<Name>Feature/usecases/`. The model reduces to one `useCase.stream()` call. After extraction, verify both a Mac app model and a CLI command consume the new use case.

---

## Feature-to-Feature Imports

Features must not import one another — it creates circular dependency risk.

**Look for:** `import <Name>Feature` inside any other Feature target.

**Fix:**
- Extract shared logic into a Service (if stateful) or SDK (if stateless)
- Compose at the App layer: model calls feature A, then feature B

---

## SDK Methods Accepting App-Specific Types

An SDK that accepts a domain type (e.g., `TaskConfig`, `ImportOptions`) is coupled to one project.

**Look for:** SDK method parameters or return types defined in Services, Features, or Apps.

**Fix:** Replace domain types with primitives or SDK-defined types (strings, URLs, Data, Int). Move mapping from domain type → SDK parameters up to the Feature layer.

---

## SDK Methods Orchestrating Multiple Operations

Each SDK method must wrap exactly one CLI command or API call.

**Look for:** A method that calls two or more operations internally — it's a use case in disguise.

**Fix:** Keep individual single-operation methods on the SDK. Move the multi-step sequence to a `StreamingUseCase` in Features.

---

## SDK Types Holding Mutable State

SDKs must be stateless `Sendable` structs.

**Look for:** `var` stored properties, caches, counters, or `class`/`actor` declarations in SDK files.

**Fix:** Remove mutable state. If caching is needed, create a Service that wraps the SDK.

---

## Services Layer Value-Type Conventions

### `var` properties never mutated after init → `let`

**Look for:** Services-layer value types (`struct`) with `var` properties that are set in `init` and never reassigned afterward.

**Fix:** Change to `let`. Before changing, check extensions and other files for mutation. If post-decode patching is needed (e.g., an `EvalCase` that needs its `suite` set after JSON decoding), keep `var` but add a `withX(_:)` copy method and remove direct external mutation:
```swift
// BEFORE
var suite: EvalSuite?

// AFTER
let suite: EvalSuite?
func withSuite(_ suite: EvalSuite) -> EvalCase {
    return EvalCase(suite: suite, ...)
}
```

### `Sendable` conformance on value types

**Look for:** `struct` or `enum` in Services or SDKs that are passed across concurrency boundaries but lack `Sendable`.

**Fix:** Add `Sendable` conformance. If a stored property isn't `Sendable`, either make it `Sendable` or use `@unchecked Sendable` with a comment explaining why it's safe.

### Services type duplicates an SDK type

**Look for:** A Services-layer struct whose properties, init signature, and conformances are identical to (or a subset of) an SDK type that already exists. The mapping use case is pure boilerplate.

**Example:** `Skill` and `ReferenceFile` in SkillService duplicated `SkillInfo` and `SkillReferenceFile` from SkillScannerSDK.

**Fix:**
1. Add any missing conformances (`Identifiable`, `Hashable`) to the SDK type
2. Replace all usages of the Services duplicate with the SDK type
3. Simplify any mapping use case to return SDK types directly
4. Delete the Services type

---

## Error Swallowing

**Look for across all layers:**
- Empty `catch {}` blocks
- `try?` discarding the error without handling the `nil` result
- `catch { print("... failed: \(error)") }` — logged but not propagated
- `Task { try? await ... }` — fire-and-forget swallowing failures
- `continuation.finish()` in a catch instead of `continuation.finish(throwing: error)`

**Fix (by layer):**
- **SDKs / Services / Features**: add `throws` and propagate — do not log here
- **Apps layer**: catch from use cases, set `.error(error, prior: state.snapshot)` state — this surfaces the error to the UI and is sufficient; do not also add `logger.error(...)` alongside the state update (that pattern was flagged as redundant in review)

**On logging:** `logger.error(...)` is only appropriate when there is no other communication channel (e.g., a background task with no observable state). Never use `print(...)` as a substitute — use the structured logger if logging is genuinely needed.

**When swallowing is intentional:** The rare cases where swallowing is correct (e.g., best-effort cleanup where failure is harmless) must be documented at the call site:

```swift
// Swallowing intentionally: cache clearing is best-effort; a failure here
// leaves stale data but does not affect correctness of the operation.
try? clearCache()
```

Without this comment, a `try?` or empty `catch` is indistinguishable from an oversight.

---

## Use Case Types Must Be Structs

**Look for:** `class` or `actor` declarations on types conforming to `UseCase`/`StreamingUseCase`.

**Fix:** Convert to a struct. If the class held mutable state (e.g., a cache), move that state to a Service dependency injected via `init`.

---

## Type Naming Convention

Expected patterns: `ImportModel` (Apps), `ImportUseCase` / `ImportStreamingUseCase` (Features), `ImportConfig` / `ConfigurationService` (Services), `APIClient` / `GitClient` (SDKs).

**Look for:** Types named `Manager`, `Controller`, or `Handler` in the Features layer — they almost always need renaming to `UseCase` and refactoring to conform to the protocol.

---

## CLI Parity

For each new or modified use case, there should be both an `@Observable` model (Mac app) and an `AsyncParsableCommand` (CLI). If either is missing, flag it — the use case exists to enable both.
