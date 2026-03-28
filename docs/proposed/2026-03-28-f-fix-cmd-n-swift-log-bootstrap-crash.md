# Fix CMD+N Crash in swift-log Bootstrap

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | Architecture guidance for moving bootstrap to app entry point |

## Background

Pressing CMD+N crashes the app with a precondition failure in swift-log:

```swift
mutating func replaceUnderlying(_ underlying: BoxedType, validate: Bool) {
    precondition(!validate || !self.initialized, self.violationErrorMessage)
```

**Root cause:** `LoggingSystem.bootstrap()` is called from `AIDevToolsKitMacEntryView.init()` (line 24). When CMD+N opens a new window, SwiftUI creates a new `WindowGroup` instance, which calls `AIDevToolsKitMacEntryView.init()` again — triggering a second `LoggingSystem.bootstrap()` call. swift-log enforces that bootstrap is called exactly once; the second call hits the precondition and crashes.

The CLI already guards against this with a `bootstrapped` flag in `EntryPoint.swift:8-17`. The Mac app needs the same protection.

**Key files:**
- `AIDevTools/AIDevToolsApp.swift` — @main app struct (no init, no bootstrap call)
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/AIDevToolsKitMacEntryView.swift:24` — bootstrap call that gets repeated
- `AIDevToolsKit/Sources/SDKs/LoggingSDK/AIDevToolsLogging.swift` — bootstrap implementation

## - [x] Phase 1: Move Bootstrap to App Init

**Skills to read**: `swift-architecture`
**Skills used**: `none` (swift-architecture skill not found)
**Principles applied**: Moved one-time initialization from a view (re-created per window) to the `@main` App struct (created once), added `LoggingSDK` as an explicit Xcode target dependency to satisfy `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`.

Move `AIDevToolsLogging.bootstrap()` out of `AIDevToolsKitMacEntryView.init()` and into `AIDevToolsApp.init()`, ensuring it runs exactly once regardless of how many windows are created.

### Tasks

1. **Add an `init()` to `AIDevToolsApp`** in `AIDevTools/AIDevToolsApp.swift`:
   - Add `import LoggingSDK` (or `import AIDevToolsKitMac` if re-exporting is preferred)
   - Add `init() { AIDevToolsLogging.bootstrap() }` to the `AIDevToolsApp` struct

2. **Remove `AIDevToolsLogging.bootstrap()`** from `AIDevToolsKitMacEntryView.init()` at line 24 of `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/AIDevToolsKitMacEntryView.swift`
   - Also remove the `import LoggingSDK` from this file if it's no longer used after removing the bootstrap call

### Expected outcome
- `LoggingSystem.bootstrap()` is called once when the app launches
- CMD+N creates new windows without re-bootstrapping the logger
- No crash on CMD+N

## - [x] Phase 2: Validation

**Skills used**: `none`
**Principles applied**: Verified build succeeds with `xcodebuild`. Pre-existing SkillScanner test failures are unrelated to this change. Manual verification (CMD+N, Settings, log output) requires human testing.

Build and verify the fix.

### Tasks

1. **Build the project:**
   ```bash
   cd /Users/bill/Developer/personal/AIDevTools && swift build
   ```

2. **Run tests (if available):**
   ```bash
   cd /Users/bill/Developer/personal/AIDevTools && swift test
   ```

3. **Manual verification:**
   - Launch the app
   - Press CMD+N to open a new window — confirm no crash
   - Open Settings — confirm no crash
   - Verify logging still works (check `~/Library/Logs/AIDevTools/aidevtools.log` for output)
