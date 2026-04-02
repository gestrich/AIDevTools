## Relevant Skills

| Skill | Description |
|-------|-------------|
| `logging` | Logging infrastructure — adding log statements, debugging via logs |

## Background

Two bugs were found in `RunChainTaskUseCase` during a real PR creation run on the `ff-ios` repo.

### Bug 1: "Run Next Task" runs against a task that already has a draft PR

When "Run Next Task" is invoked (no `taskIndex` specified), the auto-selection logic in
`RunChainTaskUseCase.run()` picks the first incomplete task:

```swift
nextStep = codeSteps.first(where: { !$0.isCompleted })
```

This check only looks at the `isCompleted` flag in `spec.md`. It does **not** check whether
a remote branch (and thus a draft PR) already exists for that task. If a task has a branch like
`claude-chain-{project}-{hash}` pushed to origin, running "next task" will re-run the AI agent
on it, overwriting the existing branch's work and re-creating the PR.

Root cause: `spec.md` marks a task complete only after a PR is created and merged. During the
draft-PR-open window, the task is not complete but also should not be re-run.

Relevant code: `RunChainTaskUseCase.swift` lines 147–152.

### Bug 2: PR summary comment contains raw JSON

After the AI run, a summary prompt is sent to Claude to generate a markdown PR description.
The result is captured via:

```swift
summaryContent = summaryResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
```

`AIClientResult.stdout` is the raw Claude CLI JSON stream (e.g.
`{"type":"system","subtype":"init",...}`), not plain text. The formatted text lives in the
`onOutput` callback or can be assembled from `.textDelta` stream events. As a result, the PR
comment contains several KB of raw JSON instead of the intended markdown summary.

The same bug exists in `FinalizeStagedTaskUseCase.swift` line 186.

Relevant code:
- `RunChainTaskUseCase.swift` line 369
- `FinalizeStagedTaskUseCase.swift` line 186
- `AIClient.swift` — `AIClientResult.stdout` is always raw JSON stream when using Claude CLI

---

## Phases

## - [x] Phase 1: Reproduce Bug 1 — "Run Next Task" hits draft PR task

**Skills used**: none
**Principles applied**: Used existing `enrichment-test` project state as reproduction evidence instead of triggering a live AI agent run. Code analysis at `RunChainTaskUseCase.swift:151` plus the existing branch/PR state together prove the bug without additional cost.

Set up a small reproduction in `../claude-chain-demo` so we can observe the bug with real
GitHub PRs.

Steps:
1. Confirm `../claude-chain-demo` is a git repo pointed at a real (or test) GitHub remote.
2. Create (or reuse) a chain project there with at least 2 incomplete tasks in `spec.md`.
3. From the Mac app (or CLI), run "Run Next Task" once. Verify a draft PR is created for
   task 1 and that branch `claude-chain-{project}-{hash1}` now exists on the remote.
4. From the Mac app, invoke "Run Next Task" again **without merging or completing task 1**.
5. Observe: does the tool pick task 1 again (the bug) or task 2 (correct)?
6. Record PR numbers and branch names for the post-fix comparison.

Expected (buggy) behavior: the second "Run Next Task" selects task 1 again because
`spec.md` still has it as incomplete.

**Reproduction findings** (gestrich/claude-chain-demo, project: `enrichment-test`):

- `../claude-chain-demo` is a real GitHub repo at `https://github.com/gestrich/claude-chain-demo`. ✅
- `enrichment-test/spec.md` has 2 incomplete tasks:
  - `[ ]` Task 2: Create `enrichment-test/file-2.txt`
  - `[ ]` Task 3: Create `enrichment-test/file-3.txt`
- Branch `claude-chain-enrichment-test-f8458cd8` already exists on the remote for task 2. ✅
- Draft PR **#93** ("ClaudeChain: [enrichment-test] Create enrichment-test/file-2.txt") is open on that branch. ✅
- `RunChainTaskUseCase.swift:151` selects `codeSteps.first(where: { !$0.isCompleted })` — no branch check.
- Conclusion: calling "Run Next Task" now would select task 2 again despite PR #93 existing. Bug confirmed via code analysis + existing state.

