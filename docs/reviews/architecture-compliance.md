## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find new features architected as afterthoughts and refactor them to integrate cleanly with the existing system, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/apps-layer.md`, `.agents/skills/ai-dev-tools-review/references/features-layer.md`.

Look for:
- New capabilities that require callers to call an additional setup method before using them (ceremony not required by the original API)
- New types that parallel existing types rather than extending them (e.g., `NewImportManager` alongside `ImportUseCase`)
- Feature flags or `isNewBehaviorEnabled` booleans scattered across unrelated call sites
- Extra parameters added to existing methods solely to activate new behavior, rather than designing a clean new interface

Fix: treat the new feature as a first-class citizen of the existing design. If the system already has a protocol or pattern for this kind of capability, conform to it. If the existing design cannot accommodate the new feature cleanly, refactor the design — do not bolt on. Clients should not need to know whether a capability is "new" or "old"; the API should be uniform.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Identify the architectural layer for every new or modified file; read the reference doc for that layer before reviewing anything else, and make the necessary code changes

Read the reference doc for each layer present in the changed files:
- Apps layer → `.agents/skills/ai-dev-tools-review/references/apps-layer.md`
- Features layer → `.agents/skills/ai-dev-tools-review/references/features-layer.md`
- Services layer → `.agents/skills/ai-dev-tools-review/references/services-layer.md`
- SDKs layer → `.agents/skills/ai-dev-tools-review/references/sdks-layer.md`

Layer signals: `@Observable`/`@MainActor`/SwiftUI views/`AsyncParsableCommand` → Apps; `UseCase`/`StreamingUseCase` conformance → Features; shared models and stateful utilities → Services; stateless `Sendable` structs with single-operation methods → SDKs. If a file's directory (e.g., `apps/`) disagrees with its contents (e.g., a use case struct), flag the disagreement as a finding before doing any other review.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find code placed in the wrong layer entirely and move it to the correct one, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/apps-layer.md`, `.agents/skills/ai-dev-tools-review/references/features-layer.md`, `.agents/skills/ai-dev-tools-review/references/services-layer.md`, `.agents/skills/ai-dev-tools-review/references/sdks-layer.md`.

Common violations and their fixes:
- `UseCase`/`StreamingUseCase` struct defined inside an Apps-layer file → move to `features/<Name>Feature/usecases/`
- Multi-step orchestration (coordinating multiple SDK/service calls) living in a Service → extract into a `StreamingUseCase` in Features
- Business logic or filtering computed inside a SwiftUI view body → move to a model computed property or use case
- App-specific types (domain models, config structs) defined inside an SDK → move to Services; have the Feature map them to generic SDK parameters

Each of these is a severity 7–9 violation per the skill's scale. Fix the most egregious first; a bounded move of one struct is better than a stalled full rewrite.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find upward dependencies (lower layers importing higher layers) and remove them, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/services-layer.md`, `.agents/skills/ai-dev-tools-review/references/sdks-layer.md`.

Dependency flow must be strictly downward: Apps → Features → Services → SDKs. Search for:
- Any `import` in an SDK target that references a Service, Feature, or App module (severity 10/10)
- Any `import` in a Service target that references a Feature or App module (severity 10/10)
- SDK methods whose parameters or return types are defined in a higher layer (e.g., `func fetch(config: AppConfiguration)`) — replace with primitive or SDK-defined parameters instead

Fix: define shared types at the lowest layer that needs them, or push mapping responsibility up to the Feature/App layer.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find `@Observable` or `@MainActor` outside the Apps layer and move it up, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/apps-layer.md`, `.agents/skills/ai-dev-tools-review/references/features-layer.md`, `.agents/skills/ai-dev-tools-review/references/services-layer.md`.

`@Observable` belongs **only** in the Apps layer. Search every new or modified file for `@Observable` and `@MainActor`; if found outside an Apps-layer file, it is a severity 8/10 violation.

Fix: convert the type to a plain struct (Features/Services) or `Sendable` struct (SDKs). Yield progress via `AsyncThrowingStream` instead of observable properties. The App-layer model wraps it and provides the observable surface.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find multi-step orchestration that belongs in a use case and extract it, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/features-layer.md`, `.agents/skills/ai-dev-tools-review/references/apps-layer.md`, `.agents/skills/ai-dev-tools-review/references/services-layer.md`.

An Apps-layer model or Service that calls two or more SDK/service methods in sequence is doing the Features layer's job (severity 7–8/10). Look for:
- `Task { }` blocks in `@Observable` models that chain multiple `await` calls
- Service methods named `prepare*`, `perform*`, `process*` that coordinate multiple steps
- "Manager" or "Controller" classes that orchestrate workflows without conforming to `UseCase`/`StreamingUseCase`

