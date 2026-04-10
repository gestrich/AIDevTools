# Model-CLI Parity

## Background

The swift-architecture skill establishes a key principle: **any functionality exposed by a Mac app `@Observable` model should also be accessible via the CLI**. Both the Mac app and CLI are entry points into the same use cases and features. When a model exposes a capability that has no CLI equivalent, that capability becomes untestable from the terminal, harder to script, and invisible in CI — violating the "Zero Duplication" principle that all entry points should share the same underlying logic.

The goal of this project is to audit each `@Observable` model in `AIDevToolsKitMac/Models/` against its corresponding CLI commands and bring them into parity.

## What Counts as Parity

Parity is at the **API level** — the user-facing operations a model triggers. It is not about internal state management, loading spinners, enum-based view transitions, or other UI mechanics that have no meaning in a CLI context. For each model, ask:

> "What actions can a user perform via the Mac app that they cannot perform via the CLI?"

If an action is missing from the CLI, add the command. If a CLI command exists with no Mac app model equivalent, add it to the model. The fix may be adding a CLI command, adding a method to the model, or both.

## Instructions

For each task below:

1. Read the model file and enumerate all **API-level operations** it exposes (use case calls, repository reads/writes, service calls). Ignore UI-only state transitions.
2. Read the corresponding CLI command file(s) and enumerate the operations they expose.
3. Identify any gaps in either direction.
4. Make the necessary changes to bring the model and CLI into parity. This may mean adding new CLI commands, adding subcommands to existing commands, or adding missing operations to the model.

## Tasks

- [x] Check `AIDevToolsKitMac/Models/ArchitecturePlannerModel.swift` and corresponding `ArchPlanner*Command.swift` files for parity
  <!-- review: Added `runStep(_ step: ArchitecturePlannerStep)` to the model — the CLI's `update --step <name>` can run any specific step out of order, but the model only had `runNextStep()` and `runAllSteps()`; all other operations were already in parity. -->
- [x] Check `AIDevToolsKitMac/Models/ClaudeChainModel.swift` and corresponding `ClaudeChainCLI/` commands for parity
  <!-- review: CLI `setup` can create a new chain project (spec.md + supporting files) but the Mac app had a placeholder "not yet implemented" sheet. Added `CreateChainProjectUseCase` to `ClaudeChainFeature`, added `createProject(name:baseBranch:)` to `ClaudeChainModel`, and implemented `CreateChainSheet` with a form that calls it. All other operations (list chains, get detail, execute task) were already in parity. -->
- [x] Check `AIDevToolsKitMac/Models/ChatModel.swift` and corresponding `ChatCommand.swift` for parity
- [ ] Check `AIDevToolsKitMac/Models/CredentialModel.swift` and corresponding `CredentialsCommand.swift` for parity
- [ ] Check `AIDevToolsKitMac/Models/EvalRunnerModel.swift` and corresponding `RunEvalsCommand.swift` for parity
- [ ] Check `AIDevToolsKitMac/Models/MarkdownPlannerModel.swift` and corresponding `MarkdownPlanner*Command.swift` files for parity
- [ ] Check `AIDevToolsKitMac/Models/ProviderModel.swift` and corresponding CLI commands for parity
- [ ] Check `AIDevToolsKitMac/Models/SettingsModel.swift` and corresponding `ConfigCommand.swift` for parity
- [ ] Check `AIDevToolsKitMac/PRRadar/Models/AllPRsModel.swift` and `PRRadar*Command.swift` files for parity
- [ ] Check `AIDevToolsKitMac/PRRadar/Models/PRModel.swift` and `PRRadar*Command.swift` files for parity
- [ ] Check `AIDevToolsKitMac/Models/WorkspaceModel.swift` and corresponding `ReposCommand.swift` for parity
