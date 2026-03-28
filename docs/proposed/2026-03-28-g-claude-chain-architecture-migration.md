## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) with placement guidance |

## Background

The ClaudeChain source was copied from `claude-chain/ClaudeChainKit` into this project as flat targets (`ClaudeChainDomain`, `ClaudeChainInfrastructure`, `ClaudeChainServices`, `ClaudeChainCLI`, `ClaudeChainMain`). These need to be reorganized into our 4-layer architecture: Apps, Features, Services, SDKs.

**Current targets and their architectural mapping:**

| Current Target | Contains | Correct Layer | New Target Name |
|---------------|----------|---------------|-----------------|
| `ClaudeChainDomain` | Shared models, formatters, error types, config types | Services | `ClaudeChainService` |
| `ClaudeChainInfrastructure` | Git/GitHub CLI wrappers, file I/O, script runner | SDKs | `ClaudeChainSDK` |
| `ClaudeChainServices` | Multi-step orchestration (PR, task, auto-start, workflow) | Features | `ClaudeChainFeature` |
| `ClaudeChainCLI` | ArgumentParser commands | Apps | `ClaudeChainCLI` (no rename) |
| `ClaudeChainMain` | Executable entry point | Apps | `ClaudeChainMain` (no rename) |

**Rationale:**

- **ClaudeChainDomain → ClaudeChainService (Services)**: Contains shared models (Project, SpecContent, GitHubModels, CostBreakdown, etc.) and formatters used across features. These are app-specific types — not generic enough for SDKs, not orchestration so not Features. Services layer is the correct home for shared models and types.
- **ClaudeChainInfrastructure → ClaudeChainSDK (SDKs)**: Wraps external tools (git, gh CLI, GitHub Actions env, file system). These are single-operation wrappers — stateless or near-stateless. SDK layer is correct.
- **ClaudeChainServices → ClaudeChainFeature (Features)**: AutoStartService, TaskService, PRService, StatisticsService, etc. all orchestrate multi-step workflows across infrastructure and domain. This is Features layer behavior.
- **ClaudeChainCLI → Apps**: CLI commands are entry points. Already correctly named for the Apps layer.
- **ClaudeChainMain → Apps**: Executable entry point. Apps layer.

**Dependency flow after migration:**
```
ClaudeChainMain → ClaudeChainCLI → ClaudeChainFeature → ClaudeChainService → (no internal deps)
                                                       → ClaudeChainSDK    → ClaudeChainService
```

**Test targets follow the same rename pattern:**

| Current Test Target | New Test Target |
|--------------------|-----------------|
| `ClaudeChainDomainTests` | `ClaudeChainServiceTests` |
| `ClaudeChainInfrastructureTests` | `ClaudeChainSDKTests` |
| `ClaudeChainServicesTests` | `ClaudeChainFeatureTests` |
| `ClaudeChainCLITests` | `ClaudeChainCLITests` (no rename) |

## Phases

## - [x] Phase 1: Move ClaudeChainDomain → ClaudeChainService (Services layer)

**Skills used**: `swift-architecture`
**Principles applied**: Placed shared models/types in Services layer per 4-layer architecture. Updated all fully-qualified module references (not just imports).

**Skills to read**: `swift-architecture`

1. Rename the source folder: `Sources/ClaudeChainDomain/` → `Sources/Services/ClaudeChainService/`
2. Rename the test folder: `Tests/ClaudeChainDomainTests/` → `Tests/Services/ClaudeChainServiceTests/`
3. Update `Package.swift`:
   - Rename target `ClaudeChainDomain` → `ClaudeChainService` with path `Sources/Services/ClaudeChainService`
   - Rename test target `ClaudeChainDomainTests` → `ClaudeChainServiceTests` with path `Tests/Services/ClaudeChainServiceTests`
   - Update the product name from `ClaudeChainDomain` → `ClaudeChainService`
4. Update all `import ClaudeChainDomain` → `import ClaudeChainService` across all ClaudeChain source and test files
5. Update all dependency references in `Package.swift` from `"ClaudeChainDomain"` → `"ClaudeChainService"`
6. Build to verify: `swift build --target ClaudeChainService`

## - [x] Phase 2: Move ClaudeChainInfrastructure → ClaudeChainSDK (SDKs layer)

**Skills used**: `swift-architecture`
**Principles applied**: Placed stateless CLI/git/GitHub wrappers in SDKs layer per 4-layer architecture. Updated all imports and Package.swift references.

**Skills to read**: `swift-architecture`

1. Rename the source folder: `Sources/ClaudeChainInfrastructure/` → `Sources/SDKs/ClaudeChainSDK/`
2. Rename the test folder: `Tests/ClaudeChainInfrastructureTests/` → `Tests/SDKs/ClaudeChainSDKTests/`
3. Update `Package.swift`:
   - Rename target `ClaudeChainInfrastructure` → `ClaudeChainSDK` with path `Sources/SDKs/ClaudeChainSDK`
   - Rename test target `ClaudeChainInfrastructureTests` → `ClaudeChainSDKTests` with path `Tests/SDKs/ClaudeChainSDKTests`
   - Update the product name