Fix: extract the sequence into a `StreamingUseCase` struct in `features/<Name>Feature/usecases/`. The model reduces to one `useCase.stream()` call. After extraction, check whether both the Mac app model and a CLI command consume the new use case — if either is missing, flag it.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find feature-to-feature imports and replace with a shared Service or SDK abstraction, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/features-layer.md`.

Features must not import one another (severity 9/10 — creates circular dependency risk). Search for `import <Name>Feature` inside any other Feature target.

Fix options:
- Extract shared logic into a Service (if it's stateful or needs shared configuration)
- Extract shared logic into an SDK (if it's stateless and generic)
- Compose the two features at the App layer — the model calls feature A, then feature B, sequentially

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that accept or return app-specific or feature-specific types and replace them with generic parameters, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/sdks-layer.md`.

An SDK that accepts a domain type (e.g., `TaskConfig`, `ImportOptions`, `AppConfiguration`) is coupled to one project and cannot be reused (severity 8/10). Look for parameters whose types are defined in Services, Features, or Apps.

Fix: replace domain types with primitives or SDK-defined types (strings, URLs, Data, Int). Move the mapping from domain type → SDK parameters up to the Feature that calls the SDK.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that orchestrate multiple operations and split them into single-operation methods, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/sdks-layer.md`.

Each SDK method must wrap exactly one CLI command or API call (severity 7/10). A method that calls two or more operations internally (e.g., `checkout` + `pull` + `checkout` again) is a use case in disguise.

Fix: keep individual single-operation methods on the SDK (`checkout`, `pull`). Move the multi-step sequence to a `StreamingUseCase` in the Features layer that calls those methods in order.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK types that hold mutable state and refactor to stateless structs, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/sdks-layer.md`.

SDKs must be stateless `Sendable` structs (severity 7/10 for mutable state; severity 5/10 for class/actor instead of struct). Look for `var` stored properties, caches, counters, or `class`/`actor` declarations in SDK files.

Fix: remove mutable state from the SDK. If caching is genuinely needed, create a Service that wraps the SDK and manages the cache. The SDK stays a pure pass-through.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find error swallowing across all layers and replace with proper propagation, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/apps-layer.md`, `.agents/skills/ai-dev-tools-review/references/features-layer.md`, `.agents/skills/ai-dev-tools-review/references/services-layer.md`.

Search for: empty `catch` blocks, `try?` that discards the error, `print("... failed: \(error)")` without setting state, and `continuation.finish()` called in a catch block instead of `continuation.finish(throwing: error)`.

Layer-specific fixes:
- **SDKs/Services/Features**: make the method `throws` and propagate with `continuation.finish(throwing: error)` — do not swallow
- **Apps layer**: catch errors from use cases and set an `.error(error, prior: state.snapshot)` state case so the UI can display the failure

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify use case types are structs conforming to `UseCase` or `StreamingUseCase`, not classes or actors, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/features-layer.md`.

Use cases must be `struct`s (severity 5/10 for class/actor). Search new Feature-layer files for `class` or `actor` declarations on types that perform orchestration.

Fix: convert to a struct. If the class held mutable state (e.g., a cache), move that state to a Service dependency injected via `init`. The use case struct stays stateless.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify type names follow the `<Name><Layer>` convention and rename any that don't, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/apps-layer.md`, `.agents/skills/ai-dev-tools-review/references/features-layer.md`, `.agents/skills/ai-dev-tools-review/references/services-layer.md`, `.agents/skills/ai-dev-tools-review/references/sdks-layer.md`.

Expected naming patterns: `ImportModel` (Apps), `ImportUseCase` / `ImportStreamingUseCase` (Features), `ImportConfig` / `ConfigurationService` (Services), `APIClient` / `GitClient` (SDKs). Types named `Manager`, `Controller`, or `Handler` in the Features layer almost always need renaming to `UseCase` and refactoring to conform to the protocol.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify both a Mac app model and a CLI command consume each new use case, and make the necessary code changes

Read `.agents/skills/ai-dev-tools-review/references/apps-layer.md`, `.agents/skills/ai-dev-tools-review/references/features-layer.md`.

The architectural payoff of extracting logic into a use case is reuse across entry points. For each new or modified use case, search for a corresponding `@Observable` model (Mac app) and `AsyncParsableCommand` (CLI). If either is missing, flag it — the use case exists to enable both, and a missing consumer means the architecture isn't delivering its intended value.
