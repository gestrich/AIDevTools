# Fix: Plans Chat Resets on Tab Switch

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns — enum-based state, `@Observable` at the App layer, thin views |
| `swift-app-architecture:swift-architecture` | 4-layer architecture — `@Observable` models belong in Apps layer, not as `@State` in views |

---

## Background

When the user navigates away from the Plans tab and returns, the chat window is reset — all messages are lost and a fresh `ChatModel` is started. This is caused by SwiftUI destroying and recreating `PlansContainer` on tab switch, which resets `@State private var chatContext: PlansChatContext?` to `nil`. When the view reappears, `.task(id: repository.id)` creates a new `PlansChatContext`, which changes `chatContextIdentifier`, which triggers `rebuildChatModel()` in `ContextualChatPanel`, creating a new `ChatModel` with an empty message history.

---

## Architectural Approach

The naive fix is to lift `@State` to `WorkspaceView`. That solves the tab-switch reset but introduces a new smell: state living in a view rather than in a model.

The correct fix follows our App-layer model ownership pattern:

- **`PlanModel`** — a new `@Observable` class that owns all runtime state for a single plan: its `PlansChatContext`, `ChatModel`, and any other per-plan state.
- **`PlansModel`** — a new `@Observable` class that owns a `[PlanID: PlanModel]` dictionary. It is the single place responsible for creating and caching `PlanModel` instances. It lives as a property of an existing workspace-level model (e.g., `WorkspaceModel` or equivalent).
- **Views are thin** — `PlansContainer` and its children receive a `PlanModel` (or `PlansModel`) and render it. No `@State` for context or chat model management.

This design also allows multiple plans to run in tandem at no extra cost, since each plan has its own independent model.

```
WorkspaceModel (@Observable, existing)
  └── plansModel: PlansModel (@Observable, new)
        └── planModels: [PlanID: PlanModel] (@Observable, new)
              ├── chatContext: PlansChatContext
              ├── chatModel: ChatModel
              └── (future per-plan runtime state)
```

---

## - [ ] Phase 1: Read Existing Code

Before writing any new code, understand the current shape of the codebase.

**Tasks:**

1. Read `PlansContainer.swift` in full. Note:
   - How `PlansChatContext` is created today (the `.task` trigger, what arguments it takes).
   - What other state `PlansContainer` currently owns.
   - What models/values are passed into `PlansContainer` from its call site.

2. Read `WorkspaceView.swift` and the workspace-level model (e.g., `WorkspaceModel.swift`) in full. Note:
   - What existing `@Observable` models are owned at the workspace level.
   - Where `PlansContainer` is instantiated and what is passed to it.
   - Whether a model already exists that is the right home for `PlansModel`.

3. Read `ContextualChatPanel.swift` to understand how `chatContextIdentifier` and `ChatModel` interact, so the new `PlanModel` initialises them correctly.

**Expected outcome:** Clear understanding of the dependency graph before touching any files.

---

## - [ ] Phase 2: Create `PlanModel`

Create a new `@Observable` class that owns all runtime state for one plan.

**Tasks:**

1. Create `PlanModel.swift` in the Apps-layer models directory (e.g., `apps/AIDevToolsKitMac/Models/`).

2. `PlanModel` should:
   - Be `@Observable`.
   - Hold `chatContext: PlansChatContext` — created in its initializer using the same arguments that `PlansContainer` currently uses in its `.task` block.
   - Hold `chatModel: ChatModel` — created from the `chatContext` (mirror how `ContextualChatPanel.rebuildChatModel()` works today).
   - Take a plan identifier (whatever type uniquely identifies a plan) as an init parameter.

3. The initializer should do exactly what the `.task` block in `PlansContainer` does today — but as synchronous setup, since the model is created once and reused.

**Expected outcome:** A self-contained, lifecycle-independent model for one plan's chat state.

---

## - [ ] Phase 3: Create `PlansModel`

Create a new `@Observable` class that manages the collection of `PlanModel` instances.

**Tasks:**

1. Create `PlansModel.swift` in the Apps-layer models directory.

2. `PlansModel` should:
   - Be `@Observable`.
   - Own `private var planModels: [PlanID: PlanModel] = [:]`.
   - Expose a method `func model(for plan: Plan) -> PlanModel` that lazily creates and caches a `PlanModel` for the given plan.
   - Expose a method `func reset()` (or respond to a repository change) that clears `planModels` so stale chat state does not carry over when the repository changes.

3. `PlansModel` receives whatever dependencies are needed to construct `PlanModel` instances (e.g., the repository, any services).

**Expected outcome:** A single owner of all per-plan models, with lazy creation and correct invalidation on repository change.

---

## - [ ] Phase 4: Wire `PlansModel` into the Workspace

Add `PlansModel` to the workspace-level model and thread it down to `PlansContainer`.

**Tasks:**

1. In the workspace-level model (identified in Phase 1), add a `let plansModel: PlansModel` property. Initialise it in the workspace model's own initializer, passing any required dependencies.

2. Remove the `.task(id: repository.id)` block from `PlansContainer` that created the old `chatContext` (it will move to `PlansModel.reset()` or be triggered by the workspace model on repository change).

3. Update `WorkspaceView` to pass `plansModel` (from the workspace model) down into `PlansContainer`.

**Expected outcome:** `PlansModel` is created once at workspace startup and survives tab navigation.

---

## - [ ] Phase 5: Refactor `PlansContainer` to Be a Thin View

Remove all context-creation logic from `PlansContainer`. It should only read from the model.

**Tasks:**

1. Remove `@State private var chatContext: PlansChatContext?` from `PlansContainer`.

2. Remove the `.task(id: repository.id)` block that assigned `chatContext`.

3. Accept a `PlansModel` (or the resolved `PlanModel` for the selected plan) as an input parameter instead.

4. Update the view body to call `plansModel.model(for: selectedPlan)` (or use the already-resolved `PlanModel`) to get `chatContext` and pass it to `ContextualChatPanel`.

5. Verify the view body is now stateless with respect to context management.

**Expected outcome:** `PlansContainer` is a thin view that renders the model it receives. No context or chat model creation happens inside any view.

---

## - [ ] Phase 6: Validation

Build and verify the fix resolves the reset behavior and supports the multi-plan case.

**Tasks:**

1. Build the project:
   ```
   xcodebuild -scheme AIDevToolsKitMac -destination 'platform=macOS' build
   ```
   Confirm zero new errors or warnings.

2. Run any existing unit or UI tests:
   ```
   xcodebuild -scheme AIDevToolsKitMac -destination 'platform=macOS' test
   ```

3. Manual smoke test — tab-switch preservation:
   - Launch the app and open the Plans tab.
   - Send one or more chat messages.
   - Switch to a different tab (e.g., Skills or another workspace tab).
   - Switch back to the Plans tab.
   - Confirm the chat messages are still present and the conversation was not reset.

4. Manual smoke test — repository change resets state:
   - Send chat messages on a plan in repository A.
   - Switch to repository B (or reopen with a different repo).
   - Confirm the chat history is cleared, since `PlansModel.reset()` should have fired.

5. Manual smoke test — multiple plans retain independent state:
   - Open Plan A, send a message.
   - Open Plan B, send a different message.
   - Switch back to Plan A.
   - Confirm Plan A's message is still present (not replaced by Plan B's).
