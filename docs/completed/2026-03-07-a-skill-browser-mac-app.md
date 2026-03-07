## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) with dependency flow, layer placement, and configuration patterns |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns with enum-based state, @Observable models, and dependency injection |
| `swift-testing` | Test style guide and conventions |

## Background

Bill has added a Mac app (`AIDevTools`) that depends on the `AIDevToolsKit` Swift package. The app currently has a bare-bones `ContentView` with placeholder content. The goal is to build a skill browser that:

1. Lets users configure repository paths (a `RepositoryConfiguration` type with a path to a repo)
2. Scans each repo's `.claude/skills/` directory to discover available skills
3. Displays a list of repositories in a sidebar, and selecting one shows its skills
4. Stores repository configurations on disk at a configurable data path (defaulting to `~/Desktop`)
5. Provides a Settings UI to change the data path

The existing project uses **targets in a single package** (`AIDevToolsKit/Package.swift`) with the 4-layer architecture already established (Apps: `AIDevToolsKitApp`, Features: `EvalFeature`, Services: `EvalService`, SDKs: `EvalSDK`). The Mac app is a separate Xcode project (`AIDevTools.xcodeproj`) that depends on `AIDevToolsKit`.

## Phases

## - [x] Phase 1: Add Service-layer models and persistence

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Services layer with no dependencies; all types are `Sendable` and `Codable`; struct-based store following stateless conventions

**Skills to read**: `swift-app-architecture:swift-architecture` (configuration.md, layers.md)

Create a new `SkillService` target in the Services layer of `AIDevToolsKit/Package.swift`. This module provides:

