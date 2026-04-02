---
name: swift-snapshot-testing
description: Four techniques for capturing iOS/macOS screenshots. Method 1 (XCUITests for macOS) captures real app screenshots — the preferred approach. Method 2 (ImageRenderer) works anywhere with no dependencies. Methods 3-4 require Aqua launchctl bootstrap from background processes. Use when you need screenshots from daemons, CI, SSH, or OpenClaw.
---

# Swift Snapshot Testing

Four proven methods for capturing screenshots from background processes (like OpenClaw). Choose based on what you need to capture.

## Background: Session Types

macOS runs processes in different **launchd session types** that determine what they can access:

- **Aqua** — The GUI session. Created when a user logs in and sees the desktop. Has access to the window server, can draw windows, run the Simulator, use ScreenCaptureKit.
- **Background** — For daemons and services (this is where OpenClaw runs). No window server access, no display. Cannot run Simulator UI or screen capture APIs.

These are separate from **display state** (awake vs asleep). A Background process has no GUI access regardless of whether the display is on. An Aqua process has GUI access but some APIs may still need the display awake.

### Aqua Launchctl Bootstrap

Methods 1, 3 and 4 need Aqua access. From a Background process, you can launch commands in the Aqua session:

```bash
LABEL="com.openclaw.my-task"

cat > /tmp/$LABEL.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/tmp/my-script.sh</string>
    </array>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "/tmp/$LABEL.plist"
launchctl kickstart "gui/$(id -u)/$LABEL"
```

**Requirements:** User must be logged into the GUI (Aqua session must exist). Display should be awake for Simulator/screen capture APIs.

---

## Method 1: XCUITests for macOS Apps (Preferred)

**Best for:** Capturing screenshots of a real running macOS app — launches the app, interacts with UI elements, and takes screenshots. This is the standard approach for macOS app screenshot automation.

**Session requirement:** Aqua (user must be logged in with a GUI session). When running from an interactive terminal, Aqua is already available — no launchctl bootstrap needed. From a Background session (e.g., OpenClaw), launch via Terminal.app using a `.command` file opened through Aqua launchctl (see "Running from a Background Session" below).

### Prerequisites

Before running XCUITests for the first time on a machine, enable automation mode:

```bash
# Enable developer tools (persists across reboots)
sudo /usr/sbin/DevToolsSecurity -enable

# Enable automation mode without authentication prompts (persists across reboots)
sudo automationmodetool enable-automationmode-without-authentication
```

Without these, tests will hang at "Running tests..." and eventually fail with:
> "Timed out while enabling automation mode."

You can verify the current state with:
```bash
/usr/sbin/DevToolsSecurity -status
automationmodetool
```

### Setup

Add a UI Testing bundle target to your Xcode project (File → New → Target → UI Testing Bundle). The test target must depend on the main app target.

### Writing a Screenshot Test

```swift
import XCTest

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Main window should appear")
        sleep(3)
        return app
    }

    @MainActor
    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        // Capture just the app window, not the full screen (per Apple docs)
        // Use app.screenshot() for full screen, XCUIScreen.main.screenshot() for main display
        let screenshot = app.windows.firstMatch.screenshot()

        // Save as XCTest attachment (embedded in .xcresult bundle)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SCREENSHOT_ATTACHED: \(name) (\(screenshot.pngRepresentation.count) bytes)")
    }

    @MainActor
    func testScreenshotExample() throws {
        let app = launchApp()
        // Navigate to the desired state...
        app.buttons["Settings"].tap()
        sleep(2)
        saveScreenshot(app, name: "settings")
    }
}
```

### Running

```bash
# From an interactive terminal (Aqua session already available):
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -only-testing:MyAppUITests \
  -destination 'platform=macOS' \
  -resultBundlePath /tmp/MyAppResults

# From a Background session (e.g., OpenClaw), use a .command file via Aqua launchctl:
# (see "Running from a Background Session" below)
```

### Running from a Background Session (e.g., OpenClaw)

Direct `xcodebuild test` from an Aqua launchctl plist **will hang** — the XCTest harness requires a full interactive terminal session, not just Aqua window server access. The workaround is to open a `.command` file via Terminal.app:

```bash
# 1. Write the test command to a .command file
cat > /tmp/run_uitests.command << 'BASH'
#!/bin/bash
cd /path/to/your/project
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -only-testing:MyAppUITests \
  -destination 'platform=macOS' \
  -resultBundlePath /tmp/MyAppResults > /tmp/uitest.log 2>&1
echo "EXIT_CODE=$?" >> /tmp/uitest.log
BASH
chmod +x /tmp/run_uitests.command

# 2. Open it via Aqua launchctl (opens in Terminal.app)
LABEL="com.openclaw.uitest"
cat > /tmp/$LABEL.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>/tmp/run_uitests.command</string>
    </array>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "/tmp/$LABEL.plist"
launchctl kickstart "gui/$(id -u)/$LABEL"

# 3. Monitor progress
tail -f /tmp/uitest.log
```

