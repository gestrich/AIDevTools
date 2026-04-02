## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer app architecture patterns — use when deciding where each fix lives |

## Background

Three gaps were observed when creating a PR via claude-chain for https://github.com/jeppesen-foreflight/ff-ios/pull/19669:

1. **Assignee not added** — `ProjectConfiguration.assignees` is parsed from the config YAML but `RunChainTaskUseCase` and `FinalizeStagedTaskUseCase` never pass `--assignee` to `gh pr create`.
2. **Reviewers not added** — same root cause; `ProjectConfiguration.reviewers` is similarly ignored.
3. **Mac app PR list doesn't refresh** — after `ClaudeChainModel.executeChain` (or `createPRFromStaged`) completes, the PR list stays stale until the user manually hits the refresh button. A call to `refreshChainDetail` should be triggered automatically.

The Python original (`/Users/bill/Developer/personal/claude-chain`) did handle assignees and reviewers (`finalize.py:219-222`). Both were dropped during the Swift port.

The two use cases (`RunChainTaskUseCase` and `FinalizeStagedTaskUseCase`) already have access to `ProjectRepository`, which can load `ProjectConfiguration` via `loadLocalConfiguration(project:)`. The configuration is available at the `claude-chain/<project-name>/` directory — `repository` is already instantiated in `RunChainTaskUseCase.run()` by line ~118.

## Phases

## - [x] Phase 1: Add assignees/reviewers to `RunChainTaskUseCase`

**Skills to read**: `swift-architecture`

In `AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/RunChainTaskUseCase.swift`:

- After the `ProjectRepository` is instantiated (~line 118), load the project configuration:
  ```swift
  let projectConfig = try? repository.loadLocalConfiguration(project: project)
  ```
- In the `gh pr create` args block (~lines 325–336), append `--assignee` for each entry in `projectConfig?.assignees` and `--reviewer` for each entry in `projectConfig?.reviewers`:
  ```swift
  for assignee in projectConfig?.assignees ?? [] {
      prCreateArgs += ["--assignee", assignee]
  }
  for reviewer in projectConfig?.reviewers ?? [] {
      prCreateArgs += ["--reviewer", reviewer]
  }
  ```
- Use `try?` (not `try`) so a missing or malformed config doesn't abort the run.

## - [x] Phase 2: Add assignees/reviewers to `FinalizeStagedTaskUseCase`

**Skills to read**: `swift-architecture`

In `AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/FinalizeStagedTaskUseCase.swift`:

- The `ProjectRepository` is already instantiated early in `run()`. Load the config the same way as Phase 1.
- Apply the same `--assignee` / `--reviewer` additions to the `prCreateArgs` block (~lines 139–150).
- The `runDry` path skips actual PR creation, so no changes are needed there.

## - [x] Phase 3: Auto-refresh PR list in Mac app after PR creation

In `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift`:

**`executeChain` (~line 151)**  
After `state = .completed(result: result)`, add:
```swift
refreshChainDetail(projectName: project.name, repoPath: repoPath)
```

**`createPRFromStaged` (~line 208)**  
After `state = .completed(result: result)` (inside the success branch ~line 231), add:
```swift
refreshChainDetail(projectName: project.name, repoPath: repoPath)
```

`refreshChainDetail` clears the cached network-fetch guard and calls `loadChainDetail`, which re-fetches from GitHub — matching what the manual refresh button does.

## - [ ] Phase 4: Validation

- Run the test suite to catch any regressions:
  ```
  swift test --filter ClaudeChainFeatureTests
  swift test --filter ClaudeChainModelTests
  ```
- Manually smoke-test by running a chain task against a test repo and verifying:
  - The created PR has the expected assignee(s) and reviewer(s) set.
  - After the run completes in the Mac app, the PR list updates automatically without pressing the refresh button.
- If a test repo with a `.claude-chain/<project>/config.yaml` containing `assignees`/`reviewers` entries isn't available, add a focused unit test to `RunChainTaskUseCaseTests` (or similar) that confirms the args include `--assignee` when the config provides one.