- **`RepositoryConfiguration`** — A `Codable` struct with:
  - `id: UUID`
  - `path: URL` (path to the repository root)
  - `name: String` (display name, derived from the path's last component or user-provided)

- **`Skill`** — A `Codable` struct representing a discovered skill:
  - `name: String` (filename without extension)
  - `path: URL` (full path to the skill file)

- **`SkillServiceConfiguration`** — A struct holding:
  - `dataPath: URL` (directory where repo configurations are stored as JSON, defaults to `~/Desktop/AIDevTools`)

- **`RepositoryConfigurationStore`** — A struct that reads/writes `[RepositoryConfiguration]` to a JSON file at `dataPath/repositories.json`. Methods:
  - `func loadAll() throws -> [RepositoryConfiguration]`
  - `func save(_ configurations: [RepositoryConfiguration]) throws`
  - `func add(_ configuration: RepositoryConfiguration) throws`
  - `func remove(id: UUID) throws`

Files to create:
- `AIDevToolsKit/Sources/SkillService/Models/RepositoryConfiguration.swift`
- `AIDevToolsKit/Sources/SkillService/Models/Skill.swift`
- `AIDevToolsKit/Sources/SkillService/SkillServiceConfiguration.swift`
- `AIDevToolsKit/Sources/SkillService/RepositoryConfigurationStore.swift`

Update `AIDevToolsKit/Package.swift` to add the `SkillService` target (Services layer, no dependencies on other targets).

## - [x] Phase 2: Add SDK-layer skill scanner

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Stateless `Sendable` struct per SDK conventions; no app-specific knowledge — takes a URL, returns file info; no dependencies on other targets

**Skills to read**: `swift-app-architecture:swift-architecture` (layers.md — SDK characteristics)

Create a new `SkillScannerSDK` target in the SDKs layer. This is a stateless, `Sendable` struct that performs a single operation: scanning a directory for skill files.

- **`SkillScanner`** — A `Sendable` struct with:
  - `func scanSkills(at repositoryPath: URL) throws -> [SkillInfo]` — Reads `.claude/skills/` directory, returns info for each `.md` file found
  - `SkillInfo` — A simple struct with `name: String` and `path: URL`

The SDK knows nothing about `RepositoryConfiguration` — it just takes a URL and returns file info. The mapping from `SkillInfo` to the service-layer `Skill` type happens in the feature.

Files to create:
- `AIDevToolsKit/Sources/SkillScannerSDK/SkillScanner.swift`
- `AIDevToolsKit/Sources/SkillScannerSDK/SkillInfo.swift`

Update `AIDevToolsKit/Package.swift` to add the `SkillScannerSDK` target (no dependencies).

## - [x] Phase 3: Add Feature-layer use case

**Skills used**: `swift-app-architecture:swift-architecture` (creating-features.md)
**Principles applied**: Plain structs with `run()` methods following UseCase pattern; dependencies via init; kept simple without a separate Uniflow SDK target

**Skills to read**: `swift-app-architecture:swift-architecture` (creating-features.md)

Create a new `SkillBrowserFeature` target in the Features layer. This contains use cases that orchestrate the service and SDK:

- **`LoadSkillsUseCase`** — A `UseCase` conformer:
  - `Options`: `RepositoryConfiguration`
  - `Result`: `[Skill]`
  - Uses `SkillScanner` to scan the repo path, maps `SkillInfo` to `Skill`

- **`LoadRepositoriesUseCase`** — A `UseCase` conformer:
  - `Options`: `Void`
  - `Result`: `[RepositoryConfiguration]`
  - Uses `RepositoryConfigurationStore` to load all configurations

Note: This project doesn't currently have a Uniflow-style `UseCase` protocol. We have two options: (a) add a simple protocol in an SDK target, or (b) just use plain structs with `run()` methods matching the pattern. Since the project is small, define a minimal `UseCase` protocol in a new `Uniflow` SDK target, or inline it in the feature. Decide during implementation — lean toward the simplest approach (inline protocol in the feature or just use plain async methods).

Files to create:
- `AIDevToolsKit/Sources/SkillBrowserFeature/LoadSkillsUseCase.swift`
- `AIDevToolsKit/Sources/SkillBrowserFeature/LoadRepositoriesUseCase.swift`

Update `AIDevToolsKit/Package.swift`: `SkillBrowserFeature` depends on `SkillService` and `SkillScannerSDK`.

## - [x] Phase 4: Add Mac app models and views

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: MV pattern with `@Observable` models injected via `.environment()`; root models owned by `@State` in App struct; enum-based state; view state (`selectedRepoID`) kept in `@State` separate from model state

**Skills to read**: `swift-app-architecture:swift-swiftui`

Wire everything up in the Mac app (`AIDevTools/` Xcode project). Create `@Observable` models and SwiftUI views.

**Models** (Apps layer — in `AIDevTools/`):

- **`SkillBrowserModel`** — `@MainActor @Observable` class:
  - `var repositories: [RepositoryConfiguration] = []`
  - `var selectedRepository: RepositoryConfiguration?`
  - `var skills: [Skill] = []`
  - `var state: ModelState` (enum: `.idle`, `.loading`, `.loaded`, `.error(Error)`)
  - `func loadRepositories()` — calls `LoadRepositoriesUseCase`
  - `func selectRepository(_ repo: RepositoryConfiguration)` — sets selection and calls `LoadSkillsUseCase`
  - `func addRepository(path: URL)` — creates config, saves via store, reloads
  - `func removeRepository(id: UUID)` — removes via store, reloads
  - Initialized with `RepositoryConfigurationStore` and use cases

- **`SettingsModel`** — `@MainActor @Observable` class:
  - `var dataPath: URL` — current data path, persisted (e.g., via `UserDefaults` or a settings JSON file)
  - `func updateDataPath(_ newPath: URL)` — updates and persists

**Views** (Apps layer — in `AIDevTools/`):

- **`SkillBrowserView`** — `NavigationSplitView`:
  - Sidebar: List of repositories with add/remove buttons
  - Detail: List of skills for the selected repository
  - Each skill shows its name

- **`SettingsView`** — Accessible via `Settings` scene (macOS Settings window):
  - Shows current data path
  - Button to change it (folder picker)

- **`AIDevToolsApp`** — Update to:
  - Create `SkillBrowserModel` with dependencies
  - Add `Settings` scene with `SettingsView`
  - Pass model into `SkillBrowserView` via `@State` / `.environment()`

Files to create/modify:
- `AIDevTools/Models/SkillBrowserModel.swift` (new)
- `AIDevTools/Models/SettingsModel.swift` (new)
- `AIDevTools/Views/SkillBrowserView.swift` (new)
- `AIDevTools/Views/SettingsView.swift` (new)
- `AIDevTools/AIDevToolsApp.swift` (modify)
- `AIDevTools/ContentView.swift` (remove or repurpose)

Ensure the Xcode project's target depends on `SkillBrowserFeature`, `SkillService`, and `SkillScannerSDK` from the `AIDevToolsKit` package.

## - [x] Phase 5: Validation

**Skills used**: `swift-testing`
**Principles applied**: Arrange-Act-Assert pattern with section comments; temp directories for filesystem isolation; cleanup via `defer`

**Skills to read**: `swift-testing`

**Unit tests:**
- `SkillServiceTests` — Test `RepositoryConfigurationStore` round-trip (save/load/add/remove) using a temp directory
- `SkillScannerSDKTests` — Test `SkillScanner` against a temp directory with mock `.md` files in `.claude/skills/`
- `SkillBrowserFeatureTests` — Test `LoadSkillsUseCase` with a temp repo directory

**Build verification:**
- Ensure `AIDevToolsKit` package builds with `swift build`
- Ensure the Xcode project builds with the new targets

**Manual smoke test:**
- Launch the Mac app
- Add a repository path (use this repo itself or another with `.claude/skills/`)
- Verify skills appear in the list
- Change data path in Settings and verify it persists
