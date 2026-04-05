# Apps Layer Review Reference

The Apps layer contains platform-specific entry points: macOS apps (SwiftUI views + `@Observable` models), CLI tools (ArgumentParser commands), and server handlers. This is the **only layer** where `@Observable` and UI code belong.

## Core Rules

1. **`@Observable` lives here and nowhere else** — models are `@MainActor @Observable class`
2. **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
3. **Enum-based state** — model state is a single enum, not multiple independent properties
4. **Depth over width** — one user action = one use case call
5. **Error catching at this layer** — catch errors from use cases and set error state for UI display

## Ideal Patterns

### Model consumes a use case stream (depth)

```swift
@MainActor @Observable
class ImportModel {
    var state: ModelState = .loading(prior: nil)
    private let useCase: ImportUseCase

    func startImport(config: ImportConfig) {
        let prior = state.snapshot
        Task {
            do {
                for try await useCaseState in useCase.stream(options: .init(config: config)) {
                    state = ModelState(from: useCaseState, prior: prior)
                }
            } catch {
                state = .error(error, prior: prior)
            }
        }
    }

    enum ModelState {
        case loading(prior: ImportSnapshot?)
        case ready(ImportSnapshot)
        case operating(ImportState, prior: ImportSnapshot?)
        case error(Error, prior: ImportSnapshot?)

        var snapshot: ImportSnapshot? {
            switch self {
            case .ready(let s): return s
            case .operating(_, let prior): return prior
            case .loading(let prior): return prior
            case .error(_, let prior): return prior
            }
        }
    }
}
```

### CLI command consumes a use case directly

```swift
struct ImportCommand: AsyncParsableCommand {
    func run() async throws {
        let useCase = ImportUseCase()
        for try await state in useCase.stream(options: .init(config: config)) {
            switch state {
            case .validating: print("Validating...")
            case .completed(let snapshot): print("Done — \(snapshot.itemCount) items")
            // ...
            }
        }
    }
}
```

## Anti-Patterns and How to Fix Them

### Anti-Pattern: Model orchestrates multiple SDK/service calls (width)

```swift
// BAD — model is doing the feature layer's job
@MainActor @Observable
class ImportModel {
    func startImport() {
        Task {
            let data = try await apiClient.fetchData(source: source)
            let validated = try await validator.validate(data)
            for try await progress in apiClient.submitImport(payload: validated) {
                self.progress = progress
            }
            let status = try await apiClient.fetchStatus(id: "latest")
            self.result = status
        }
    }
}
```

**Severity: 8/10** — This is orchestration logic that belongs in a Feature (use case).

**Incremental fix:** Extract the multi-step logic into a `StreamingUseCase` in the Features layer. The model calls `useCase.stream()` and maps yielded state. You don't have to move everything at once — start by wrapping the existing logic in a use case struct and having the model call it.

### Anti-Pattern: Multiple independent state properties instead of enum

```swift
// BAD — scattered state, easy to have inconsistent combinations
@MainActor @Observable
class ImportModel {
    var isLoading = false
    var error: Error?
    var result: ImportResult?
    var progress: Double = 0
}
```

**Severity: 6/10** — Leads to impossible state combinations and scattered UI logic.

**Incremental fix:** Introduce a `ModelState` enum and migrate one property at a time. Start by combining `isLoading` and `result` into `.loading` / `.ready(result)`, then fold in `error`.

### Anti-Pattern: Swallowing errors silently

```swift
// BAD — error is caught and discarded
func save() {
    Task {
        do {
            try await useCase.run(options: opts)
        } catch {
            print("save failed: \(error)")
        }
    }
}
```

**Severity: 5/10** — Users never see failures. The UI shows stale data.

**Incremental fix:** Set an error state case instead of printing:
```swift
} catch {
    state = .error(error, prior: state.snapshot)
}
```

### Anti-Pattern: Business logic in a view

```swift
// BAD — view is computing derived business data
struct ImportView: View {
    var body: some View {
        let filteredItems = items.filter { $0.isValid && $0.date > cutoffDate }
        let total = filteredItems.reduce(0) { $0 + $1.amount }
        Text("Total: \(total)")
    }
}
```

**Severity: 7/10** — Business logic is untestable and duplicated if another view needs the same computation.

**Incremental fix:** Move the computation into the model as a computed property or into a use case if it involves multiple steps.

### Anti-Pattern: Feature-layer code inside an app-layer file

```swift
// BAD — use case defined in the app layer
// File: apps/MyMacApp/Models/ImportModel.swift
struct ImportUseCase: StreamingUseCase { ... }

@MainActor @Observable
class ImportModel { ... }
```

**Severity: 9/10** — The use case can't be shared with the CLI or other entry points.

**Incremental fix:** Move the `UseCase` struct to `features/ImportFeature/usecases/`. The model file should only contain the model.

## Cross-Cutting Check: CLI Parity

When a review suggests extracting logic into a use case, check whether an associated CLI command exists for the same workflow. CLI commands live alongside models as entry points in the Apps layer and should consume the same use cases.

**What to check:**
1. Search for a CLI command that corresponds to the model's functionality (e.g., `ImportModel` → `ImportCommand`)
2. If a CLI command exists, verify it calls the same use case as the model
3. If a CLI command does not exist, note this as an opportunity — the extracted use case enables adding one

**Why this matters:** The whole point of extracting orchestration into a use case is reuse across entry points. If the model calls a use case but the CLI command duplicates the logic inline (or doesn't exist), the architectural benefit is unrealized.

When recommending a use case extraction, include a note about the CLI command:
- If one exists: verify it shares the use case and flag if it doesn't
- If one doesn't exist: mention that the new use case enables adding a CLI command
