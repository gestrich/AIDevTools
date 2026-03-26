## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `ai-dev-tools-debug` | File paths, CLI commands, and artifact structure for AIDevTools |

## Background

`AIRunSession` was introduced as a passive output-persistence wrapper — callers pass in a `work` closure that does the actual AI execution, and the session accumulates + persists the output. This means every caller still:

1. Depends directly on `ClaudeCLIClient` (or `CodexCLIClient`)
2. Builds CLI-specific command structs (`Claude(prompt:)`)
3. Manages its own output accumulation/streaming patterns
4. Manually wires the client call into the session's `work` closure

Three features currently interface with AI independently:

| Feature | Current pattern | Persistence |
|---------|----------------|-------------|
| **Evals** (`ClaudeAdapter`) | `claudeClient.run(command:onFormattedOutput:)` → manual `session.store.write()` | Via `OutputService` + `AIRunSession` (passive) |
| **Architecture Planner** (`ExecuteImplementationUseCase`) | `claudeClient.runStructured(command:onFormattedOutput:)` directly | None currently |
| **Plan Runner** (`ExecutePlanUseCase`) | `claudeClient.runStructured(command:onFormattedOutput:)` directly | Own `OutputAccumulator` + manual file write |

The goal is to evolve `AIRunSession` from a passive output wrapper into the **single interface to the AI** — owning prompt execution, streaming, and persistence. Callers should interact only with the session, not with `ClaudeCLIClient` directly.

### Target pattern

```swift
// Create a session with a client + storage key
let session = AIRunSession(key: "eval/claude/my-case", store: outputStore, client: claudeClient)

// Execute — session handles streaming, accumulation, and persistence
let result = try await session.run(
    prompt: "Evaluate this code...",
    options: AIClientOptions(model: "opus", workingDirectory: repoPath),
    onOutput: { chunk in liveUI.append(chunk) }
)

// Structured variant
let response: PhaseResponse = try await session.runStructured(
    PhaseResponse.self,
    prompt: "Evaluate implementation...",
    jsonSchema: schema,
    options: AIClientOptions(workingDirectory: repoPath)
)

// Later — load historical output
let previousOutput = session.loadOutput()
```

### Module dependency changes

`AIOutputSDK` (no deps) gains the `AIClient` protocol + supporting types.
`ClaudeCLISDK` gains a dependency on `AIOutputSDK` (leaf node, safe) and conforms `ClaudeCLIClient` to `AIClient`.
`CodexCLISDK` gains a dependency on `AIOutputSDK` and conforms `CodexCLIClient` to `AIClient`.
Feature targets replace direct `ClaudeCLISDK` imports with `AIOutputSDK` where possible.

## Phases

## - [x] Phase 1: Define `AIClient` protocol and types in `AIOutputSDK`

**Skills used**: `swift-architecture`
**Principles applied**: Protocol + value types placed in leaf SDK (AIOutputSDK) with no dependencies; all types marked Sendable

**Skills to read**: `swift-architecture`

Add a provider-agnostic protocol to `AIOutputSDK` that abstracts AI execution. This keeps the protocol dependency-free and available to all layers.

### Types to add

```swift
public struct AIClientOptions: Sendable {
    public var dangerouslySkipPermissions: Bool
    public var environment: [String: String]?
    public var model: String?
    public var workingDirectory: String?

    public init(
        dangerouslySkipPermissions: Bool = false,
        environment: [String: String]? = nil,
        model: String? = nil,
        workingDirectory: String? = nil
    )
}

public struct AIClientResult: Sendable {
    public let exitCode: Int32
    public let stderr: String
    public let stdout: String
}

public struct AIStructuredResult<T: Sendable>: Sendable {
    public let rawOutput: String
    public let stderr: String
    public let value: T
}

public protocol AIClient: Sendable {
    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T>
}
```

### Design notes

- `onOutput` receives **formatted** text (human-readable streaming chunks for live UI display)
- `AIClientResult.stdout` carries **raw** output (for parsing and persistence)
- `AIStructuredResult` carries both the decoded value and raw output (so the session can persist it)
- Options intentionally exclude CLI-specific flags like `outputFormat`, `verbose`, `printMode` — the client implementation sets those internally based on which method is called (`run` vs `runStructured`)

### Tasks

- Add `AIClient.swift` with the protocol and supporting types
- Unit tests: verify types are `Sendable`, compile-time protocol conformance check

## - [x] Phase 2: Conform CLI clients to `AIClient`

**Skills used**: `swift-architecture`
**Principles applied**: Extensions in separate files per SDK convention; ClaudeStructuredOutput updated to expose rawOutput/stderr for protocol conformance; CodexCLIClient structured output implemented via --output-schema + --json flags

**Skills to read**: `swift-architecture`

### `ClaudeCLIClient` conformance

