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

## - [ ] Phase 3: Review and fix ChatModel.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ChatModel.swift`
- Save the review output to `reviews/apps-ChatModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 4: Review and fix EvalRunnerModel.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/EvalRunnerModel.swift`
- Save the review output to `reviews/apps-EvalRunnerModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 5: Review and fix MarkdownPlannerModel.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/MarkdownPlannerModel.swift`
- Save the review output to `reviews/apps-MarkdownPlannerModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 6: Review and fix ProviderModel.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ProviderModel.swift`
- Save the review output to `reviews/apps-ProviderModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 7: Review and fix RepositoryEvalConfig.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/RepositoryEvalConfig.swift`
- Save the review output to `reviews/apps-RepositoryEvalConfig.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 8: Review and fix SettingsModel.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/SettingsModel.swift`
- Save the review output to `reviews/apps-SettingsModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 9: Review and fix SkillContent.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/SkillContent.swift`
- Save the review output to `reviews/apps-SkillContent.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 10: Review and fix WorkspaceModel.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift`
- Save the review output to `reviews/apps-WorkspaceModel.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 11: Review and fix CaseResult.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/CaseResult.swift`
- Save the review output to `reviews/services-CaseResult.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 12: Review and fix EvalCase.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/EvalCase.swift`
- Save the review output to `reviews/services-EvalCase.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 13: Review and fix EvalSuite.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/EvalSuite.swift`
- Save the review output to `reviews/services-EvalSuite.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 14: Review and fix GradingModels.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/GradingModels.swift`
- Save the review output to `reviews/services-GradingModels.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 15: Review and fix ProviderTypes.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/EvalService/Models/ProviderTypes.swift`
- Save the review output to `reviews/services-ProviderTypes.md`
- Implement all review findings, including low severity
- Verify the build passes

## - [ ] Phase 16: Review and fix Skill.swift

**Skills to read**: `ai-dev-tools-review`

- Run the `ai-dev-tools-review` skill on `AIDevToolsKit/Sources/Services/SkillService/Models/Skill.swift`
- Save the review output to `reviews/services-Skill.md`
- Implement all review findings, including low severity
- Verify the build passes
