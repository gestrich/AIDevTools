## Fix Repository Matching to Only Use App-Configured Repositories

### Background

The feature that matches repositories from text (likely voice-transcribed or pasted text) is returning repositories that are not part of the user's configured repository list in the AIDevTools app. The matching logic appears to source repositories from somewhere other than the app's own repo store (e.g., scanning the filesystem or using a broader source). This needs to be fixed so that repository matching only returns repositories that exist in the user's configured repo list within the app.

## - [x] Phase 1: Interpret the Request

When executed, this phase will:
- Examine recent commits related to repo matching (especially `40b9131`, `035c718`, `a416dbf`, `21b9360`) to understand what has already been attempted
- Read any existing proposed docs (`docs/proposed/fix-repo-matching-to-app-repo-list.md` — noted as deleted in git status, check history)
- Trace the repository matching flow: find where text is parsed to extract repo references, where candidate repos are sourced, and where matching occurs
- Identify the current source of repositories used for matching (e.g., filesystem scan, git discovery, vs. the app's configured repo list)
- Identify the app's configured repo list storage (likely in `RepositorySDK` or `SkillService`)
- Document all relevant files, functions, and data flow

### Findings

#### Prior Work (Commits `40b9131`, `035c718`, `a416dbf`, `21b9360`)

These commits documented the issue and applied an initial fix:
- **`21b9360`**: Traced the repo matching flow and identified two root causes — prompt ambiguity and unnecessary filesystem access flags.
- **`a416dbf`**: Documented architectural constraints (4-layer architecture, `RepositoryStore` as single source of truth).
- **`035c718`**: Planned implementation phases 4–6.
- **`40b9131`**: Applied the fix — added explicit "You MUST select one of the listed repositories" constraint to the prompt and removed `dangerouslySkipPermissions`, `verbose`, and `printMode` flags from the `matchRepo` Claude CLI command.

The doc was then reset (all phases unchecked) to re-run the process from scratch.

#### Repository Matching Code Flow

The feature lives in `GeneratePlanUseCase.matchRepo()` (`GeneratePlanUseCase.swift:117–151`):

1. Takes `prompt: String` and `repositories: [RepositoryInfo]`
2. Formats repos as `- id: {UUID} | description: ... | recent focus: ...`
3. Sends prompt to Claude CLI via `ClaudeCLIClient.runStructured()` with a JSON schema constraining output to `{ repoId, interpretedRequest }`
4. Returns `RepoMatch` (defined in `ClaudeResponseModels.swift:1–11`)

**Caller validation** (`GeneratePlanUseCase.run()`, lines 88–91): The returned `repoId` UUID must exist in the passed `repositories` array, otherwise `GenerateError.repoNotFound` is thrown.

#### Where Repositories Are Sourced

| Entry Point | Flow | Source |
|-------------|------|--------|
| **Mac App** | `GeneratePlanSheet` → `PlanRunnerModel.generate()` → `GeneratePlanUseCase.run()` | `WorkspaceModel.repositories` → `LoadRepositoriesUseCase` → `RepositoryStore.loadAll()` → `{dataPath}/repositories.json` |
| **CLI** | `PlanRunnerPlanCommand` → `ReposCommand.makeStore()` → `RepositoryStore.loadAll()` | Same `repositories.json` |

Both paths source repos exclusively from the app's `repositories.json`. The `matchRepo()` prompt only includes repos from the passed array.

#### Current State of the Fix (Commit `40b9131`)

The `matchRepo()` function now:
- Includes explicit constraint: "You MUST select one of the listed repositories. Do not reference or suggest any repository not in this list."
- Uses only `outputFormat` and `jsonSchema` flags — no `dangerouslySkipPermissions`, `verbose`, or `printMode`
- Does **not** pass a `workingDirectory`, keeping Claude CLI sandboxed without filesystem access

#### Uncommitted Working Tree Changes

The working tree contains additional changes **unrelated to the repo matching fix**:
- `ConfigurationEditSheet.swift` / `RepositoriesSettingsView.swift` / `SettingsView.swift`: Expanded repo configuration UI (description, skills, architecture docs, verification, PR settings)
- `WorkspaceModel.swift`: `addRepository()` now accepts full `RepositoryInfo` and persists all fields
- `ReposCommand.swift`: CLI `update-repo` expanded with `--description`, `--github-user`, `--recent-focus`, `--skills`, `--architecture-docs`, `--verification-commands`, `--verification-notes`, `--pr-base-branch`, `--pr-branch-naming`, `--pr-template`, `--pr-notes`
- `EntryPoint.swift` / `Package.swift`: Added `LoggingSDK` dependency and bootstrap
- `ClaudeStructuredOutputParser.swift`: Handle edge case where CLI marks `is_error=true` but `subtype=success` with valid output
- `PlanRunnerFeatureTests.swift`: Test updates

There is also a `selectedRepository` bypass in the working tree:
- `GeneratePlanUseCase.Options` has a `selectedRepository: RepositoryInfo?` field
- When provided, `run()` skips `matchRepo()` entirely and uses the selected repo
- The Mac app's `GeneratePlanSheet` has a "Match repository from text" toggle (default off) that controls this

#### Root Cause Analysis

Two root causes were identified and already fixed in commit `40b9131`:

1. **Prompt ambiguity**: The prompt said "Available repositories" without explicitly constraining Claude to choose only from that list. Fixed by adding an explicit constraint.
2. **Unnecessary filesystem access**: `matchRepo()` ran Claude CLI with `dangerouslySkipPermissions=true`, `verbose=true`, and `printMode=true`, allowing Claude to discover repos via the filesystem. Since repo matching is pure text-in/JSON-out (no tool access needed), these flags were removed.

#### Key Files

| File | Role |
|------|------|
| `AIDevToolsKit/Sources/Features/PlanRunnerFeature/usecases/GeneratePlanUseCase.swift` | `matchRepo()` (lines 117–151), `run()` with `selectedRepository` bypass (lines 76–93) |
| `AIDevToolsKit/Sources/Features/PlanRunnerFeature/services/ClaudeResponseModels.swift` | `RepoMatch` struct (lines 1–11) |
| `AIDevToolsKit/Sources/SDKs/ClaudeCLISDK/ClaudeCLIClient.swift` | `runStructured()` signature (lines 143–158) |
| `AIDevToolsKit/Sources/SDKs/ClaudeCLISDK/ClaudeCLI.swift` | `Claude` command struct with flags (lines 9–20) |
| `AIDevToolsKit/Sources/SDKs/RepositorySDK/RepositoryStore.swift` | `loadAll()` — single source of truth for repo list |
| `AIDevToolsKit/Sources/SDKs/RepositorySDK/RepositoryInfo.swift` | `RepositoryInfo` model |
| `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/PlanRunnerModel.swift` | Mac app `generate()` integration (lines 142–182) |
| `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PlanRunnerPlanCommand.swift` | CLI plan command — always triggers matching (no `selectedRepository`) |

## - [x] Phase 2: Gather Architectural Guidance

When executed, this phase will:
- Read `AIDevToolsKit/ARCHITECTURE.md` to understand layer boundaries and module responsibilities
- Review the `RepositorySDK` module (repository configuration and storage) to understand how configured repos are stored and accessed
- Review the `SkillService` module (skill configuration and repository settings) for its role in repo management
- Check relevant skills and architecture docs for patterns around repository access
- Summarize key architectural constraints that apply to this fix (e.g., which layer should own the matching logic, how to properly access the configured repo list without violating dependency rules)

### Findings

#### 4-Layer Architecture

| Layer | May Depend On | Key Modules for This Fix |
|-------|---------------|--------------------------|
| **Apps** (CLI, Mac) | Features, Services, SDKs | `AIDevToolsKitCLI`, `AIDevToolsKitMac` — entry points that wire up use cases |
| **Features** | Services, SDKs | `PlanRunnerFeature` — owns `GeneratePlanUseCase` and `matchRepo()` |
| **Services** | SDKs | `SkillService` — skill data models; `PlanRunnerService` — plan settings |
| **SDKs** | (none) | `RepositorySDK` — repo storage; `ClaudeCLISDK` — Claude CLI process management |

#### RepositorySDK — Single Source of Truth for Repos

- **Storage**: JSON file at `{dataPath}/repositories.json`, managed by `RepositoryStore`
- **Model**: `RepositoryInfo` — id (UUID), path, name, plus optional metadata (description, skills, architectureDocs, verification, pullRequest config)
- **Access**: `RepositoryStore.loadAll()` reads all configured repos; `find(byID:)` and `find(byPath:)` for lookups
- **Constraint**: SDKs have no internal dependencies, so `RepositorySDK` cannot reference any higher layer

#### SkillService — Read-Only Skill Discovery (No Repo Mutation)

- Defines `Skill` and `ReferenceFile` data models
- Skills are discovered dynamically from the filesystem by `SkillScannerSDK`, not stored in `RepositoryInfo` (though `RepositoryInfo.skills` can hold static references)
- Does not own or manage the repository list — purely a consumer of `RepositoryInfo.path` for scanning
- No direct involvement in the repo matching flow

#### Architectural Constraints for This Fix

1. **`matchRepo()` belongs in the Features layer** (`PlanRunnerFeature`). It orchestrates business logic (formatting repos, calling Claude CLI, validating output) — this is the correct layer per the architecture.
2. **Repository list must come from `RepositoryStore`** (SDK layer). Both CLI and Mac app already source repos from `RepositoryStore.loadAll()` before passing them to `GeneratePlanUseCase.run()`. No alternative repo source should be introduced.
3. **`matchRepo()` must not access the filesystem for repo discovery**. It receives `[RepositoryInfo]` as a parameter — it should never scan for repos itself. The fix in commit `40b9131` correctly removed filesystem access flags.
4. **Caller-side validation is the safety net**. `GeneratePlanUseCase.run()` validates the returned `repoId` UUID exists in the passed array (`GenerateError.repoNotFound`). This catch remains important even with prompt constraints.
5. **The `selectedRepository` bypass is architecturally sound**. When the Mac app provides a pre-selected repo, skipping `matchRepo()` entirely avoids an unnecessary Claude CLI call while staying within the same use case boundary.
6. **No cross-layer shortcuts**. `GeneratePlanUseCase` (Features) correctly depends on `ClaudeCLISDK` and `RepositorySDK` (SDKs). It must not reach into Apps or Services for repo data.

## - [ ] Phase 3: Plan the Implementation

When executed, this phase will:
- Use findings from Phases 1 and 2 to create concrete implementation steps
- Append new phases (Phase 4 through N) to this document, each specifying:
  - What to implement
  - Which files to modify
  - Which architectural documents to reference
  - Acceptance criteria
- Append a Testing/Verification phase
- Append a Create Pull Request phase (using `gh pr create --draft`)
- Generate the architecture diagram JSON file (`fix-repo-matching-to-app-repo-list-architecture.json`) mapping all changed files to their modules and layers
