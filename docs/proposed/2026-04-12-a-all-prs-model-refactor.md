## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Layer placement and dependency rules |
| `ai-dev-tools-enforce` | Post-implementation standards check |

## Rename Reference

| Old Name | New Name | What It Does |
|---|---|---|
| `DiscoverPRsUseCase` | `CachedPRsUseCase` | Reads PR metadata from disk cache |
| `FetchPRListUseCase` | `FetchPRsUseCase` | Fetches PR list from GitHub API |
| `load()` | `loadCached()` | Sets loading state, reads cache, applies metadata to model list |
| `refresh(filter:)` | *(unchanged)* | Fetches all PRs from GitHub matching a filter |
| `syncAndDiscover(prNumber:)` | `refresh(number:)` | Fetches one PR from GitHub, re-reads cache, updates model list |
| `buildPRModels(from:reusingExisting:)` | `PRModel.make(from:reusingExisting:config:)` | Static factory on `PRModel` — creates/reuses instances from metadata, preserving SwiftUI identity |
| `discoverAndMerge(filter:)` | *(deleted)* | Was: read cache + reconcile models + trigger enrichment — split into `cachedPRs`, `applyMetadata`, `loadSummariesInBackground` |
| *(new)* | `cachedPRs(filter:)` | Private acquisition helper — calls `CachedPRsUseCase`, returns `[PRMetadata]` |
| *(new)* | `applyMetadata(_ metadata:)` | Private reconciliation — calls `PRModel.make`, sets state, returns models |

## Background

`AllPRsModel` is hard to follow for two reasons:

**1. Naming doesn't communicate data source or operation type.** Methods like
`discoverAndMerge` and `syncAndDiscover` mix verbs from different concepts. There is no
consistent convention distinguishing disk I/O from network I/O from in-memory work.

**2. Three distinct concerns bleed into each other** inside the same methods:
- **Acquisition** — I/O through use cases that produce `[PRMetadata]` (disk or network)
- **Reconciliation** — pure in-memory: merge fresh `[PRMetadata]` into the live `[PRModel]` list,
  preserving SwiftUI identity by reusing instances by ID
- **Enrichment** — background disk I/O per model: `PRModel.loadSummary()` loads analysis
  results after reconciliation

The proposed convention to make data source explicit throughout:
- `cached` = local disk cache
- `fetch` = GitHub network

No behavior changes. Pure rename/restructure only.

## Phases

## - [x] Phase 1: Rename use cases

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Renamed files and structs to apply the cached/fetch convention; updated all references in `AllPRsModel`, `PRRadarRefreshCommand`, and the `startObservingChanges` closure. Deleted old files. Build clean.

**Skills to read**: `ai-dev-tools-architecture`

`DiscoverPRsUseCase` and `FetchPRListUseCase` both sound like "get a list of PRs" with no
indication of where they get it from. Apply the cached/fetch convention, and drop the redundant
"List" suffix from both:

- **`DiscoverPRsUseCase` → `CachedPRsUseCase`**
  - Source: disk cache
  - Update all references across the codebase (use case file, `AllPRsModel`, any tests)

- **`FetchPRListUseCase` → `FetchPRsUseCase`**
  - "List" is redundant; "Fetch" already implies network
  - Update all references across the codebase (use case file, `AllPRsModel`, any tests)

## - [ ] Phase 2: Extract `PRModel.make` static factory

**Skills to read**: `ai-dev-tools-architecture`

`buildPRModels(from:reusingExisting:)` is a pure transformation — `[PRMetadata]` + `[PRModel]?`
→ `[PRModel]` — with no dependency on `AllPRsModel` state. Move it to `PRModel` as a static
factory so it lives with the type it produces.

