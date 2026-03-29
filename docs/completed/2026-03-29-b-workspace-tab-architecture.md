> **2026-03-29 Obsolescence Evaluation:** Completed. WorkspaceView now uses TabView architecture and container views exist (SkillsContainer, PlansContainer, EvalsContainer). ClaudeChainView is used directly instead of a container. The tab-based workspace architecture has been successfully implemented.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture — confirms views/models belong in Apps layer |
| `swift-swiftui` | SwiftUI patterns for enum state, observable models, view composition |

## Background

The current `WorkspaceView` is a monolithic view that manages all feature-specific logic (Claude Chain loading, plan loading, skill loading, eval config) directly. Feature concerns leak into the shared workspace — e.g., `claudeChainModel.loadChains()` is called from `WorkspaceView`'s `onChange` handlers.

Bill wants each feature to be an independent container view with its own HSplitView (list + detail), so that:
- Feature logic stays encapsulated within its own container
- Adding a new feature tab doesn't require touching `WorkspaceView`
- Each container manages its own selection, loading, and persistence

The new layout: when a repo is selected, a **tab bar** appears at the top with tabs for each feature. Tapping a tab presents that feature's full container view.

### Current structure
```
NavigationSplitView {
    Repo List
} content: {
    List with all items (flat: arch planner, claude chain, plans, skills)
} detail: {
    switch on selectedItem → different detail views
}
```

### Target structure
```
NavigationSplitView {
    Repo List
} detail: {
    TabView (persisted via AppStorage) {
        ArchitecturePlannerContainer   // own HSplitView: job list | detail
        ClaudeChainContainer           // own HSplitView: chain list | detail
        EvalsContainer                 // conditional, own view
        PlansContainer                 // own HSplitView: plan list | detail
        SkillsContainer                // own HSplitView: skill list | detail
    }
}
```

### Shared styling

Create a `WorkspaceStyle` enum or ViewModifier set providing:
- Consistent list row styling (row height, spacing)
- Consistent detail header bar styling (padding, divider)
- Consistent sidebar width constraints (minWidth, idealWidth)

## Phases

## - [ ] Phase 1: Create shared workspace styling

**Skills to read**: `swift-swiftui`

Create `WorkspaceStyle.swift` in the Views folder with reusable ViewModifiers:
- `sidebarList` modifier — consistent `frame(minWidth: 220, idealWidth: 260)` and list style
- `detailHeader` modifier — consistent header bar padding, background, divider
- Constants for shared sizing

## - [ ] Phase 2: Create `ClaudeChainContainer`

**Skills to read**: `swift-swiftui`

Extract all Claude Chain sidebar/detail logic into a self-contained container view:
- `ClaudeChainContainer`: HSplitView with chain project list on left, `ChainProjectDetailView` on right
- Owns `@AppStorage("selectedChainProject")` for persisting selected project
- Loads chains via `claudeChainModel.loadChains()` in its own `.task` or `.onAppear`
- No coupling to `WorkspaceView` selection state

The existing `ClaudeChainView` and `ChainProjectDetailView` can be refactored into this. The inner `ChainProjectDetailView` stays as-is.

## - [ ] Phase 3: Create `PlansContainer`

**Skills to read**: `swift-swiftui`

Extract plans list + detail into a self-contained container view:
- `PlansContainer`: HSplitView with plan list on left, `MarkdownPlannerDetailView` on right
- Owns `@AppStorage("selectedPlanName")` for persisting selected plan
- Includes the generate sheet button and plan loading logic
- Loads plans via `markdownPlannerModel.loadPlans()` in its own `.task`

## - [ ] Phase 4: Create `SkillsContainer`

**Skills to read**: `swift-swiftui`

Extract skills list + detail into a self-contained container view:
- `SkillsContainer`: HSplitView with skill list on left, `SkillDetailView` on right
- Owns `@AppStorage("selectedSkillName")` for persisting selected skill
- Shows loading state for skills
- Skills are already loaded by `WorkspaceModel.selectRepository()`, so this container just reads `model.skills`

## - [ ] Phase 5: Rework `WorkspaceView` to use tab bar

**Skills to read**: `swift-swiftui`

Replace the current 3-column `NavigationSplitView` with a 2-column layout:
- Left column: Repo list (unchanged)
- Right column: `TabView` with tabs for each feature

```swift
NavigationSplitView {
    // Repo list
} detail: {
    if let repo = model.selectedRepository {
        TabView(selection: $selectedTab) {
            ArchitecturePlannerView(model: architecturePlannerModel)
                .tabItem { Label("Architecture", systemImage: "building.columns") }
                .tag("architecture")
            ClaudeChainContainer(repository: repo)
                .tabItem { Label("Claude Chain", systemImage: "link") }
                .tag("claudeChain")
            // Evals (conditional)
            PlansContainer(repository: repo)
                .tabItem { Label("Plans", systemImage: "doc.text") }
                .tag("plans")
            SkillsContainer(repository: repo)
                .tabItem { Label("Skills", systemImage: "star") }
                .tag("skills")
        }
    }
}
```

- `@AppStorage("selectedWorkspaceTab")` persists which tab is active
- Remove all the `storedArchPlanner`/`storedClaudeChain`/etc. booleans — replaced by the single tab key
- Remove `WorkspaceItem` enum — no longer needed
- Remove feature-specific loading from `WorkspaceView` onChange handlers — each container loads its own data

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

- `swift build` succeeds
- `swift test` — all existing tests pass
- Manual checks:
  - Switching repos changes all tab content
  - Selected tab persists on restart
  - Selected items within each tab persist on restart
  - Each container loads its own data independently