Branches on remote for post-fix comparison:
- Task 2 branch: `claude-chain-enrichment-test-f8458cd8` (PR #93)
- Task 3 branch: none yet (no PR)

## - [ ] Phase 2: Reproduce Bug 2 — Raw JSON in PR comment

**Skills to read**: none

During Phase 1, step 3, the summary comment will already be posted. Read it on GitHub.

Steps:
1. Open the PR created in Phase 1.
2. Check the first comment posted by the automation.
3. Confirm whether the comment body contains raw JSON (`{"type":"system"...}`) or a
   proper markdown summary.
4. Screenshot / note the exact content for the bug report in the plan doc.

Expected (buggy) behavior: the comment contains one or more lines of JSON stream events
starting with `{"type":`.

## - [ ] Phase 3: Fix Bug 1 — Skip tasks with existing remote branches

**Skills to read**: `logging`

Modify the auto next-task selection in `RunChainTaskUseCase.run()` to exclude tasks that
already have a remote branch.

Implementation:

1. Add `LsRemote` command to `GitCLI.swift` (alphabetical order):
   ```swift
   @CLICommand("ls-remote")
   public struct LsRemote {
       @Flag("--heads") public var heads: Bool = false
       @Positional public var remote: String
       @Positional public var pattern: String?
   }
   ```

2. Add `listRemoteBranches(matching:remote:workingDirectory:) -> [String]` to `GitClient.swift`
   that runs `git ls-remote --heads origin refs/heads/<pattern>` and parses the tab-separated
   output to return branch name strings.

3. In `RunChainTaskUseCase.run()`, replace the no-`taskIndex` branch selection:
   ```swift
   // Before:
   nextStep = codeSteps.first(where: { !$0.isCompleted })

   // After:
   let projectPattern = "claude-chain-\(options.projectName)-*"
   let existingBranches = Set(
       (try? await git.listRemoteBranches(matching: projectPattern, workingDirectory: repoDir)) ?? []
   )
   nextStep = codeSteps.first(where: { step in
       guard !step.isCompleted else { return false }
       let hash = TaskService.generateTaskHash(description: step.description)
       let branch = PRService.formatBranchName(projectName: options.projectName, taskHash: hash)
       return !existingBranches.contains(branch)
   })
   ```

4. Add a logger debug line noting how many existing branches were found and which task was
   selected.

## - [ ] Phase 4: Fix Bug 2 — Extract plain text from summary AI result

**Skills to read**: `logging`

Fix both `RunChainTaskUseCase.swift` and `FinalizeStagedTaskUseCase.swift` to collect the
AI text response from stream events instead of from `stdout`.

Implementation:

1. Add a file-private helper class near the top of each affected file:
   ```swift
   private final class TextAccumulator: @unchecked Sendable {
       var text = ""
   }
   ```

2. In `RunChainTaskUseCase.run()` Phase 6 (summary generation), replace the `onOutput: nil`
   and `summaryResult.stdout` pattern:
   ```swift
   let summaryText = TextAccumulator()
   let summaryResult = try await client.run(
       prompt: summaryPrompt,
       options: summaryOptions,
       onOutput: { chunk in summaryText.text += chunk },
       onStreamEvent: { event in
           onProgress?(.summaryStreamEvent(event))
       }
   )
   summaryContent = summaryText.text.trimmingCharacters(in: .whitespacesAndNewlines)
   if summaryContent?.isEmpty == true { summaryContent = nil }
   ```

   Note: `onOutput` receives the formatted text (plain text + tool use markers). For the
   summary prompt there should be no tool use, but if there is, the formatted output still
   produces readable text. This is preferable to `.textDelta` stream events because no
   actor/await is needed inside the sync closure.

3. Apply the same change to `FinalizeStagedTaskUseCase.swift` line 178–186.

## - [ ] Phase 5: Validate fixes with claude-chain-demo

**Skills to read**: none

Re-run the reproduction steps from Phases 1–2 after applying the fixes.

1. Reset `claude-chain-demo` to a clean state (delete previously created branches/PRs or
   use a fresh project name).
2. Run "Run Next Task" once → verify a draft PR is created for task 1.
3. Run "Run Next Task" again → verify task 2 is selected (not task 1).
4. Open the PR comment → verify it contains a readable markdown summary, not raw JSON.
5. If both pass, the fixes are confirmed.
