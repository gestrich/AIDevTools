## Fix Repository Matching to Only Source Repos from App's Repo List

### Background

The feature that matches repositories from text (likely voice-transcribed or pasted text) is currently pulling in repositories that are not part of the user's configured repository list in the AIDevTools app. The matching logic appears to be sourcing repositories from somewhere other than the app's own repo store. This needs to be fixed so that repository matching only returns repositories that exist in the user's configured repo list within the app.

## - [x] Phase 1: Interpret the Request

When executed, this phase will explore the codebase and recent commits to understand what the voice transcription is asking for. The request text — "The feature to match repository from text is pulling repos that are not in my repo list in this app. I'm not sure where it is coming from. I'd like it to only source repos from this repo." — likely means:

- There is a feature that extracts/matches repository references from text input
- It is returning repositories not in the user's configured list
- The fix should constrain matching to only repositories configured in the app

This phase will find the relevant code for repository-from-text matching, identify where repositories are being sourced, and document the current behavior. It will look at recent commits and search for repository matching logic. Document findings underneath this phase heading.

### Findings

#### Repository Matching Code Flow

The "Match repository from text" feature lives in `GeneratePlanUseCase.matchRepo()` (`GeneratePlanUseCase.swift:117-152`). It:

1. Takes a `voiceText` string and a `[RepositoryInfo]` array
2. Formats the repo list (id, description, recent focus) into a prompt
3. Sends the prompt to Claude CLI via `ClaudeCLIClient.runStructured()` with a JSON schema constraining output to `{ repoId, interpretedRequest }`
4. Returns the `RepoMatch` result

**Validation:** After matching, the caller validates the returned `repoId` UUID exists in the passed `repositories` array (lines 88-91). If not found, it throws `GenerateError.repoNotFound`.

#### Where Repositories Are Sourced

- **Mac App:** `GeneratePlanSheet` passes `model.repositories` → loaded by `WorkspaceModel.load()` → `LoadRepositoriesUseCase` → `RepositoryStore.loadAll()` → reads `{dataPath}/repositories.json`
- **CLI:** `PlanRunnerPlanCommand` → `ReposCommand.makeStore()` → `RepositoryStore.loadAll()` → same `repositories.json`
- **Default data path:** `~/Desktop/ai-dev-tools` (from `RepositoryStoreConfiguration`)

Both entry points source repos exclusively from the app's `repositories.json`. The `matchRepo()` prompt only includes repos from the passed array.

#### Uncommitted Working Tree Changes

The working tree contains changes that add a `selectedRepository` bypass to the matching flow:

- `GeneratePlanUseCase.Options` gains a `selectedRepository: RepositoryInfo?` field
- `GeneratePlanUseCase.run()` skips `matchRepo()` when `selectedRepository` is provided
- `GeneratePlanSheet` adds a "Match repository from text" toggle (default off) — when off, uses the currently selected repo directly; when on, triggers Claude-based matching
- `PlanRunnerModel.generate()` accepts the optional `selectedRepository` parameter

#### Root Cause Hypothesis

The `matchRepo()` function runs Claude CLI **without a working directory** (unlike `generatePlan()` which passes `repo.path.path()`). With `dangerouslySkipPermissions = true`, `printMode = true`, and `verbose = true`, Claude CLI has filesystem access in whatever directory the process runs from. Claude may be discovering or referencing repos outside the provided list in its reasoning, even though the JSON output is schema-constrained. The existing UUID validation guard would catch truly invalid matches, but the user may be seeing Claude's verbose output reference unexpected repos.

Additionally, the prompt doesn't explicitly instruct Claude to **only** choose from the listed repos — it says "Available repositories" but doesn't say "You must choose one of these."

## - [x] Phase 2: Gather Architectural Guidance

When executed, this phase will look at the repository's skills and architecture docs to identify which documentation and architectural guidelines are relevant to this request. It will read and summarize the key constraints. Document findings underneath this phase heading.

### Findings

#### Project Architecture (4-Layer Pattern)

The project follows a 4-layer architecture defined in `AIDevToolsKit/Package.swift`:

1. **Apps** — CLI and Mac app entry points (`AIDevToolsKitCLI`, `AIDevToolsKitMac`)
2. **Features** — Domain-specific use cases and workflows (`PlanRunnerFeature`, `EvalFeature`, etc.)
3. **Services** — Stateless business logic and persistence (`PlanRunnerService`, `EvalService`, etc.)
4. **SDKs** — Reusable, stateless utilities and external integrations (`RepositorySDK`, `ClaudeCLISDK`, `GitSDK`, etc.)

