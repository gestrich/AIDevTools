## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Eval system debugging — artifact paths, CLI commands, grading layers |
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) and dependency rules |

## Background

The `DeterministicGrader` checks whether a skill was invoked by pattern-matching skill names against trace command strings. This breaks for nested skill paths (e.g. `.claude/skills/ios-26/merge-insurance-policy.md`) because the matcher only looks for `skills/<name>/`.

Meanwhile, `SkillScanner` already discovers all skills with their full paths as `SkillInfo` models. But `RunEvalsUseCase` and `DeterministicGrader` never see this data — they only get a bare string like `"merge-insurance-policy"` from the eval case JSON. The fix is to thread skill models through the eval pipeline so the grader can match against known paths instead of guessing.

## Phases

## - [x] Phase 1: Add `SkillScannerSDK` dependency to `EvalService`

**Skills used**: `swift-architecture`
**Principles applied**: Verified downward dependency flow (Services → SDKs) per 4-layer architecture

**Skills to read**: `swift-architecture`

`SkillInfo` lives in `SkillScannerSDK` (SDKs layer). `EvalService` is at the Services layer, so it can depend on SDKs. Add `SkillScannerSDK` as a dependency of `EvalService` in `Package.swift`. This lets `DeterministicGrader` accept `[SkillInfo]` directly.

- Edit `Package.swift`: add `"SkillScannerSDK"` to `EvalService`'s dependencies array
- Edit `EvalServiceTests` to also depend on `SkillScannerSDK`

## - [x] Phase 2: Update `DeterministicGrader` to accept `[SkillInfo]`

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Added `SkillInfo.relativePath(to:)` instance method per feedback; falls back to convention-based matching when no SkillInfo available

**Skills to read**: `ai-dev-tools-debug`

Update the `grade()` method signature to accept `skills: [SkillInfo]` instead of relying on `matchesSkillPath` string matching. The grader should:

1. Add `skills: [SkillInfo] = []` parameter to `grade(case:resultText:traceCommands:toolEvents:providerCapabilities:repoRoot:diff:)`
2. For `skillMustBeInvoked`: look up the skill name in the `[SkillInfo]` array, get its `path`, and check if the path (relative to repo root) appears in trace commands or `toolEvents`. Fall back to the existing `matchesSkillPath` if no matching `SkillInfo` found (for cases where skills weren't scanned).
3. Same for `skillMustNotBeInvoked`
4. Remove or deprecate the `matchesSkillPath` private function once the model-based matching is in place

Files to modify:
- `AIDevToolsKit/Sources/EvalService/DeterministicGrader.swift`

## - [x] Phase 3: Add `SkillScannerSDK` dependency to `EvalFeature` and scan skills in `RunEvalsUseCase`

**Skills used**: `swift-architecture`
**Principles applied**: Skills scanned once in RunEvalsUseCase and threaded through to grading; errors propagated rather than swallowed per feedback

**Skills to read**: `swift-architecture`

`RunEvalsUseCase` has access to `repoRoot`. It should scan skills once at the start of a run and pass them through to grading.

1. Add `SkillScannerSDK` to `EvalFeature`'s dependencies in `Package.swift`
2. In `RunEvalsUseCase.run()`, call `SkillScanner().scanSkills(at: repoRoot)` once before the case loop
3. Pass the resulting `[SkillInfo]` to `DeterministicGrader.grade()` via `RunCaseUseCase`

Files to modify:
- `Package.swift`
- `AIDevToolsKit/Sources/EvalFeature/RunEvalsUseCase.swift`
- `AIDevToolsKit/Sources/EvalFeature/RunCaseUseCase.swift` (if grading happens here)

## - [x] Phase 4: Update tests

**Skills used**: `swift-testing`
**Principles applied**: Arrange-Act-Assert pattern; tested nested skill paths for both mustBeInvoked and mustNotBeInvoked

**Skills to read**: `swift-testing`

1. Update existing `DeterministicGraderTests` that test skill invocation to pass `[SkillInfo]` with known paths
2. Add a test for nested skill paths (e.g. skill at `ios-26/merge-insurance-policy.md`) to confirm the model-based matching works
3. Verify all existing tests still pass

Files to modify:
- `AIDevToolsKit/Tests/EvalServiceTests/DeterministicGraderTests.swift`

## - [x] Phase 5: Validation

Run the full test suite:

```bash
cd AIDevToolsKit && swift test
```

Then build the Mac app:

```bash
xcodebuild build -scheme AIDevTools -destination 'platform=macOS' -quiet
```

Success criteria:
- All tests pass including new nested-path skill test
- Mac app builds cleanly
- The `merge-insurance-policy` eval case's `skillMustBeInvoked` assertion would now match against the real path from `SkillInfo` rather than string pattern matching
