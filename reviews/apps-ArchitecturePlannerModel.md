# Architecture Review: ArchitecturePlannerModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ArchitecturePlannerModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 7/10] Model orchestrates multi-step workflow dispatch instead of delegating to a single use case

**Location:** Lines 124-188

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
>
> **Depth over width** — one user action = one use case call
>
> **Rule:** If code coordinates multiple SDK/service calls, it belongs in a use case, not in an app-layer model or service.

### Interpretation

`runNextStep()` contains a large switch statement that selects among seven different use cases based on `ArchitecturePlannerStep`. The model is acting as a step dispatcher — it knows which use case maps to which step, how to construct the options for each, and how to wire up output handling. This is orchestration logic that belongs in the Features layer. If a CLI command needed to run a planning step, it would have to duplicate this entire switch. `runAllSteps()` compounds the issue by looping over steps sequentially, adding more orchestration on top. Severity 7/10 because the model is doing the Features layer's job, though each individual branch does delegate to a use case (so the violation is dispatch, not business logic).

### Resolution

Create a `RunPlanningStepUseCase` (or extend an existing use case) in `ArchitecturePlannerFeature` that accepts a job, step index, store, and repo path, and internally dispatches to the correct sub-use-case. The model becomes:

```swift
func runNextStep() async {
    guard let job = selectedJob, let store, let repoPath = currentRepoPath else { return }
    guard let stepDef = ArchitecturePlannerStep(rawValue: job.currentStepIndex) else { return }

    state = .running(stepName: stepDef.name)
    currentOutput = ""
    let session = makeSession(jobId: job.jobId, stepIndex: job.currentStepIndex)

    do {
        try await runStepUseCase.run(
            .init(job: job, repoPath: repoPath, step: stepDef),
            store: store,
            session: session,
            onOutput: { [weak self] text in
                Task { @MainActor in self?.currentOutput += text }
            }
        )
        reloadSelectedJob()
        state = .idle
    } catch {
        state = .error(error)
    }
}
```

---

## Finding 2 — [Severity: 5/10] `currentOutput` is an independent stored property outside the state enum

**Location:** Lines 19

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties
>
> Enum-based `ModelState` with `prior` for retaining last-known data. View switches on model state — no separate loading/error properties.

### Interpretation

The model has an enum-based `State` but `currentOutput` lives outside it as an independent `String` property. It's only meaningful during `.running` and gets manually cleared at the start of `runNextStep()`. This creates a mismatch — the enum says the model is `.idle` but `currentOutput` may still hold stale text from the last run. Severity 5/10 because the `State` enum itself is well-structured and this is one spillover property, not a pervasive pattern.

### Resolution

Move `currentOutput` into the `.running` case:

```swift
enum State {
    case idle
    case loading
    case running(stepName: String, output: String)
    case error(Error)
}
```

Update output appending to mutate the associated value. If the view needs the output to persist after the step completes, add a `prior` pattern or a separate `.completed(output:)` case.

---

## Finding 3 — [Severity: 5/10] Model directly constructs data paths and stores instead of receiving them

**Location:** Lines 88-101

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
>
> **`@Observable` lives here and nowhere else** — models are `@MainActor @Observable class`

### Interpretation

`loadJobs()` calls `dataPathsService.path(for:subdirectory:)`, then constructs an `AIOutputStore` and an `ArchitecturePlannerStore` inline. This mixes infrastructure setup (where to store data) with the model's job of translating use case results into state. If the storage strategy changes (e.g., database-backed stores), this model must change too. Severity 5/10 because it's mild setup logic rather than multi-step business orchestration, but it still couples the model to storage construction details.

### Resolution

Move store construction into the use case or a factory. The model could receive the stores from an initializer or from a use case that returns them:

```swift
func loadJobs(repoName: String, repoPath: String) {
    currentRepoName = repoName
    currentRepoPath = repoPath
    do {
        let workspace = try setupWorkspaceUseCase.run(repoName: repoName)
        self.outputStore = workspace.outputStore
        self.store = workspace.plannerStore
        self.jobs = workspace.jobs
    } catch {
        state = .error(error)
    }
}
```

---

## Finding 4 — [Severity: 4/10] Eight use case instances rebuilt on provider change via mutable vars

**Location:** Lines 46-54, 78-86

### Guidance

> **`@Observable` lives here and nowhere else** — models are `@MainActor @Observable class`
>
> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows

### Interpretation

Six use cases are stored as `var` and rebuilt in `rebuildUseCases()` when the provider changes. This means the model knows the internal dependency of each use case on `AIClient` and must keep the reconstruction list in sync with the initializer. If a new use case is added, both `init` and `rebuildUseCases()` must be updated — a maintenance risk. Severity 4/10 because it works correctly and the duplication is bounded, but it's fragile bookkeeping that shouldn't live in the model.

### Resolution

Introduce a `UseCaseFactory` or a struct that groups the use cases and can be rebuilt atomically:

```swift
private struct UseCases {
    let compileArchInfo: CompileArchitectureInfoUseCase
    let compileFollowups: CompileFollowupsUseCase
    let execute: ExecuteImplementationUseCase
    let formRequirements: FormRequirementsUseCase
    let planAcrossLayers: PlanAcrossLayersUseCase
    let scoreConformance: ScoreConformanceUseCase

    init(client: any AIClient) {
        self.compileArchInfo = CompileArchitectureInfoUseCase(client: client)
        self.compileFollowups = CompileFollowupsUseCase(client: client)
        self.execute = ExecuteImplementationUseCase(client: client)
        self.formRequirements = FormRequirementsUseCase(client: client)
        self.planAcrossLayers = PlanAcrossLayersUseCase(client: client)
        self.scoreConformance = ScoreConformanceUseCase(client: client)
    }
}
```

This way `rebuildUseCases()` becomes a single assignment and is impossible to have out of sync with `init`.

---

## Finding 5 — [Severity: 3/10] No CLI parity — architecture planner workflow is Mac-only

**Location:** N/A (cross-cutting)

### Guidance

> **Cross-Cutting Check: CLI Parity**
>
> When a review suggests extracting logic into a use case, check whether an associated CLI command exists for the same workflow. CLI commands live alongside models as entry points in the Apps layer and should consume the same use cases.
>
> If a CLI command does not exist, note this as an opportunity — the extracted use case enables adding one.

### Interpretation

There is no CLI command for architecture planning (create job, run steps, generate report). All use cases are consumed exclusively through `ArchitecturePlannerModel`. Severity 3/10 because this is an opportunity note, not a code defect — but it means the feature is locked to the Mac GUI.

### Resolution

After extracting the step-dispatch logic into a use case (Finding 1), adding CLI commands like `architecture-planner run <job-id>` becomes straightforward. No action needed now, but note the opportunity.

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 5 |
| **Highest severity** | 7/10 |
| **Overall health** | Well-structured model with proper enum state and error handling. Main issue is step-dispatch orchestration that belongs in the Features layer. |
| **Top priority** | Extract the step-dispatch switch in `runNextStep()` into a feature-layer use case to enable CLI reuse and simplify the model. |