### Extracting Screenshots from `.xcresult` Bundle

Screenshots saved as XCTest attachments are embedded in the `.xcresult` bundle. Extract them with `xcresulttool`:

```bash
# 1. Get the testsRef from the top-level result
xcrun xcresulttool get --path /tmp/MyAppResults.xcresult --format json --legacy

# 2. Drill into test summaries to find attachment payloadRefs
xcrun xcresulttool get --path /tmp/MyAppResults.xcresult --format json --legacy --id <summaryRef>

# 3. Export the screenshot by its payloadRef
xcrun xcresulttool export --legacy \
  --path /tmp/MyAppResults.xcresult \
  --output-path screenshots/my-screenshot.png \
  --id <payloadRef> \
  --type file
```

### Key Points

- **Window screenshots:** Use `app.windows.firstMatch.screenshot()` to capture just the app window. `app.screenshot()` captures the full screen (including desktop, other apps, menu bar).
- **XCTest attachments** are the recommended way to access screenshots — they're embedded in the `.xcresult` bundle at `-resultBundlePath`. Use `xcresulttool export --legacy` to extract them.
- **Sandbox file paths:** XCUITest runners are App Sandboxed. Direct writes to `/tmp/` will fail. If you need filesystem writes, use `NSTemporaryDirectory()` which resolves to `~/Library/Containers/<bundle-id>.xctrunner/Data/tmp/`
- `@MainActor` is required on test methods that interact with `XCUIApplication`
- Use `sleep()` after navigation to let the UI settle before capturing
- Use `waitForExistence(timeout:)` for elements that may take time to appear
- Element lookup strategies (in order of reliability): `app.buttons["Label"]`, `app.radioButtons["Label"]`, predicate-based `descendants(matching:)` search

### Limitations

- Requires Aqua session (display must be active for the GUI)
- Captures the app as-is — screenshots depend on app state/data
- Each test method re-launches the app (standard XCTest behavior), so test suites can be slow

---

## Method 2: ImageRenderer in `swift test`

**Best for:** Rendering isolated SwiftUI views to PNG. No dependencies on display, Aqua, or Simulator.

**Session requirement:** None — works from Background, SSH, CI, anywhere.

### Setup

Add a test target to your `Package.swift`:

```swift
.testTarget(
    name: "SnapshotTests",
    dependencies: ["YourModule"],
    path: "Tests/SnapshotTests"
),
```

### Writing a Snapshot Test

```swift
import SwiftUI
import Testing

@MainActor
@Test func renderMyView() async throws {
    let view = MyView()
        .frame(width: 800, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0

    guard let image = renderer.cgImage else {
        Issue.record("Failed to render image")
        return
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        Issue.record("Failed to create PNG")
        return
    }

    let path = "/tmp/my_view_snapshot.png"
    try data.write(to: URL(fileURLWithPath: path))
    print("Snapshot saved: \(path) (\(image.width)x\(image.height))")
}
```

### Running

```bash
cd YourPackage && swift test --filter SnapshotTests
```

### Key Points

- `@MainActor` is required — `ImageRenderer` must run on the main thread
- Set `.frame(width:height:)` explicitly — without it the view may render at zero size
- Use `.background(Color(nsColor: .windowBackgroundColor))` for an opaque background
- `renderer.scale = 2.0` gives Retina-quality output
- NavigationSplitView, List, and most SwiftUI views render correctly
- SwiftData `@Query` views won't work (no model container in test context) — pass static data instead

### Limitations

- Renders a single static frame — no scrolling, gestures, or animations
- Cannot capture a real running app — only standalone SwiftUI view trees
- Views must be self-contained (no environment objects from the app)

---

## Method 3: macOS Screen Capture via Aqua Launchctl

**Best for:** Capturing the actual Mac screen or a specific app window.

**Session requirement:** Aqua (use launchctl bootstrap from Background).

```bash
#!/bin/bash
# screenshot.sh [output_path] [app_to_activate]
OUTPUT="${1:-/tmp/screenshot.png}"
APP="${2:-}"
LABEL="com.openclaw.screenshot"

cat > /tmp/_capture.sh << BASH
#!/bin/bash
${APP:+osascript -e "tell application \"$APP\" to activate"}
${APP:+sleep 1}
/usr/sbin/screencapture -x "$OUTPUT"
BASH
chmod +x /tmp/_capture.sh

cat > /tmp/$LABEL.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/tmp/_capture.sh</string>
    </array>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "/tmp/$LABEL.plist"
launchctl kickstart "gui/$(id -u)/$LABEL"
sleep ${APP:+3}${APP:-2}
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
```

