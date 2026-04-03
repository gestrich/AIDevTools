# Add Screenshot Targets to AIDevTools

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) — target placement |
| `swift-snapshot-testing` | Three techniques for capturing screenshots from background processes |

## Background

GetRicher has two UI test targets that enable AI-driven screenshot capture:

1. **GetRicherUITests** — Standard XCUITests with `captureScreenshot()` helpers. Good for scripted, deterministic screenshot flows.
2. **GetRicherInteractiveTests** — Uses `xcode-sim-automation` (`InteractiveControlLoop`) for interactive, CLI-driven control of the running app in the Simulator.

AIDevTools currently has **zero UI test targets**. It's a macOS app (not iOS), which means:
- It runs natively on Mac — no Simulator needed
- Method 2 (Aqua screen capture) or Method 3 (xcode-sim-automation) from the snapshot skill both apply
- For macOS, standard XCUITests work well and are simpler than the interactive approach

The goal: add UI test targets to AIDevTools so Claw can capture screenshots of each major screen, verify them, and include them in a PR under `screenshots/`.

### AIDevTools Main Screens (tabs in WorkspaceView)

1. **Architecture** — Architecture planner with diagram view
2. **Chains** — Claude Chain management
3. **Evals** — Eval runner with results
4. **Plans** — Markdown planner
5. **PR Radar** — PR review with list/detail
6. **Skills** — Skill browser

Plus: **Settings** (separate window/view)

## Phases

## - [x] Phase 1: Bill creates the UI test targets in Xcode (MANUAL — Bill)

**Skills used**: none
**Principles applied**: Both UI test targets (`AIDevToolsUITests` and `AIDevToolsInteractiveTests`) already existed in the Xcode project, along with the `xcode-sim-automation` SPM package linked via `XCUITestControl`. No changes were needed — verified by inspecting `project.pbxproj` and the target directories.

**Skills to read**: none (Xcode UI work)

Bill needs to manually create two targets in the AIDevTools Xcode project:

### Target 1: `AIDevToolsUITests`
- **Type:** UI Testing Bundle
- **Target Application:** AIDevTools
- **Purpose:** Scripted screenshot tests (like GetRicherUITests)

### Target 2: `AIDevToolsInteractiveTests`
- **Type:** UI Testing Bundle  
- **Target Application:** AIDevTools
- **Dependencies:** Add `xcode-sim-automation` SPM package (`https://github.com/gestrich/xcode-sim-automation`) and link `XCUITestControl` to this target
- **Purpose:** Interactive CLI-driven control (like GetRicherInteractiveTests)

**Steps for Bill:**
1. Open `AIDevTools.xcodeproj` in Xcode
2. File → New → Target → macOS → UI Testing Bundle → name it `AIDevToolsUITests`, target app = AIDevTools
3. File → New → Target → macOS → UI Testing Bundle → name it `AIDevToolsInteractiveTests`, target app = AIDevTools
4. Add `xcode-sim-automation` SPM dependency to the project (URL: `https://github.com/gestrich/xcode-sim-automation`)
5. In `AIDevToolsInteractiveTests` target → Build Phases → Link Binary With Libraries → add `XCUITestControl`
6. Commit the changes so Claw can work on them

**Deliverable:** Two empty UI test targets in the Xcode project, committed to a branch.

## - [x] Phase 2: Claw writes the scripted screenshot tests (CLAW)

**Skills used**: `swift-snapshot-testing`
**Principles applied**: Used Method 1 (XCUITests for macOS) as the preferred approach. Implemented `launchApp()`, `saveScreenshot()`, `findTab()`, and `tapTab()` helpers. Tests cover all 6 tabs plus settings (via Cmd+,). Added `selectFirstRepository()` to handle empty state gracefully. Tests use numbered names for deterministic ordering. The file was already present from a prior commit — verified build succeeds for both app and test targets.

**Skills to read**: `swift-snapshot-testing`, `swift-architecture`

Create `AIDevToolsUITests/AIDevToolsUITests.swift` following the GetRicher pattern:

- Helper: `launchApp()` that launches the app and waits for the main window
- Helper: `captureScreenshot(app, name)` using `XCTAttachment`
- Helper: `selectTab(app, tabName)` to switch between tabs
- Tests for each screen:
  - `testArchitectureTabScreenshot()` — select Architecture tab, capture
  - `testChainsTabScreenshot()` — select Chains tab, capture
  - `testEvalsTabScreenshot()` — select Evals tab, capture
  - `testPlansTabScreenshot()` — select Plans tab, capture
  - `testPRRadarTabScreenshot()` — select PR Radar tab, capture
  - `testSkillsTabScreenshot()` — select Skills tab, capture
  - `testSettingsScreenshot()` — open Settings, capture

**Note:** The app needs at least one repository configured to show tab content. Tests should handle the empty state gracefully (screenshot whatever is visible).

## - [x] Phase 3: Claw writes the interactive control test (CLAW)

**Skills used**: `swift-snapshot-testing`
**Principles applied**: The `InteractiveControlTests` class with `testInteractiveControl()` was already present in `AIDevToolsInteractiveTests/AIDevToolsInteractiveTests.swift` from Phase 1. It correctly imports `XCUITestControl`, launches the app, and runs `InteractiveControlLoop().run(app:)` per Method 4 of the snapshot skill. Verified both the app and test targets build successfully (`** TEST BUILD SUCCEEDED **`).

**Skills to read**: `swift-snapshot-testing`

Create `AIDevToolsInteractiveTests/InteractiveControlTests.swift` mirroring GetRicher's pattern:

```swift
import XCTest
import XCUITestControl

final class InteractiveControlTests: XCTestCase {
    @MainActor
    func testInteractiveControl() throws {
        let app = XCUIApplication()
        app.launch()
        InteractiveControlLoop().run(app: app)
    }
}
```

This enables CLI-driven screenshot capture via `xcuitest-control` for more flexible, on-demand screenshots.

## - [x] Phase 4: Claw captures screenshots and creates PR (CLAW)

**Skills used**: `swift-snapshot-testing`
**Principles applied**: Ran `AIDevToolsUITests` via `xcodebuild test` from the interactive terminal (Aqua session already available — no launchctl bootstrap needed). All 9 tests passed. Extracted screenshots from the `.xcresult` bundle using `xcresulttool export --legacy`, walking the summaryRef → payloadRef chain. Resized all images with `sips -Z 1200`. Saved to `screenshots/` in the repo root with descriptive names. Created a draft PR.

**Skills to read**: `swift-snapshot-testing`

1. Launch the AIDevTools UI tests from the Aqua session (macOS UI tests require Aqua, same as GetRicher):
   ```bash
   xcodebuild test \
     -project AIDevTools.xcodeproj \
     -scheme AIDevTools \
     -only-testing:AIDevToolsUITests \
     -resultBundlePath /tmp/AIDevToolsResults
   ```
2. Extract screenshots from the result bundle or `/tmp/` output
3. Create `screenshots/` folder in the repo root
4. Copy all captured screenshots there with descriptive names:
   - `screenshots/architecture-tab.png`
   - `screenshots/chains-tab.png`
   - `screenshots/evals-tab.png`
   - `screenshots/plans-tab.png`
   - `screenshots/pr-radar-tab.png`
   - `screenshots/skills-tab.png`
   - `screenshots/settings.png`
5. Resize screenshots with `sips -Z 1200` for reasonable file sizes
6. Create a PR on `gestrich-ai/AIDevTools` → `gestrich/AIDevTools` with:
   - The new test files
   - The `screenshots/` folder with captured images
   - A PR description showing each screenshot

## - [x] Phase 5: Validation

**Skills used**: none
**Principles applied**: Verified all success criteria by inspecting existing artifacts. Both UI test targets (`AIDevToolsUITests`, `AIDevToolsInteractiveTests`) build successfully (`** TEST BUILD SUCCEEDED **`). The `screenshots/` folder contains all 9 captured images (6 tabs + settings + empty state + repository sidebar). Draft PR #14 exists with all test files and screenshots.

**Skills to read**: none

**Success criteria:**
- Both UI test targets exist and build
- `AIDevToolsUITests` runs and captures screenshots of all 6 tabs + settings
- `AIDevToolsInteractiveTests` has the interactive control loop ready
- `screenshots/` folder contains all captured images
- PR is created with screenshots visible for Bill to review
- Screenshots show actual app content (not just blank windows)
