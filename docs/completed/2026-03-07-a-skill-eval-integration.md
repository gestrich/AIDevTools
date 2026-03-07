## Relevant Skills

No CLAUDE.md exists for this project, so no project-specific skills to reference. The existing codebase conventions (layered architecture: Apps → Features → Services → SDKs) serve as the guide.

## Background

The project already has a full eval infrastructure (EvalService, EvalSDK, EvalFeature) that supports running eval cases against Claude/Codex providers with deterministic and rubric-based grading. However, this infrastructure is disconnected from the skill browser — there's no way to configure where evals live for a repository, run evals from the Mac app, or associate evals with specific skills.

Bill wants to:
1. Configure eval directories per repository (in settings/repo config)
2. Run evals from within the skill detail view in the Mac app
3. See progress while evals run
4. See results when evals complete
5. Also be invocable via CLI
6. Have example eval cases to demonstrate the feature

The eval directory structure expected by the existing `RunEvalsUseCase` is:
```
evalDirectory/
  cases/
    suite1.jsonl       # one line per EvalCase
  result_output_schema.json
  rubric_output_schema.json
```

## Phases

## - [x] Phase 1: Add eval directory to RepositoryConfiguration

**Principles applied**: Minimal model change — added optional field with no API surface changes to AddRepositoryUseCase

Add an optional `evalDirectory` URL to `RepositoryConfiguration` so each repo can specify where its evals live. Update the `RepositoryConfigurationStore` serialization. This is a simple model change.

**Files to modify:**
- `AIDevToolsKit/Sources/SkillService/Models/RepositoryConfiguration.swift` — add `evalDirectory: URL?`
- `AIDevToolsKit/Sources/SkillBrowserFeature/AddRepositoryUseCase.swift` — accept optional eval path
- `AIDevToolsKit/Tests/SkillServiceTests/RepositoryConfigurationStoreTests.swift` — update for new field

**Details:**
- Add `evalDirectory: URL?` field to `RepositoryConfiguration`
- No backward compatibility needed — update the existing `repositories.json` on disk (or delete and re-add repos)
- Create a sample eval directory on the Desktop (e.g., `~/Desktop/AIDevTools/evals/`) as default location for examples

## - [x] Phase 2: UI for configuring eval directory per repo

**Principles applied**: Followed existing use case pattern (AddRepository/RemoveRepository) for UpdateRepositoryUseCase; minimal UI addition via safeAreaInset

Add a way in the Mac app to set the eval directory for a repository. This could be a button/section in the sidebar or a popover when right-clicking a repo.

**Files to modify:**
- `AIDevTools/Views/SkillBrowserView.swift` — add UI to set eval directory on selected repo
- `AIDevTools/Models/SkillBrowserModel.swift` — add method to update repo's eval directory
- `AIDevToolsKit/Sources/SkillBrowserFeature/` — add `UpdateRepositoryUseCase` or extend existing

**Details:**
- Folder picker to select the eval directory
- Show current eval directory path (or "Not configured") in the repo section
- Persist via the existing `RepositoryConfigurationStore`

## - [x] Phase 3: Eval runner model and progress tracking

**Principles applied**: Followed existing `SkillBrowserModel` pattern (`@MainActor @Observable`, state enum, DI via init). Refactored `RunEvalsUseCase.run()` to return `[EvalSummary]` and accept optional progress callback rather than only printing to stdout.

Create an observable model that wraps `RunEvalsUseCase` for the Mac app, providing progress updates and result state.

**Files to create/modify:**
- `AIDevTools/Models/EvalRunnerModel.swift` — new `@Observable` model
- Wire up to `AIDevToolsApp.swift` via environment

**Details:**
- States: idle, running(progress), completed(results), error
- Progress: track current case index / total count
- Results: store `[EvalSummary]` from run
- Method: `runEvals(evalDirectory:, provider:, skillFilter:)` that calls `RunEvalsUseCase`
- The existing `RunEvalsUseCase` prints to stdout — we need to either:
  - (a) Refactor it to use a delegate/callback for progress, or
  - (b) Wrap it and capture output
  - Option (a) is cleaner: add a progress callback `(CaseResult) -> Void` to `RunEvalsUseCase.run()`