- **Move `buildPRModels(from:reusingExisting:)` → `PRModel.make(from:reusingExisting:config:)`**
  - Add `config: PRRadarRepoConfig` parameter (needed to construct new `PRModel` instances)
  - Place in `PRModel.swift` or a `PRModel+Factory.swift` extension file

  ```swift
  static func make(
      from metadata: [PRMetadata],
      reusingExisting prior: [PRModel]? = nil,
      config: PRRadarRepoConfig
  ) -> [PRModel] {
      let existingByID = Dictionary(uniqueKeysWithValues: (prior ?? []).map { ($0.id, $0) })
      return metadata.map { meta in
          if let existing = existingByID[meta.id] {
              existing.updateMetadata(meta)
              return existing
          }
          return PRModel(metadata: meta, config: config)
      }
  }
  ```

- Update `applyMetadata` in `AllPRsModel` to call the static:
  ```swift
  let models = PRModel.make(from: metadata, reusingExisting: currentPRModels, config: config)
  ```

## - [ ] Phase 3: Rename and restructure `AllPRsModel`

**Skills to read**: `ai-dev-tools-architecture`

File: `Sources/Apps/AIDevToolsKitMac/PRRadar/Models/AllPRsModel.swift`

**Renames:**

1. **`load()` → `loadCached()`** — makes the disk-only nature explicit.

2. **`syncAndDiscover(prNumber:)` → `refresh(number:)`** — makes it parallel to
   `refresh(filter:)`. Both methods fetch from GitHub and update the in-memory list;
   the only difference is scope (one PR vs. many). Swift's overloading makes the
   relationship clear from the call site.

**Restructure:**

3. **Delete `discoverAndMerge(filter:)`** — it conflates acquisition with reconciliation
   with enrichment. Replace it with three explicit steps at each call site:

   - Add a private acquisition helper:
     ```swift
     private func cachedPRs(filter: PRFilter? = nil) async -> [PRMetadata] {
         await CachedPRsUseCase(config: config).execute(filter: filter)
     }
     ```

   - Extract reconciliation as `applyMetadata` that returns models (no enrichment side effect):
     ```swift
     @discardableResult
     private func applyMetadata(_ metadata: [PRMetadata]) -> [PRModel] {
         let models = PRModel.make(from: metadata, reusingExisting: currentPRModels, config: config)
         state = .ready(models)
         return models
     }
     ```

   - Call enrichment explicitly at each call site — visible, not hidden:
     ```swift
     // loadCached
     let models = applyMetadata(await cachedPRs(filter: config.makeFilter()))
     loadSummariesInBackground(for: models)

     // refresh(filter:) after GitHub fetch
     let models = applyMetadata(metadata)
     loadSummariesInBackground(for: models)

     // refresh(number:) after single-PR sync
     let models = applyMetadata(await cachedPRs(filter: config.makeFilter()))
     loadSummariesInBackground(for: models)
     ```

4. **Update MARK sections** to reflect the three layers:
   ```
   // MARK: - Cache Load          (public: loadCached, refresh(number:))
   // MARK: - GitHub Refresh      (public: refresh(filter:))
   // MARK: - Acquisition         (private: cachedPRs)
   // MARK: - Reconciliation      (private: applyMetadata)
   // MARK: - Enrichment          (private: loadSummariesInBackground)
   // MARK: - Filtering
   // MARK: - Change Observation
   // MARK: - Helpers
   ```

**After the refactor the call graph reads:**
```
init                 → loadCached()
view .task           → refresh(filter:)
view search          → refresh(number:)

loadCached()         → cachedPRs() → applyMetadata() → loadSummariesInBackground()
refresh(filter:)     → FetchPRsUseCase → applyMetadata() → loadSummariesInBackground()
                       → per-PR sync loop
refresh(number:)     → SyncPRUseCase → cachedPRs() → applyMetadata() → loadSummariesInBackground()

applyMetadata()      → PRModel.make(from:reusingExisting:config:)
```

## - [ ] Phase 4: Validation

**Skills to read**: `ai-dev-tools-enforce`

1. `swift build` — must be clean.
2. `swift test` — all tests must pass.
3. Search for old names — all must be zero:
   - `discoverAndMerge`
   - `syncAndDiscover`
   - `DiscoverPRsUseCase`
   - `FetchPRListUseCase`
   - `buildPRModels`
   - `func load()`
4. Read `AllPRsModel` top-to-bottom and verify each method clearly belongs to one layer.
5. Run enforce on all modified files.