4. Update all `import ClaudeChainInfrastructure` → `import ClaudeChainSDK` across all ClaudeChain source and test files
5. Update all dependency references in `Package.swift` from `"ClaudeChainInfrastructure"` → `"ClaudeChainSDK"`
6. Build to verify: `swift build --target ClaudeChainSDK`

## - [x] Phase 3: Move ClaudeChainServices → ClaudeChainFeature (Features layer)

**Skills used**: `swift-architecture`
**Principles applied**: Placed multi-step orchestration services in Features layer per 4-layer architecture. Updated all imports and Package.swift references. Added ClaudeChainFeature dependency to ClaudeChainServiceTests since SlackBlockLimitTests imports it.

**Skills to read**: `swift-architecture`

1. Rename the source folder: `Sources/ClaudeChainServices/` → `Sources/Features/ClaudeChainFeature/`
2. Rename the test folder: `Tests/ClaudeChainServicesTests/` → `Tests/Features/ClaudeChainFeatureTests/`
3. Update `Package.swift`:
   - Rename target `ClaudeChainServices` → `ClaudeChainFeature` with path `Sources/Features/ClaudeChainFeature`
   - Rename test target `ClaudeChainServicesTests` → `ClaudeChainFeatureTests` with path `Tests/Features/ClaudeChainFeatureTests`
   - Update the product name
4. Update all `import ClaudeChainServices` → `import ClaudeChainFeature` across all ClaudeChain source and test files
5. Update all dependency references in `Package.swift` from `"ClaudeChainServices"` → `"ClaudeChainFeature"`
6. Build to verify: `swift build --target ClaudeChainFeature`

## - [x] Phase 4: Move ClaudeChainCLI and ClaudeChainMain to Apps layer

**Skills used**: `swift-architecture`
**Principles applied**: Moved CLI commands and executable entry point to Apps layer per 4-layer architecture. No import renames needed since target names are unchanged.

**Skills to read**: `swift-architecture`

1. Move the source folder: `Sources/ClaudeChainCLI/` → `Sources/Apps/ClaudeChainCLI/`
2. Move the source folder: `Sources/ClaudeChainMain/` → `Sources/Apps/ClaudeChainMain/`
3. Move the test folder: `Tests/ClaudeChainCLITests/` → `Tests/Apps/ClaudeChainCLITests/`
4. Update `Package.swift` paths:
   - `ClaudeChainCLI` path → `Sources/Apps/ClaudeChainCLI`
   - `ClaudeChainMain` path → `Sources/Apps/ClaudeChainMain`
   - `ClaudeChainCLITests` path → `Tests/Apps/ClaudeChainCLITests`
5. No import renames needed — target names stay the same
6. Build to verify: `swift build --target ClaudeChainMain`

## - [x] Phase 5: Clean up old directories and verify products

**Skills used**: none
**Principles applied**: Verified no empty leftover directories exist (previous phases already cleaned up). Products array already reflects renamed targets from phases 1-4. ClaudeChainKit umbrella product was never carried over from the original package — N/A. Directory structure confirmed correct across all 4 layers.

1. Remove any empty leftover directories from the old flat structure
2. Update the `products` array in `Package.swift` to reflect renamed targets:
   - `ClaudeChainDomain` → `ClaudeChainService`
   - `ClaudeChainInfrastructure` → `ClaudeChainSDK`
   - `ClaudeChainServices` → `ClaudeChainFeature`
3. Keep the `ClaudeChainKit` library product but update its target list to the new names
4. Verify final directory structure matches:
   ```
   Sources/
   ├── Apps/
   │   ├── ClaudeChainCLI/
   │   ├── ClaudeChainMain/
   │   ├── AIDevToolsKitCLI/
   │   └── AIDevToolsKitMac/
   ├── Features/
   │   ├── ClaudeChainFeature/
   │   └── ...existing features...
   ├── Services/
   │   ├── ClaudeChainService/
   │   └── ...existing services...
   └── SDKs/
       ├── ClaudeChainSDK/
       └── ...existing SDKs...
   ```

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: Validated all ClaudeChain targets build and tests pass. Confirmed no stale imports remain. 3 pre-existing test failures in TestRealWorkflowData are due to hardcoded fixture paths from the original claude-chain repo, not the migration.

**Skills to read**: `swift-testing`

1. Build all ClaudeChain targets: `swift build --target ClaudeChainMain`
2. Run all ClaudeChain test targets:
   - `swift test --filter ClaudeChainServiceTests`
   - `swift test --filter ClaudeChainSDKTests`
   - `swift test --filter ClaudeChainFeatureTests`
   - `swift test --filter ClaudeChainCLITests`
3. Build the full project to ensure no regressions: `swift build`
4. Verify no stale `import ClaudeChainDomain`, `import ClaudeChainInfrastructure`, or `import ClaudeChainServices` remain in any source files