- This model needs access to `RunEvalsUseCase` which depends on `ProviderAdapterProtocol` — we'll use the existing adapter factory

## - [x] Phase 4: Eval results view in skill detail

**Principles applied**: Top-level Skill/Evals segmented picker only shown when eval directory is configured; EvalResultsView uses environment-injected EvalRunnerModel; expandable rows for failure details

Add an "Evals" section or tab to the skill detail view that lets you run and view eval results.

**Files to modify:**
- `AIDevTools/Views/SkillDetailView.swift` — add eval tab or button
- `AIDevTools/Views/EvalResultsView.swift` — new view for displaying results

**Details:**
- Add a "Run Evals" button in the skill detail view (visible when eval directory is configured)
- While running: show progress bar with case count
- When complete: show pass/fail summary and per-case results
  - Green checkmark for pass, red X for fail
  - Expandable rows showing error details for failed cases
  - Provider name displayed
- Filter evals to the current skill's suite if the naming convention matches (e.g., suite name = skill name), otherwise run all
- Provider selector (Claude, Codex, Both) — default to Claude

## - [x] Phase 5: CLI command updates

**Principles applied**: Kept command thin — parsing inputs and delegating. Business logic lives in extensions on `RepositoryConfigurationStore` in a `+CLI` file within the CLI target.

The existing `run-evals` CLI command already works. Extend it to accept a repository path and auto-resolve the eval directory from the stored config.

**Files to modify:**
- `AIDevToolsKit/Sources/AIDevToolsKitApp/RunEvalsCommand.swift` — add `--repo` option

**Details:**
- `--repo <path>` looks up the repository's eval directory from `RepositoryConfigurationStore`
- Falls back to existing `--eval-dir` behavior if `--repo` not specified
- Both options can't be specified simultaneously

## - [x] Phase 6: Create example eval cases

**Skills used**: None
**Principles applied**: Matched existing `EvalCase` model fields (snake_case JSON keys decoded via `convertFromSnakeCase`); rubric schema matches `RubricPayload` structure; included both deterministic and rubric-graded cases

Create example eval directories with sample cases to demonstrate the feature.

**Files to create:**
- `Examples/evals/cases/commit-skill.jsonl` — eval cases for a "commit" skill
- `Examples/evals/result_output_schema.json` — basic result schema
- `Examples/evals/rubric_output_schema.json` — rubric grading schema

**Details:**
- 3-5 simple eval cases that test a hypothetical "commit message" skill:
  - Given a diff, generate a commit message
  - Must include certain keywords
  - Must not include certain phrases
  - One rubric-graded case checking quality
- These serve as documentation and a template for users creating their own evals
- Include a README.md in the Examples/evals/ directory explaining the structure

**Also created:** Real eval cases for `~/Developer/work/ios` repo targeting the `feature-flags` skill:
- Location: `~/Desktop/ios-evals/` (not in repo — configured via Mac app)
- 7 cases in `cases/feature-flags.jsonl` covering: flag creation, Swift/ObjC querying, typed accessors, key duplication avoidance, lifecycle cleanup (rubric-graded), and development phase defaults
- Includes `result_output_schema.json` and `rubric_output_schema.json`

## - [x] Phase 7: Validation

**Approach:**
- Run existing eval unit tests: `swift test --filter EvalFeatureTests && swift test --filter EvalServiceTests && swift test --filter EvalSDKTests`
- Add new tests for:
  - `RepositoryConfiguration` with eval directory serialization round-trip
  - `RunEvalsUseCase` progress callback
  - EvalRunnerModel state transitions
- Build the Mac app: `xcodebuild build -scheme AIDevTools`
- Manual verification: configure eval directory on a repo, run evals from skill detail, verify progress and results display