### Key Points

- Requires Screen Recording permission for the capturing process
- `-x` flag suppresses the capture sound
- Can activate a specific app before capturing
- Resize with `sips -Z <maxDim>` before sending

### Limitations

- Requires display to be awake
- Captures whatever is on screen — not isolated to a specific view
- Requires Screen Recording permission in System Settings

---

## Method 4: xcode-sim-automation (Interactive Simulator Control)

**Best for:** Full iOS app screenshots with interactive control — tap, scroll, type text, navigate between screens. The most capable technique.

**Session requirement:** Aqua for the test runner. The CLI controller works from Background.

**Repo:** [github.com/gestrich/xcode-sim-automation](https://github.com/gestrich/xcode-sim-automation)

### Architecture

This is a **split-session** design:

```
OpenClaw (Background) → CLI → JSON file → XCUITest loop (Aqua/Simulator) → Screenshot
```

1. An XCUITest (`InteractiveControlLoop`) runs in the Simulator via Aqua launchctl — it launches the app and polls a JSON command file
2. The `xcuitest-control` CLI runs from the Background session — writes commands, reads results
3. After each command, the loop writes a screenshot and UI hierarchy to `/tmp/`

This is the same architecture **Appium** uses (via WebDriverAgent), just with a JSON file instead of HTTP.

### Setup

1. Add `xcode-sim-automation` as an SPM dependency in your Xcode project
2. Add `XCUITestControl` to your UI test target
3. Create a test:

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

### Launching the Test Runner (from Background session)

```bash
# Write the xcodebuild command to a script
cat > /tmp/_interactive_test.sh << 'BASH'
#!/bin/bash
rm -rf /tmp/MyAppResults 2>/dev/null
cd /path/to/your/project
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:MyAppUITests/InteractiveControlTests/testInteractiveControl \
  -resultBundlePath /tmp/MyAppResults \
  -allowProvisioningUpdates > /tmp/interactive_test.log 2>&1
BASH
chmod +x /tmp/_interactive_test.sh

# Launch in Aqua session
LABEL="com.openclaw.interactive-test"
cat > /tmp/$LABEL.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/tmp/_interactive_test.sh</string>
    </array>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "/tmp/$LABEL.plist"
launchctl kickstart "gui/$(id -u)/$LABEL"
```

### Sending Commands (from Background session)

Wait for the test to start (monitor `/tmp/interactive_test.log` for the polling loop), then:

```bash
# Clone the repo to get the CLI tool
cd /path/to/xcode-sim-automation

# Take a screenshot
Tools/xcuitest-control screenshot
# → writes /tmp/xcuitest-screenshot.png and /tmp/xcuitest-hierarchy.txt

# Interact with the app
Tools/xcuitest-control tap --target "Settings"
Tools/xcuitest-control screenshot
Tools/xcuitest-control scroll --direction down
Tools/xcuitest-control type --value "hello" --target "searchField"

# Exit the test loop cleanly
Tools/xcuitest-control done
```

### Available Commands

| Command | Description |
|---------|-------------|
| `screenshot` | Capture screenshot + UI hierarchy |
| `tap --target "Label"` | Tap an element |
| `scroll --direction down` | Scroll in a direction |
| `type --value "text" --target "Field"` | Type into a text field |
| `adjust --target "slider" --value 0.75` | Set a slider value |
| `wait --value 2.0` | Pause for N seconds |
| `done` | Exit the test loop |
| `status` | Check command status |

### Key Points

- First CLI run builds the Swift binary (~24s), subsequent runs are instant
- Test session times out after 300s by default if no commands arrive — send periodic commands to keep alive
- The CLI tool is at `Tools/xcuitest-control` in the xcode-sim-automation repo
- Screenshots are full Simulator resolution (e.g., 1170×2532 for iPhone)
- Resize with `sips -Z <maxDim>` before sending

### Limitations

- Requires Aqua session (user logged in, display awake)
- Requires Simulator device runtime installed
- `xcodebuild test` from a Background session **always hangs** — must use Aqua launchctl
- App state affects what you see (need demo mode or test data for consistent screenshots)

---

## Quick Reference

| Method | Aqua Required | Simulator Required | Interactive | Best For |
|--------|:---:|:---:|:---:|---------|
| 1. XCUITests (macOS) | Yes | No | Semi | Real macOS app screenshots (preferred) |
| 2. ImageRenderer | No | No | No | Isolated SwiftUI views |
| 3. Screen Capture | Yes | No | No | Mac screen / app windows |
| 4. xcode-sim-automation | Yes (test runner) | Yes | Yes | Full iOS app with navigation |
