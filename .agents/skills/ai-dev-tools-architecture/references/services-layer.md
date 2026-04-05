# Services Layer Review Reference

The Services layer holds shared models, configuration, and stateful utilities used across features. Services do **not** orchestrate multi-step workflows — that's the Features layer's job.

## Core Rules

1. **Shared models and types** — data structures used by multiple features
2. **Configuration persistence** — auth tokens, user settings, file paths
3. **No orchestration** — services don't coordinate multi-step operations across SDKs
4. **No `@Observable`** — that belongs exclusively in the Apps layer
5. **Dependencies flow downward** — services depend on other services and SDKs, never on Features or Apps
6. **Stateful utilities that don't orchestrate** — caches, stores, registries

## Ideal Patterns

### Shared model in CoreService

```swift
public struct ImportConfig: Sendable {
    public let source: DataSource
    public let validateFirst: Bool
    public let batchSize: Int

    public init(source: DataSource, validateFirst: Bool, batchSize: Int) {
        self.source = source
        self.validateFirst = validateFirst
        self.batchSize = batchSize
    }
}

public enum DataSource: Sendable {
    case local(path: String)
    case remote(url: URL)
}
```

### Configuration service

```swift
public struct ConfigurationService {
    public func get<T: Decodable>(_ type: T.Type, from file: String) throws -> T {
        // Loads typed configuration from JSON
    }
}
```

### Stateful utility (no orchestration)

```swift
public struct GitConfig {
    public let defaultRemote: String
    public let mainBranch: String
}
```

## Anti-Patterns and How to Fix Them

### Anti-Pattern: Service orchestrates multi-step workflows

```swift
// BAD — multi-step orchestration belongs in a Feature (use case)
public struct GitService {
    func prepareBranchAndPush(name: String) async throws {
        try gitClient.checkout(branch: "main")
        try gitClient.pull()
        try gitClient.checkout(branch: "feature/\(name)")
        try gitClient.push(branch: "feature/\(name)")
    }
}
```

**Severity: 8/10** — This is a use case hiding in the Services layer. It can't be consumed via `UseCase`/`StreamingUseCase` protocol, and it couples orchestration logic to a layer meant for shared utilities.

**Incremental fix:** Move the method into a `StreamingUseCase` struct in the Features layer. The service can still hold `GitConfig`, but the multi-step workflow becomes a use case.

### Anti-Pattern: Service holds `@Observable` state

```swift
// BAD — @Observable belongs in the Apps layer
@Observable
class UserService {
    var currentUser: User?
    var isAuthenticated: Bool = false
}
```

**Severity: 8/10** — Services shouldn't drive UI reactivity. This creates a dependency from the Service toward UI concerns.

**Incremental fix:** Make the service a plain struct or class without `@Observable`. The App-layer model wraps the service and exposes observable state.

### Anti-Pattern: Service depends on a Feature

```swift
// BAD — upward dependency from Service to Feature
import ImportFeature

public struct CoreService {
    func prepareForImport() -> ImportUseCase.Options {
        // ...
    }
}
```

**Severity: 10/10** — Violates the fundamental dependency flow rule. Creates circular dependency risk.

**Incremental fix:** Define the shared types (like the options struct) in the Service layer itself, and have both the Feature and Service depend on those types.

### Anti-Pattern: "God service" that does everything

```swift
// BAD — too many unrelated responsibilities
public struct AppService {
    func authenticate() async throws { ... }
    func fetchBuilds() async throws -> [Build] { ... }
    func saveUserPreferences(_ prefs: Preferences) throws { ... }
    func clearCache() { ... }
    func formatReport(_ data: ReportData) -> String { ... }
}
```

**Severity: 6/10** — Becomes a dumping ground. Changes to one concern risk breaking others.

**Incremental fix:** Split into focused services: `AuthService`, `BuildService`, `PreferencesService`, etc. Start with the most independent chunk — often auth or config.

### Anti-Pattern: Service contains app-specific types that only one feature uses

```swift
// BAD — types used by only one feature should live in that feature's services/ directory
// File: services/CoreService/Models/ImportStageTracker.swift
public struct ImportStageTracker {
    // Only used by ImportFeature
}
```

**Severity: 4/10** — Clutters the shared service with feature-specific concerns.

**Incremental fix:** Move to `features/ImportFeature/services/`. Only promote to CoreService when a second feature needs it.

### Anti-Pattern: Error swallowing in a service

```swift
// BAD — silently swallows the error
public func loadConfig() -> AppConfig? {
    do {
        return try configService.get(AppConfig.self, from: "app")
    } catch {
        print("Config load failed")
        return nil
    }
}
```

**Severity: 5/10** — Callers can't distinguish between "no config" and "config failed to load."

**Incremental fix:** Make the method `throws` and let callers handle the error:
```swift
public func loadConfig() throws -> AppConfig {
    try configService.get(AppConfig.self, from: "app")
}
```
