# Features Layer Review Reference

The Features layer contains use cases — structs conforming to `UseCase` or `StreamingUseCase` that orchestrate multi-step operations across SDKs and Services. Features are the primary unit of business logic.

## Core Rules

1. **Use cases are structs** — not classes, not actors
2. **Conform to `UseCase` or `StreamingUseCase`** — from the Uniflow SDK
3. **Orchestrate multiple steps** — coordinate SDK and Service calls into workflows
4. **No `@Observable`** — that belongs exclusively in the Apps layer
5. **No UI or CLI code** — features don't import SwiftUI or ArgumentParser
6. **No feature-to-feature dependencies** — shared logic goes in Services or SDKs; compose at the App layer
7. **Dependencies via init** — accept SDK clients and services through the initializer

## Ideal Patterns

### StreamingUseCase with progress reporting

```swift
public struct ImportUseCase: StreamingUseCase {
    public typealias State = ImportState
    public typealias Result = State

    public struct Options: Sendable {
        public let config: ImportConfig
    }

    private let apiClient: APIClient

    public init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.validating)
                    let data = try await apiClient.fetchData(source: options.config.source.identifier)

                    continuation.yield(.importing(.starting))
                    for try await progress in apiClient.submitImport(payload: data) {
                        continuation.yield(.importing(.progress(progress)))
                    }

                    continuation.yield(.completed(ImportSnapshot(itemCount: data.count)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

### Simple UseCase (single result, no progress)

```swift
public struct ValidateUseCase: UseCase {
    public typealias Options = ValidateOptions
    public typealias Result = ValidationResult

    public func run(options: ValidateOptions) async throws -> ValidationResult {
        // Single-step validation
    }
}
```

### Feature directory structure

```
features/ImportFeature/
├── usecases/
│   ├── ImportUseCase.swift
│   └── ValidateUseCase.swift
└── services/
    ├── ImportMapper.swift        # Feature-specific helpers
    └── ImportTypes.swift         # Feature-specific models
```

## Anti-Patterns and How to Fix Them

### Anti-Pattern: Use case holds `@Observable` state

```swift
// BAD — @Observable belongs in the Apps layer
@Observable
class ImportUseCase {
    var progress: Double = 0
    var result: ImportResult?

    func run() async throws {
        progress = 0.5
        result = try await apiClient.fetch()
        progress = 1.0
    }
}
```

**Severity: 8/10** — Mixes UI concerns with business logic. Can't be consumed by CLI.

**Incremental fix:** Convert to a struct conforming to `StreamingUseCase`. Yield progress via `AsyncThrowingStream` instead of setting observable properties. The App-layer model handles observation.

### Anti-Pattern: Feature depends on another feature

```swift
// BAD — features must not depend on other features
import ExportFeature

public struct ImportUseCase: StreamingUseCase {
    private let exportUseCase: ExportUseCase
    // ...
}
```

**Severity: 9/10** — Creates circular risk and tight coupling between features.

**Incremental fix:** Extract the shared logic into a Service or SDK. If `ImportUseCase` needs to trigger an export, compose them at the App layer (model calls import, then export sequentially).

### Anti-Pattern: Use case is a class or actor instead of a struct

```swift
// BAD — use cases should be lightweight value types
class ImportUseCase: StreamingUseCase {
    private var cache: [String: Data] = [:]
    // ...
}
```

**Severity: 5/10** — Classes allow mutable shared state that complicates concurrency.

**Incremental fix:** Convert to a struct. If caching is needed, move the cache to a Service that the use case depends on.

### Anti-Pattern: Use case swallows errors internally

```swift
// BAD — errors should propagate to the caller
public func stream(options: Options) -> AsyncThrowingStream<State, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                // multi-step work
            } catch {
                print("Import failed: \(error)")
                continuation.yield(.failed)
                continuation.finish()  // silently finishes
            }
        }
    }
}
```

**Severity: 6/10** — The caller has no way to distinguish between success and failure if the stream finishes normally in both cases.

**Incremental fix:** Use `continuation.finish(throwing: error)` to propagate the error. The App layer catches it and sets error state.

### Anti-Pattern: Orchestration logic that should be a use case lives in a "Manager" or "Controller"

```swift
// BAD — this is a use case in disguise
public class ImportManager {
    func performImport(config: ImportConfig) async throws {
        let data = try await apiClient.fetchData(...)
        let validated = try validate(data)
        try await apiClient.submitImport(payload: validated)
    }
}
```

**Severity: 7/10** — Same orchestration logic, but doesn't conform to the use case protocol. Can't be consumed uniformly by CLI and Mac app.

**Incremental fix:** Rename to a struct, conform to `UseCase` or `StreamingUseCase`, and add proper `Options`/`Result` types. The method body often stays the same.

### Anti-Pattern: Feature imports SwiftUI or platform-specific frameworks

```swift
// BAD — SwiftUI belongs in the Apps layer only
import SwiftUI

public struct ImportUseCase: StreamingUseCase {
    // ...
}
```

**Severity: 9/10** — Features must be platform-agnostic to be shared across entry points.

**Incremental fix:** Remove the SwiftUI import. If the use case needs something that lives in SwiftUI (like `Color`), define a platform-agnostic equivalent in Services or accept it as a parameter from the App layer.

## Cross-Cutting Check: Entry Point Parity

Every use case should be consumed by **both** the Mac app (via an `@Observable` model) and the CLI (via an `AsyncParsableCommand`). When reviewing a use case, check that both entry points exist and call the same use case.

**What to check:**
1. Search for a Mac app model that consumes this use case (e.g., `ImportUseCase` → `ImportModel`)
2. Search for a CLI command that consumes this use case (e.g., `ImportUseCase` → `ImportCommand`)
3. If either is missing, flag it — the use case exists to enable reuse across entry points, so a missing consumer means the benefit is unrealized
4. If both exist, verify they call the same use case rather than duplicating orchestration logic inline

**Why this matters:** The architectural reason for extracting logic into a use case is shared reuse between the Mac app and CLI. If only one entry point consumes the use case while the other duplicates the logic or lacks the capability entirely, the architecture isn't delivering its intended value.
