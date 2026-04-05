# SDKs Layer Review Reference

The SDKs layer contains low-level, reusable building blocks. Each SDK is a stateless `Sendable` struct where every method wraps a single operation (one CLI command, one API call). SDKs have no app-specific logic — they could be extracted to a standalone package and used in a completely different project.

## Core Rules

1. **Stateless `Sendable` structs** — no mutable internal state, no actors, no classes
2. **Single-operation methods** — each method wraps one CLI command or one API call
3. **No business concepts** — no app-specific types, no domain logic
4. **Generic and reusable** — could be used by any project as-is
5. **Dependencies: only other SDKs or external packages** — never depend on Services, Features, or Apps

## Ideal Patterns

### Stateless API client

```swift
public struct APIClient: Sendable {
    public init() {}

    public func fetchData(source: String) async throws -> Data {
        // Single API call
    }

    public func submitImport(payload: Data) -> AsyncThrowingStream<ImportProgress, Error> {
        // Single streaming API call
    }

    public func fetchStatus(id: String) async throws -> StatusResponse {
        // Single API call
    }
}
```

### CLI wrapper

```swift
public struct GitClient: Sendable {
    public init() {}

    public func checkout(branch: String) throws { }
    public func commit(message: String) throws { }
    public func push(branch: String, remote: String) throws { }
}
```

### Quick tests for SDK correctness

- Could another project use this SDK as-is? → **Yes** = correct
- Does the SDK reference app-specific types? → **Yes** = violation
- Does the SDK hold mutable state? → **Yes** = violation
- Does a method coordinate multiple operations? → **Yes** = violation (belongs in Features)

## Anti-Patterns and How to Fix Them

### Anti-Pattern: SDK knows about business concepts

```swift
// BAD — SDK shouldn't know about app-specific types
public struct GitClient: Sendable {
    public func createWorktreeForTask(task: TaskConfig) throws {
        // TaskConfig is an app-specific business type
    }
}
```

**Severity: 8/10** — Ties the SDK to one app's domain. Can't be reused.

**Incremental fix:** Accept generic parameters instead:
```swift
public func createWorktree(path: String, branch: String) throws { }
```
The Feature layer maps business types to generic SDK parameters.

### Anti-Pattern: SDK holds mutable state

```swift
// BAD — SDK should be stateless
public struct APIClient: Sendable {
    private var cache: [String: Data] = [:]  // ❌ mutable state
    private var requestCount: Int = 0         // ❌ mutable state

    public mutating func fetch(url: String) async throws -> Data {
        requestCount += 1
        if let cached = cache[url] { return cached }
        // ...
    }
}
```

**Severity: 7/10** — Breaks the stateless contract. Complicates concurrency and testing.

**Incremental fix:** Remove the cache from the SDK. If caching is needed, create a Service that wraps the SDK and manages the cache. The SDK stays a pure pass-through.

### Anti-Pattern: SDK method orchestrates multiple operations

```swift
// BAD — multi-step orchestration belongs in a Feature
public struct GitClient: Sendable {
    public func prepareBranch(name: String) throws {
        try checkout(branch: "main")
        try pull(remote: "origin")
        try checkout(branch: name)
    }
}
```

**Severity: 7/10** — This is a use case in disguise. SDKs wrap single operations; orchestration belongs in Features.

**Incremental fix:** Keep only the single-operation methods (`checkout`, `pull`). Move `prepareBranch` to a use case in the Features layer.

### Anti-Pattern: SDK is a class or actor

```swift
// BAD — SDKs should be structs
public class APIClient {
    private let session: URLSession

    public func fetch(url: String) async throws -> Data { ... }
}
```

**Severity: 5/10** — Classes allow reference semantics and mutable state, which undermines the stateless guarantee.

**Incremental fix:** Convert to a struct. If the class held configuration (like a base URL), pass it through `init` as a stored property on the struct. If it held mutable state, that state likely belongs in a Service.

### Anti-Pattern: SDK depends on a Service or Feature

```swift
// BAD — upward dependency
import CoreService

public struct APIClient: Sendable {
    public func fetch(config: AppConfiguration) async throws -> Data {
        // AppConfiguration is a service-layer type
    }
}
```

**Severity: 10/10** — Violates the fundamental dependency rule. SDKs sit at the bottom of the stack.

**Incremental fix:** Accept primitive or SDK-defined parameters instead:
```swift
public func fetch(baseURL: URL, token: String) async throws -> Data { }
```
The Feature or App layer resolves `AppConfiguration` into the primitives the SDK needs.

### Anti-Pattern: SDK has `import SwiftUI` or `import Combine`

```swift
// BAD — platform frameworks don't belong in SDKs
import SwiftUI

public struct ThemeSDK: Sendable {
    public func primaryColor() -> Color { ... }
}
```

**Severity: 8/10** — Ties the SDK to a specific platform, making it unusable in CLI or server contexts.

**Incremental fix:** Define platform-agnostic types (e.g., a `ColorValue` struct with RGB components). If the SDK genuinely only wraps a platform-specific API, consider whether it belongs in Services instead.

### Anti-Pattern: SDK with default/fallback values masking errors

```swift
// BAD — silently returns a default when something went wrong
public struct ConfigClient: Sendable {
    public func readTimeout() -> Int {
        guard let value = try? readFromDisk("timeout") else {
            return 30  // silent fallback
        }
        return value
    }
}
```

**Severity: 4/10** — Hides configuration errors. Debugging becomes difficult when the app uses unexpected defaults.

**Incremental fix:** Make the method `throws`:
```swift
public func readTimeout() throws -> Int {
    try readFromDisk("timeout")
}
```