**Dependency rule:** No upward dependencies — SDKs cannot depend on Features/Services/Apps. The repo matching logic lives in the Features layer (`GeneratePlanUseCase` in `PlanRunnerFeature`), which correctly depends on `ClaudeCLISDK` and `RepositorySDK`.

#### Relevant Architecture Docs

| Document | Relevance |
|----------|-----------|
| `docs/completed/2026-03-21-a-unified-app-rearchitecture.md` | Establishes `RepositorySDK` as the single source of truth for repository information. `RepositoryStore` loads from `repositories.json`. |
| `docs/completed/2026-03-21-a-extract-claude-cli-sdk.md` | Defines `ClaudeCLIClient` patterns: stateless Sendable struct, `run()` and `runStructured()` both accept optional `workingDirectory` parameter. |

#### SDK Design Constraints

- **Stateless & Sendable:** All SDK types (`ClaudeCLIClient`, `RepositoryStore`, `RepositoryInfo`, `RepoMatch`) must remain `Sendable` and `Codable` where applicable.
- **ClaudeCLIClient interface:** `runStructured<T>(type:command:workingDirectory:environment:onFormattedOutput:)` — the `workingDirectory` parameter is optional and currently omitted in `matchRepo()` but used in `generatePlan()`.
- **Environment setup:** ClaudeCLIClient clears the `CLAUDECODE` env var, enriches PATH with `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, and has a 120-second inactivity watchdog.

#### Key Constraints for the Fix

1. **Single source of truth:** `RepositoryStore` → `repositories.json` is the canonical repo list. Both Mac app and CLI already source repos correctly before passing them to `matchRepo()`.
2. **Working directory gap:** `matchRepo()` does not pass `workingDirectory` to `claudeClient.runStructured()`, while `generatePlan()` does. Without a working directory constraint, Claude CLI may discover repos via filesystem access (especially with `dangerouslySkipPermissions = true`).
3. **Prompt clarity:** The current prompt says "Available repositories" but lacks an explicit constraint like "You must choose one of these and no others."
4. **Existing validation:** The UUID guard at lines 88-91 catches invalid repo IDs, but doesn't prevent Claude from being influenced by external repo discovery.
5. **selectedRepository bypass:** The working tree already has a `selectedRepository` parameter that skips `matchRepo()` entirely — this path must remain functional.
6. **Alphabetical ordering:** Per `CLAUDE.md`, any changes to Package.swift targets, enum cases, imports, or CLI command definitions must maintain alphabetical order.

#### Relevant Skills

- **`swift-architecture`** (referenced in `CLAUDE.md` for architecture/planning): Provides the 4-layer architecture patterns, layer placement guidance, and SDK design principles.
- **`ai-dev-tools-debug`** (referenced in `CLAUDE.md` for debugging): Provides CLI commands for manual validation — `swift run ai-dev-tools-kit repos list`, `swift run ai-dev-tools-kit plan-runner plan "..."`.

#### Files Most Relevant to the Fix

| File | Role |
|------|------|
| `AIDevToolsKit/Sources/Features/PlanRunnerFeature/usecases/GeneratePlanUseCase.swift` | Primary fix location — `matchRepo()` method and prompt |
| `AIDevToolsKit/Sources/SDKs/ClaudeCLISDK/ClaudeCLIClient.swift` | Client pattern reference for `runStructured()` signature |
| `AIDevToolsKit/Sources/SDKs/RepositorySDK/RepositoryStore.swift` | Single source of truth for repo loading |
| `AIDevToolsKit/Sources/SDKs/RepositorySDK/RepositoryInfo.swift` | Repository model definition |
| `AIDevToolsKit/Sources/Features/PlanRunnerFeature/services/ClaudeResponseModels.swift` | `RepoMatch` struct definition |
| `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/PlanRunnerModel.swift` | Mac app integration point |
| `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PlanRunnerPlanCommand.swift` | CLI integration point |

## - [ ] Phase 3: Plan the Implementation

When executed, this phase will use insights from Phases 1 and 2 to create concrete implementation steps. It will append new phases (Phase 4 through N) to this document, each with: what to implement, which files to modify, which architectural documents to reference, and acceptance criteria. It will also append a Testing/Verification phase and a Create Pull Request phase at the end. The Create Pull Request phase MUST always use `gh pr create --draft` (all PRs are drafts). This phase is responsible for generating the remaining phases dynamically.