Add `AIOutputSDK` as a dependency of `ClaudeCLISDK` in Package.swift. Add an extension on `ClaudeCLIClient` conforming to `AIClient`.

The conformance translates `AIClientOptions` into a `Claude` command struct:

```swift
extension ClaudeCLIClient: AIClient {
    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult {
        var command = Claude(prompt: prompt)
        command.model = options.model
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        let result = try await run(
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput
        )
        return AIClientResult(exitCode: result.exitCode, stderr: result.stderr, stdout: result.stdout)
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        var command = Claude(prompt: prompt)
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        command.jsonSchema = jsonSchema
        command.model = options.model
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.printMode = true
        command.verbose = true
        let output = try await runStructured(
            T.self,
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput
        )
        return AIStructuredResult(rawOutput: output.rawOutput, stderr: output.stderr, value: output.value)
    }
}
```

Note: `ClaudeStructuredOutput` currently does not expose `rawOutput` or `stderr`. Update it to carry these values so the conformance can forward them.

### `CodexCLIClient` conformance

Add `AIOutputSDK` as a dependency of `CodexCLISDK`. Add analogous conformance for `CodexCLIClient`.

### Tasks

- Update Package.swift: add `AIOutputSDK` dependency to `ClaudeCLISDK` and `CodexCLISDK`
- Add `ClaudeCLIClient+AIClient.swift` extension
- Update `ClaudeStructuredOutput` to expose raw stdout and stderr
- Add `CodexCLIClient+AIClient.swift` extension
- Verify existing tests still pass

## - [x] Phase 3: Evolve `AIRunSession` to own execution

**Skills used**: `swift-architecture`
**Principles applied**: Session owns execution + persistence; old closure API kept deprecated for one remaining caller until Phase 5 migration; read-only init preserved for historical-only sessions

**Skills to read**: `swift-architecture`

Transform `AIRunSession` from a passive output wrapper into an active AI execution interface.

### Updated API

```swift
public struct AIRunSession: Sendable {
    public let client: (any AIClient)?
    public let key: String
    public let store: AIOutputStore

    public init(key: String, store: AIOutputStore, client: any AIClient)

    /// Execute a prompt, stream formatted output, persist raw stdout, return result.
    public func run(
        prompt: String,
        options: AIClientOptions = AIClientOptions(),
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> AIClientResult

    /// Execute a prompt expecting structured output, persist raw stdout, return decoded value.
    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions = AIClientOptions(),
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> T

    /// Load previously stored output.
    public func loadOutput() -> String?

    /// Delete stored output.
    public func deleteOutput() throws
}
```

### Behavior

- `run()` calls `client.run()`, persists `result.stdout` via `store.write()`, returns result
- `runStructured()` calls `client.runStructured()`, persists `structuredResult.rawOutput` via `store.write()`, returns decoded value
- On failure (client throws), persist any accumulated output if available. Use a combined approach: accumulate via `onOutput` callback as fallback, but prefer raw output from result when available.
- `loadOutput()` and `deleteOutput()` unchanged

### Backward compatibility

Keep a read-only initializer without client for historical-only sessions:

```swift
public init(key: String, store: AIOutputStore)  // client = nil, for loading only
```

Remove the old `run(onOutput:work:)` closure-based method. All callers were migrated in the previous spec (2026-03-25-b) and will be migrated again here to the new API.

### Tasks

- Update `AIRunSession` with `client` property and new `run`/`runStructured` methods
- Remove old `run(onOutput:work:)` method
- Remove private `Accumulator` class (no longer needed — raw output comes from client result)
- Unit tests:
  - `run()` calls client and persists raw stdout
  - `run()` forwards formatted output to `onOutput` callback
  - `runStructured()` calls client, persists raw output, returns decoded value
  - `loadOutput()` returns persisted output after execution
  - Session without client can still `loadOutput()` / `deleteOutput()`

## - [x] Phase 4: Migrate eval `ClaudeAdapter` to use session execution

**Skills used**: `swift-architecture`, `ai-dev-tools-debug`
**Principles applied**: Added `jsonSchema` to `AIClientOptions` so `run()` supports structured output mode while returning raw stdout for custom parsing; separated default init into extension file to decouple `ClaudeAdapter` from concrete `ClaudeCLIClient`

**Skills to read**: `swift-architecture`, `ai-dev-tools-debug`

Replace the manual `claudeClient.run()` + persistence in `ClaudeAdapter` with `session.run()`.

### Current flow
```
claudeClient.run(command:onFormattedOutput:) → ExecutionResult
session.store.write(executionResult.stdout)   // manual persistence
parser.buildResult(from: executionResult.stdout)
outputService.writeArtifacts(...)
```

### New flow
```
session.run(prompt:options:onOutput:) → AIClientResult  // auto-persists
parser.buildResult(from: result.stdout)
outputService.writeArtifacts(...)
```

