> **2026-03-29 Obsolescence Evaluation:** Plan reviewed, still relevant. Apps and Services layers have been reviewed (16 review files in reviews/), but Features layer files have not been reviewed. The plan provides detailed file-by-file approach for 45 Swift files across 4 feature directories using the ai-dev-tools-review skill.

# Review and Fix All Features Layer Files

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-review` | The review skill that analyzes Swift files against the 4-layer architecture and produces findings with severity scores |
| `swift-architecture` | Provides the 4-layer architecture reference (Apps, Features, Services, SDKs) needed for understanding violations |

## Background

The `ai-dev-tools-review` skill reviews Swift files for conformance to the 4-layer architecture (Apps, Features, Services, SDKs). Reviews have already been completed for the Apps and Services layers (16 review files exist in `reviews/`). The Features layer has not yet been reviewed.

This plan covers all 45 Swift files under `AIDevToolsKit/Sources/Features/`. For each file, the executor will:
1. Run the `ai-dev-tools-review` skill to produce a review file in `reviews/`
2. Read the review output and identify all findings that are violations (severity ≥ 5)
3. Immediately implement the resolution for each violation

Review files follow the existing naming convention: `features-<FileName>.md` stored in `reviews/`.

Each phase covers one feature directory. Within each phase, every file is a discrete task: review → store → fix violations.

---

## - [ ] Phase 1: Review and fix ArchitecturePlannerFeature (13 files)

**Skills to read**: `ai-dev-tools-review`, `swift-architecture`

For each of the 13 files below, invoke the `ai-dev-tools-review` skill, save the review to `reviews/features-<FileName>.md`, then immediately implement all resolutions for findings with severity ≥ 5.

Files (process in this order):

1. **ArchitecturePlannerWorkspace.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/ArchitecturePlannerWorkspace.swift` → `reviews/features-ArchitecturePlannerWorkspace.md`
2. **ChecklistValidationUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/ChecklistValidationUseCase.swift` → `reviews/features-ChecklistValidationUseCase.md`
3. **CompileArchitectureInfoUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/CompileArchitectureInfoUseCase.swift` → `reviews/features-CompileArchitectureInfoUseCase.md`
4. **CompileFollowupsUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/CompileFollowupsUseCase.swift` → `reviews/features-CompileFollowupsUseCase.md`
5. **CreatePlanningJobUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/CreatePlanningJobUseCase.swift` → `reviews/features-CreatePlanningJobUseCase.md`
6. **ExecuteImplementationUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/ExecuteImplementationUseCase.swift` → `reviews/features-ExecuteImplementationUseCase.md`
7. **FormRequirementsUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/FormRequirementsUseCase.swift` → `reviews/features-FormRequirementsUseCase.md`
8. **GenerateReportUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/GenerateReportUseCase.swift` → `reviews/features-GenerateReportUseCase.md`
9. **ManageGuidelinesUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/ManageGuidelinesUseCase.swift` → `reviews/features-ManageGuidelinesUseCase.md`
10. **PlanAcrossLayersUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/PlanAcrossLayersUseCase.swift` → `reviews/features-PlanAcrossLayersUseCase.md`
11. **RunPlanningStepUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/RunPlanningStepUseCase.swift` → `reviews/features-RunPlanningStepUseCase.md`
12. **ScoreConformanceUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/ScoreConformanceUseCase.swift` → `reviews/features-ScoreConformanceUseCase.md`
13. **SeedGuidelinesUseCase.swift** — `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/SeedGuidelinesUseCase.swift` → `reviews/features-SeedGuidelinesUseCase.md`

**Per-file workflow:**
- Read the file
- Read `references/features-layer.md` from the skill
- Identify the layer and evaluate against the reference
- Write the review to `reviews/features-<FileName>.md` using the skill's output format
- For every finding with severity ≥ 5, implement the resolution described in that finding
- If a fix changes the file's public API, check callers and update them

---

## - [ ] Phase 2: Review and fix ChatFeature (7 files)

**Skills to read**: `ai-dev-tools-review`, `swift-architecture`

For each of the 7 files below, invoke the `ai-dev-tools-review` skill, save the review to `reviews/features-<FileName>.md`, then immediately implement all resolutions for findings with severity ≥ 5.

Files (process in this order):

1. **ChatMessage.swift** — `AIDevToolsKit/Sources/Features/ChatFeature/ChatMessage.swift` → `reviews/features-ChatMessage.md`
2. **ChatSettings.swift** — `AIDevToolsKit/Sources/Features/ChatFeature/ChatSettings.swift` → `reviews/features-ChatSettings.md`
3. **GetSessionDetailsUseCase.swift** — `AIDevToolsKit/Sources/Features/ChatFeature/GetSessionDetailsUseCase.swift` → `reviews/features-GetSessionDetailsUseCase.md`
4. **ListSessionsUseCase.swift** — `AIDevToolsKit/Sources/Features/ChatFeature/ListSessionsUseCase.swift` → `reviews/features-ListSessionsUseCase.md`
5. **LoadSessionMessagesUseCase.swift** — `AIDevToolsKit/Sources/Features/ChatFeature/LoadSessionMessagesUseCase.swift` → `reviews/features-LoadSessionMessagesUseCase.md`
6. **ScanSkillsUseCase.swift** — `AIDevToolsKit/Sources/Features/ChatFeature/ScanSkillsUseCase.swift` → `reviews/features-ScanSkillsUseCase.md`
7. **SendChatMessageUseCase.swift** — `AIDevToolsKit/Sources/Features/ChatFeature/SendChatMessageUseCase.swift` → `reviews/features-SendChatMessageUseCase.md`

**Per-file workflow:** Same as Phase 1 — review, store in `reviews/`, fix all violations ≥ 5.

---

## - [ ] Phase 3: Review and fix EvalFeature (7 files)

**Skills to read**: `ai-dev-tools-review`, `swift-architecture`

For each of the 7 files below, invoke the `ai-dev-tools-review` skill, save the review to `reviews/features-<FileName>.md`, then immediately implement all resolutions for findings with severity ≥ 5.

Files (process in this order):

1. **ClearArtifactsUseCase.swift** — `AIDevToolsKit/Sources/Features/EvalFeature/ClearArtifactsUseCase.swift` → `reviews/features-ClearArtifactsUseCase.md`
2. **ListEvalCasesUseCase.swift** — `AIDevToolsKit/Sources/Features/EvalFeature/ListEvalCasesUseCase.swift` → `reviews/features-ListEvalCasesUseCase.md`
3. **ListEvalSuitesUseCase.swift** — `AIDevToolsKit/Sources/Features/EvalFeature/ListEvalSuitesUseCase.swift` → `reviews/features-ListEvalSuitesUseCase.md`
4. **LoadLastResultsUseCase.swift** — `AIDevToolsKit/Sources/Features/EvalFeature/LoadLastResultsUseCase.swift` → `reviews/features-LoadLastResultsUseCase.md`
5. **ReadCaseOutputUseCase.swift** — `AIDevToolsKit/Sources/Features/EvalFeature/ReadCaseOutputUseCase.swift` → `reviews/features-ReadCaseOutputUseCase.md`
6. **RunCaseUseCase.swift** — `AIDevToolsKit/Sources/Features/EvalFeature/RunCaseUseCase.swift` → `reviews/features-RunCaseUseCase.md`
7. **RunEvalsUseCase.swift** — `AIDevToolsKit/Sources/Features/EvalFeature/RunEvalsUseCase.swift` → `reviews/features-RunEvalsUseCase.md`

**Per-file workflow:** Same as Phase 1 — review, store in `reviews/`, fix all violations ≥ 5.

---

## - [ ] Phase 4: Review and fix MarkdownPlannerFeature (11 files)

**Skills to read**: `ai-dev-tools-review`, `swift-architecture`

For each of the 11 files below, invoke the `ai-dev-tools-review` skill, save the review to `reviews/features-<FileName>.md`, then immediately implement all resolutions for findings with severity ≥ 5.

Files (process in this order):

1. **ClaudeResponseModels.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/services/ClaudeResponseModels.swift` → `reviews/features-ClaudeResponseModels.md`
2. **PhaseStatus.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/services/PhaseStatus.swift` → `reviews/features-PhaseStatus.md`
3. **PlanPhase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/services/PlanPhase.swift` → `reviews/features-PlanPhase.md`
4. **CompletePlanUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/CompletePlanUseCase.swift` → `reviews/features-CompletePlanUseCase.md`
5. **DeletePlanUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/DeletePlanUseCase.swift` → `reviews/features-DeletePlanUseCase.md`
6. **ExecutePlanUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift` → `reviews/features-ExecutePlanUseCase.md`
7. **GeneratePlanUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/GeneratePlanUseCase.swift` → `reviews/features-GeneratePlanUseCase.md`
8. **IntegrateTaskIntoPlanUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/IntegrateTaskIntoPlanUseCase.swift` → `reviews/features-IntegrateTaskIntoPlanUseCase.md`
9. **LoadPlansUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/LoadPlansUseCase.swift` → `reviews/features-LoadPlansUseCase.md`
10. **TogglePhaseUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/TogglePhaseUseCase.swift` → `reviews/features-TogglePhaseUseCase.md`
11. **WatchPlanUseCase.swift** — `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/WatchPlanUseCase.swift` → `reviews/features-WatchPlanUseCase.md`

**Per-file workflow:** Same as Phase 1 — review, store in `reviews/`, fix all violations ≥ 5.

**Note:** The 3 files in `services/` subdirectory (ClaudeResponseModels, PhaseStatus, PlanPhase) may be flagged as belonging in the Services layer rather than Features. If the review identifies a layer-placement violation, evaluate whether moving the file is warranted or if the `services/` subdirectory is an intentional organizational choice within the feature.

---

## - [ ] Phase 5: Review and fix SkillBrowserFeature (7 files)

**Skills to read**: `ai-dev-tools-review`, `swift-architecture`

For each of the 7 files below, invoke the `ai-dev-tools-review` skill, save the review to `reviews/features-<FileName>.md`, then immediately implement all resolutions for findings with severity ≥ 5.

Files (process in this order):

1. **AddRepositoryUseCase.swift** — `AIDevToolsKit/Sources/Features/SkillBrowserFeature/AddRepositoryUseCase.swift` → `reviews/features-AddRepositoryUseCase.md`
2. **ConfigureNewRepositoryUseCase.swift** — `AIDevToolsKit/Sources/Features/SkillBrowserFeature/ConfigureNewRepositoryUseCase.swift` → `reviews/features-ConfigureNewRepositoryUseCase.md`
3. **LoadRepositoriesUseCase.swift** — `AIDevToolsKit/Sources/Features/SkillBrowserFeature/LoadRepositoriesUseCase.swift` → `reviews/features-LoadRepositoriesUseCase.md`
4. **LoadSkillsUseCase.swift** — `AIDevToolsKit/Sources/Features/SkillBrowserFeature/LoadSkillsUseCase.swift` → `reviews/features-LoadSkillsUseCase.md`
5. **RemoveRepositoryUseCase.swift** — `AIDevToolsKit/Sources/Features/SkillBrowserFeature/RemoveRepositoryUseCase.swift` → `reviews/features-RemoveRepositoryUseCase.md`
6. **RemoveRepositoryWithSettingsUseCase.swift** — `AIDevToolsKit/Sources/Features/SkillBrowserFeature/RemoveRepositoryWithSettingsUseCase.swift` → `reviews/features-RemoveRepositoryWithSettingsUseCase.md`
7. **UpdateRepositoryUseCase.swift** — `AIDevToolsKit/Sources/Features/SkillBrowserFeature/UpdateRepositoryUseCase.swift` → `reviews/features-UpdateRepositoryUseCase.md`

**Per-file workflow:** Same as Phase 1 — review, store in `reviews/`, fix all violations ≥ 5.

---

## - [ ] Phase 6: Validation

Build the project and run the test suite to confirm all fixes compile and pass.

```bash
cd /Users/bill/Developer/personal/AIDevTools && swift build 2>&1 | tail -20
```

```bash
cd /Users/bill/Developer/personal/AIDevTools && swift test 2>&1 | tail -40
```

**Verification checklist:**
- All 45 review files exist in `reviews/` with `features-` prefix
- `swift build` succeeds with no new errors
- `swift test` passes with no new failures
- Each review file follows the skill's output format (Guidance / Interpretation / Resolution sections)
- All findings with severity ≥ 5 have corresponding code fixes applied

If build or tests fail, trace the failure back to the specific fix that caused it and adjust the resolution while keeping it architecturally sound.
