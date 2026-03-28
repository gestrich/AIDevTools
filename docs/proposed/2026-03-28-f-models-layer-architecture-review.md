## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-review` | Reviews a Swift file for conformance to the 4-layer app architecture and reports violations ranked by severity |

## Background

We want to systematically review every file in the Models directories across the project for architecture compliance. Each file will be reviewed using the `ai-dev-tools-review` skill, and the resulting review will be saved to a `reviews/` directory for future reference.

There are 16 files across three Models directories:
- **Apps layer** (`Sources/Apps/AIDevToolsKitMac/Models/`) — 10 files
- **Services layer** (`Sources/Services/EvalService/Models/`) — 5 files
- **Services layer** (`Sources/Services/SkillService/Models/`) — 1 file

Each phase reviews one file and then implements all findings. The review output (markdown) should be saved to `reviews/<layer>-<filename>.md` (e.g., `reviews/apps-ActivePlanModel.md`).

## Phases

## - [x] Phase 1: Review ActivePlanModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Extracted orchestration into WatchPlanUseCase, added enum-based ModelState, moved PlanPhase and parsePhases to MarkdownPlannerFeature

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ActivePlanModel.swift`
- Save the review output to `reviews/apps-ActivePlanModel.md`

## - [x] Phase 2: Review ArchitecturePlannerModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Extracted step dispatch into RunPlanningStepUseCase, moved currentOutput into State enum, extracted store construction into ArchitecturePlannerWorkspace, consolidated 6 client-dependent use cases into single RunPlanningStepUseCase

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ArchitecturePlannerModel.swift`
- Save the review output to `reviews/apps-ArchitecturePlannerModel.md`

## - [x] Phase 3: Review and fix ChatModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Replaced direct AIClient calls with GetSessionDetailsUseCase, ListSessionsUseCase, and LoadSessionMessagesUseCase; introduced ModelState enum replacing scattered isProcessing/isLoadingHistory booleans; extracted StreamAccumulator actor to file-level; deduplicated session resume logic into resumeLatestSession helper

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ChatModel.swift`
- Save the review output to `reviews/apps-ChatModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 4: Review and fix EvalRunnerModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Extracted LoadLastResultsUseCase for filesystem I/O; folded lastResults into State enum with prior pattern; removed debug logging infrastructure; injected all dependencies (GitClient, ClearArtifactsUseCase, ReadCaseOutputUseCase) via init; fixed force-unwraps on registry.defaultEntry; surfaced suite-loading errors to state

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/EvalRunnerModel.swift`
- Save the review output to `reviews/apps-EvalRunnerModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 5: Review and fix MarkdownPlannerModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Replaced force-unwrap on `providerRegistry.defaultClient` with guard/preconditionFailure; folded `lastExecutionPhases` into State enum `.completed` case with computed accessor; tightened access control on `isLoadingPlans`, `executionCompleteCount`, `phaseCompleteCount` to `private(set)`; documented `executionProgressObserver` bridging purpose; removed redundant Logger import/property/usage in `generate()`; nested `QueuedTask` inside model

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/MarkdownPlannerModel.swift`
- Save the review output to `reviews/apps-MarkdownPlannerModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 6: Review and fix ProviderModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Injected API key source via closure to decouple from UserDefaults singleton; parameterized `buildRegistry()` to accept API key, improving testability and reducing implicit coupling to hardcoded key string; noted CLI factory duplication as future consolidation opportunity

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ProviderModel.swift`
- Save the review output to `reviews/apps-ProviderModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 7: Review and fix RepositoryEvalConfig.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Added `Sendable` conformance for consistency with project value-type conventions; removed redundant explicit memberwise init that duplicated Swift's synthesized initializer

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/RepositoryEvalConfig.swift`
- Save the review output to `reviews/apps-RepositoryEvalConfig.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 8: Review and fix SettingsModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Injected ResolveDataPathUseCase via init for testability; removed hidden didSet side-effect and moved save into explicit updateDataPath method; tightened dataPath to private(set)

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/SettingsModel.swift`
- Save the review output to `reviews/apps-SettingsModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 9: Review and fix SkillContent.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Moved SkillContent from Apps/Models to SkillService/Models since it's a pure parsing/data struct with no app-layer concerns; added public access control and Sendable conformance

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/SkillContent.swift`
- Save the review output to `reviews/apps-SkillContent.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 10: Review and fix WorkspaceModel.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Extracted multi-step add/remove orchestration into ConfigureNewRepositoryUseCase and RemoveRepositoryWithSettingsUseCase (shared by model and CLI, eliminating duplication); tightened access control on repositories, selectedRepository, skills, isLoadingSkills to private(set)

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift`
- Save the review output to `reviews/apps-WorkspaceModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 11: Review and fix CaseResult.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Changed nine never-mutated properties from `var` to `let` to communicate immutability intent; extracted `EvalSummary` to its own file for discoverability since it's a standalone public type used broadly across Features and Apps

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/CaseResult.swift`
- Save the review output to `reviews/services-CaseResult.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 12: Review and fix EvalCase.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Changed `suite` from `var` to `let` and added `withSuite(_:)` copy method to eliminate post-decode mutation; updated CaseLoader to use the copy method instead of direct property mutation

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/EvalCase.swift`
- Save the review output to `reviews/services-EvalCase.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 13: Review and fix EvalSuite.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: No violations found — file is a clean Services-layer value type with immutable properties, Sendable conformance, and correct layer placement

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/EvalSuite.swift`
- Save the review output to `reviews/services-EvalSuite.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 14: Review and fix GradingModels.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: No violations found — file is a clean Services-layer value type with immutable properties, Sendable/Codable conformance, and correct layer placement

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/GradingModels.swift`
- Save the review output to `reviews/services-GradingModels.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 15: Review and fix ProviderTypes.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Renamed file from ProviderTypes.swift to SkillCheckResult.swift to match its sole type after provider-related types were moved out in prior refactors; no other violations found — file is a clean Services-layer value type with Sendable/Codable conformance

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/ProviderTypes.swift`
- Save the review output to `reviews/services-ProviderTypes.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [x] Phase 16: Review and fix Skill.swift

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Eliminated redundant `Skill` and `ReferenceFile` types that duplicated `SkillInfo` and `SkillReferenceFile` from SkillScannerSDK; added `Identifiable` and `Hashable` to `SkillReferenceFile`; simplified `LoadSkillsUseCase` to return SDK types directly; removed unnecessary `SkillService` dependency from `SkillBrowserFeature`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/SkillService/Models/Skill.swift`
- Save the review output to `reviews/services-Skill.md`
- Implement all review findings, including low severity
- Verify the build passes
