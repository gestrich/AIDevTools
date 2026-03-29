# Fix: Plans Chat Resets on Tab Switch

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-swiftui` | SwiftUI state management patterns relevant to preserving view state across tab switches |

---

## Background

When the user navigates away from the Plans tab and returns, the chat window is reset — all messages are lost and a fresh `ChatModel` is started. This is caused by SwiftUI destroying and recreating `PlansContainer` on tab switch, which resets `@State private var chatContext: PlansChatContext?` to `nil`. When the view reappears, `.task(id: repository.id)` creates a new `PlansChatContext`, which changes `chatContextIdentifier`, which triggers `rebuildChatModel()` in `ContextualChatPanel`, creating a new `ChatModel` with an empty message history.

The fix is to lift `PlansChatContext` creation to `WorkspaceView` — the view that owns the `TabView` and is never destroyed during tab navigation — so the context (and the `ChatModel` it anchors) survives tab switches.

---

## - [ ] Phase 1: Lift PlansChatContext into WorkspaceView

**Skills to read**: `swift-app-architecture:swift-swiftui`

Move the `PlansChatContext` from `PlansContainer` up to `WorkspaceView` so its lifetime is tied to the workspace, not the tab's view.

**Tasks:**

1. Read `WorkspaceView.swift` and `PlansContainer.swift` in full to understand the current call site and any relevant model dependencies (`markdownPlannerModel`, `model`, `selectedPlanName`).

2. In `WorkspaceView.swift`:
   - Add `@State private var plansChatContext: PlansChatContext?`
   - Add a `.task(id: repository.id)` (or the equivalent trigger already used in `PlansContainer`) that creates and assigns the `PlansChatContext` exactly as `PlansContainer` currently does.
   - Pass `plansChatContext` down to `PlansContainer` as a new parameter.

3. The `@State` in `WorkspaceView` will persist across tab switches because `WorkspaceView` is never destroyed during normal tab navigation — it is the root view containing the `TabView`.

**Expected outcome:** `PlansChatContext` is created once when the workspace loads (or when the repository changes) and is not recreated on tab navigation.

---

## - [ ] Phase 2: Update PlansContainer to Accept an External ChatContext

Remove the internal context creation from `PlansContainer` and replace it with the externally provided instance.

**Tasks:**

1. Change `PlansContainer`'s initializer to accept a `PlansChatContext?` (or non-optional if appropriate) parameter, e.g. `chatContext: PlansChatContext?`.

2. Remove `@State private var chatContext: PlansChatContext?` from `PlansContainer`.

3. Remove the `.task(id: repository.id)` block inside `PlansContainer` that assigned `chatContext`.

4. Update any internal references to `chatContext` to use the passed-in parameter. The rest of the view body (passing `chatContext` to `ContextualChatPanel`) should remain unchanged.

5. Update the call site in `WorkspaceView` to pass `plansChatContext` into `PlansContainer`.

**Expected outcome:** `PlansContainer` no longer owns or creates the `PlansChatContext`. It only consumes it. The chat state survives view destruction/recreation of `PlansContainer`.

---

## - [ ] Phase 3: Validation

Build and verify the fix resolves the reset behavior.

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

3. Manual smoke test:
   - Launch the app and open the Plans tab.
   - Send one or more chat messages.
   - Switch to a different tab (e.g., Skills or another workspace tab).
   - Switch back to the Plans tab.
   - Confirm the chat messages are still present and the conversation was not reset.

4. Verify that changing the repository (if applicable) still correctly resets the chat, since the `.task(id: repository.id)` trigger should still handle that case.