### Tasks

- Remove `ClaudeCLIClient` import from `ClaudeAdapter` — use `AIClient` via session instead
- Update `ClaudeAdapter` to accept an `AIClient` instead of `CLIClient` in its initializer
- Replace manual command building with `AIClientOptions`
- Remove manual `session.store.write()` call — session handles it
- Keep `ClaudeOutputParser` usage — it parses from `result.stdout`
- Keep `OutputService.writeArtifacts()` for structured JSON + stderr
- Pass `result.stderr` to `writeArtifacts()` from `AIClientResult`
- Run eval CLI commands to verify artifacts written correctly

## - [x] Phase 5: Migrate Architecture Planner and Plan Runner

**Skills used**: `swift-architecture`
**Principles applied**: Replaced concrete ClaudeCLIClient with AIClient protocol in all three use cases; isolated default ClaudeCLIClient creation into +Default.swift extension files per Phase 4 pattern; kept OutputAccumulator in ExecutePlanUseCase for error-resilient log writing since AIRunSession doesn't yet persist on failure

**Skills to read**: `swift-architecture`

### Architecture Planner (`ExecuteImplementationUseCase`)

Currently calls `claudeClient.runStructured()` directly with manually constructed `Claude` commands.

- Accept an `AIClient` (or `AIRunSession`) instead of `ClaudeCLIClient` in the initializer
- Replace `claudeClient.runStructured(PhaseResponse.self, command:...)` with `session.runStructured(PhaseResponse.self, prompt:jsonSchema:options:onOutput:)`
- This gives the planner auto-persistence of AI output per phase (keyed by `"<jobId>/<phaseIndex>"`)
- Remove direct `ClaudeCLISDK` dependency from `ArchitecturePlannerFeature` if no other usage remains

### Plan Runner (`ExecutePlanUseCase`)

Currently calls `claudeClient.runStructured()` directly and manages its own `OutputAccumulator` + phase log writing.

- Accept an `AIClient` instead of `ClaudeCLIClient`
- Replace `claudeClient.runStructured()` calls in `getPhaseStatus()` and `executePhase()` with `AIRunSession.runStructured()`
- Session auto-persists output per phase (keyed by `"<planName>/phase-<N>"`)
- Remove the private `OutputAccumulator` class — session handles accumulation
- Keep `writePhaseLog()` as an additional log mechanism if needed, or replace with session `loadOutput()` for log retrieval

### Plan Generator (`GeneratePlanUseCase`)

- Accept an `AIClient` instead of `ClaudeCLIClient`
- Replace `claudeClient.runStructured()` calls with direct `client.runStructured()` (no session needed — plan generation doesn't need output persistence)

### Tasks

- Update `ExecuteImplementationUseCase` initializer and execution
- Update `ExecutePlanUseCase` initializer and execution
- Update `GeneratePlanUseCase` initializer
- Remove duplicate `OutputAccumulator` from `ExecutePlanUseCase`
- Update Package.swift dependencies: replace `ClaudeCLISDK` with `AIOutputSDK` in feature targets where possible
- Verify architecture planner streams live output and loads historical output
- Verify plan runner executes phases and writes logs correctly

## - [x] Phase 6: Clean up and validation

**Skills used**: `swift-testing`, `ai-dev-tools-debug`
**Principles applied**: Updated OutputService.makeSession() factory to accept optional AIClient; ClaudeAdapter now uses factory instead of manual session creation; added jsonSchema test coverage. Deprecated `run(onOutput:work:)` and its Accumulator retained — still called by ArchitecturePlannerModel (Apps layer). OutputAccumulator in ExecutePlanUseCase retained for error-resilient log writing. StdoutAccumulator in ClaudeCLIClient retained for timeout retry logic.

**Skills to read**: `swift-testing`, `ai-dev-tools-debug`

### Clean up

- Remove any remaining duplicate `OutputAccumulator`/`StdoutAccumulator` classes that are no longer used
- Remove the old `run(onOutput:work:)` method from `AIRunSession` if not done in Phase 3
- Update `OutputService.makeSession()` factory to accept an `AIClient` parameter
- Audit imports: features should depend on `AIOutputSDK` for the protocol, not on `ClaudeCLISDK` directly (except where CLI-specific types like `Claude` are still needed)

### Automated tests

- `AIClient` protocol conformance tests for `ClaudeCLIClient` and `CodexCLIClient`
- `AIRunSession` unit tests (Phase 3)
- Existing `OutputService` tests still pass
- Existing `AIOutputStore` tests still pass
- Existing eval and planner tests still pass

### Manual verification

- Run an eval via CLI — confirm artifacts written correctly, raw stdout at expected path
- Open Mac app → run eval → verify live streaming → close and reopen → verify historical output loads
- Run plan runner via CLI — confirm phase execution and log output
- Build both Mac app and CLI with no compile errors
