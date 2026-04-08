import ArchitecturePlannerService
import Foundation
import SwiftData
import UseCaseSDK

/// Seeds the guideline store with bundled architecture knowledge and ARCHITECTURE.md content.
/// Idempotent — skips seeding if guidelines already exist for the repo.
public struct SeedGuidelinesUseCase: UseCase {

    public struct Options: Sendable {
        public let repoName: String
        public let repoPath: String

        public init(repoName: String, repoPath: String) {
            self.repoName = repoName
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let guidelinesCreated: Int
        public let skipped: Bool

        public init(guidelinesCreated: Int, skipped: Bool) {
            self.guidelinesCreated = guidelinesCreated
            self.skipped = skipped
        }
    }

    public init() {}

    @MainActor
    public func run(_ options: Options, store: ArchitecturePlannerStore) throws -> Result {
        let context = store.createContext()

        let repoName = options.repoName
        let predicate = #Predicate<Guideline> { $0.repoName == repoName }
        let descriptor = FetchDescriptor<Guideline>(predicate: predicate)
        let existing = try context.fetch(descriptor)

        if !existing.isEmpty {
            return Result(guidelinesCreated: 0, skipped: true)
        }

        var created = 0

        // Seed from ARCHITECTURE.md if it exists
        let architectureMDPath = URL(fileURLWithPath: options.repoPath)
            .appendingPathComponent("ARCHITECTURE.md")
        // Intentional: ARCHITECTURE.md may not exist in all repos; absence is not an error.
        if let content = try? String(contentsOf: architectureMDPath, encoding: .utf8), !content.isEmpty {
            let guideline = Guideline(
                repoName: repoName,
                title: "Repository Architecture (ARCHITECTURE.md)",
                body: content,
                filePathGlobs: ["**/*"],
                highLevelOverview: "The repository's own ARCHITECTURE.md defining layers, modules, and dependency rules specific to this codebase."
            )
            let category = findOrCreateCategory(name: "architecture", repoName: repoName, context: context)
            guideline.categories.append(category)
            context.insert(guideline)
            created += 1
        }

        // Seed bundled swift-architecture guidelines
        for def in Self.swiftArchitectureGuidelines {
            let guideline = Guideline(
                repoName: repoName,
                title: def.title,
                body: def.body,
                filePathGlobs: def.filePathGlobs,
                highLevelOverview: def.overview
            )
            for catName in def.categories {
                let category = findOrCreateCategory(name: catName, repoName: repoName, context: context)
                guideline.categories.append(category)
            }
            context.insert(guideline)
            created += 1
        }

        // Seed bundled swift-swiftui guidelines
        for def in Self.swiftUIGuidelines {
            let guideline = Guideline(
                repoName: repoName,
                title: def.title,
                body: def.body,
                filePathGlobs: def.filePathGlobs,
                highLevelOverview: def.overview
            )
            for catName in def.categories {
                let category = findOrCreateCategory(name: catName, repoName: repoName, context: context)
                guideline.categories.append(category)
            }
            context.insert(guideline)
            created += 1
        }

        try context.save()
        return Result(guidelinesCreated: created, skipped: false)
    }

    @MainActor
    public func runAndListGuidelines(_ options: Options, store: ArchitecturePlannerStore) throws -> [Guideline] {
        _ = try run(options, store: store)
        return try ManageGuidelinesUseCase().listGuidelines(repoName: options.repoName, store: store)
    }

    // MARK: - Helpers

    @MainActor
    private func findOrCreateCategory(name: String, repoName: String, context: ModelContext) -> GuidelineCategory {
        let predicate = #Predicate<GuidelineCategory> { $0.name == name && $0.repoName == repoName }
        let descriptor = FetchDescriptor<GuidelineCategory>(predicate: predicate)
        // Intentional: fetch failure is treated as "not found" and a new category is created.
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let category = GuidelineCategory(name: name, repoName: repoName)
        context.insert(category)
        return category
    }
}

// MARK: - Bundled Guideline Definitions

extension SeedGuidelinesUseCase {

    struct GuidelineDefinition {
        let title: String
        let body: String
        let overview: String
        let filePathGlobs: [String]
        let categories: [String]
    }

    // MARK: swift-architecture guidelines

    static let swiftArchitectureGuidelines: [GuidelineDefinition] = [
        GuidelineDefinition(
            title: "4-Layer Architecture Overview",
            body: """
            A layered architecture for Swift applications: Apps → Features → Services → SDKs.

            Apps Layer: Platform-specific entry points (macOS apps, CLI tools, servers). @Observable models live here. Minimal business logic.
            Features Layer: Multi-step orchestration via UseCase / StreamingUseCase protocols. Not @Observable.
            Services Layer: Shared models, configuration, stateful utilities. No orchestration.
            SDKs Layer: Stateless Sendable structs wrapping single operations. Reusable across projects.

            Dependencies flow downward only: Apps → Features → Services → SDKs. Never depend upward. Features never depend on other features.
            """,
            overview: "4-layer Swift architecture (Apps, Features, Services, SDKs) with strict downward-only dependency flow.",
            filePathGlobs: ["**/*"],
            categories: ["architecture"]
        ),
        GuidelineDefinition(
            title: "Layer Placement Rules",
            body: """
            Decision flow for placing code:
            - UI, @Observable, platform-specific I/O → Apps Layer
            - Multi-step workflow orchestration → Features Layer (UseCase / StreamingUseCase)
            - Shared models, config, stateful utilities → Services Layer
            - Single operation (one API call, one CLI command) → SDKs Layer (stateless Sendable struct)

            Dependency rules:
            - Apps → Features, Services, SDKs
            - Features → Services, SDKs
            - Services → Other Services, SDKs
            - SDKs → Other SDKs, external packages only
            - Features → Other Features: FORBIDDEN
            - Upward dependencies: FORBIDDEN
            """,
            overview: "Decision flowcharts and rules for placing code in the correct architectural layer.",
            filePathGlobs: ["**/*"],
            categories: ["architecture", "layer-placement"]
        ),
        GuidelineDefinition(
            title: "Architecture Principles",
            body: """
            1. Depth Over Width — App-layer code calls ONE use case per user action; orchestration lives in Features.
            2. Zero Duplication — CLI and Mac app share the same use cases and features.
            3. Use Cases Orchestrate — Features expose UseCase / StreamingUseCase conformers for multi-step operations.
            4. SDKs Are Stateless — Single operations, Sendable structs, no business concepts.
            5. @Observable at the App Layer Only — Models consume use case streams; use cases own state data, models own state transitions.
            """,
            overview: "Five core principles: depth over width, zero duplication, use cases orchestrate, stateless SDKs, @Observable at app layer only.",
            filePathGlobs: ["**/*"],
            categories: ["architecture", "conventions"]
        ),
        GuidelineDefinition(
            title: "Creating Features",
            body: """
            Features are use case modules in features/<Name>Feature/:
            - usecases/ — UseCase or StreamingUseCase conformers
            - services/ — Feature-specific types and helpers

            Steps: Create feature module → Define use cases → Add shared types to Services if needed → Connect at app layer (Mac model and/or CLI command).

            Use case rules:
            - Structs, not classes
            - Accept dependencies via init with defaults
            - Options and State are Sendable
            - No @Observable (that belongs in Apps layer)

            Features do NOT contain SwiftUI views, @Observable models, or CLI commands.
            """,
            overview: "How to create feature modules with use cases, proper structure, and app-layer connection.",
            filePathGlobs: ["**/Features/**", "**/features/**"],
            categories: ["architecture", "conventions"]
        ),
        GuidelineDefinition(
            title: "Configuration and Data Paths",
            body: """
            ConfigurationService: Loads typed configuration from JSON files. Lives in Services layer.
            DataPathsService: Type-safe enum-based paths for data storage directories.

            Principles:
            - Apps layer owns initialization of configuration services
            - Use cases receive resolved values (API clients, paths), not config services
            - Fail fast on missing required configuration
            - Optional features use optional child models when config may be absent
            """,
            overview: "Configuration services and data path management in the Services layer, initialized at the Apps layer.",
            filePathGlobs: ["**/Services/**", "**/services/**"],
            categories: ["architecture", "conventions"]
        ),
        GuidelineDefinition(
            title: "Code Style Conventions",
            body: """
            - Imports ordered alphabetically
            - File organization: stored properties → init → computed properties → methods → nested types
            - No type aliases or re-exports
            - Avoid default parameter values — require data explicitly
            - Propagate errors with throws — don't swallow them
            - Only catch errors at the app layer to display to the user
            - No silent fallbacks masking missing data
            """,
            overview: "Code style rules: alphabetical imports, file organization order, no type aliases, explicit parameters, error propagation.",
            filePathGlobs: ["**/*.swift"],
            categories: ["conventions"]
        ),
    ]

    // MARK: swift-swiftui guidelines

    static let swiftUIGuidelines: [GuidelineDefinition] = [
        GuidelineDefinition(
            title: "SwiftUI Model-View Pattern",
            body: """
            SwiftUI follows Model-View (MV) — not MVVM. Views connect directly to @Observable models in the Apps layer.

            Key rules:
            - No dedicated ViewModels per view — models span many views
            - @MainActor on all @Observable models
            - Store root models in the App struct to avoid re-initialization on view rebuilds
            - Business logic belongs in Features (use cases) and SDKs (clients), not models
            """,
            overview: "Model-View (not MVVM) pattern for SwiftUI with @Observable models in the Apps layer only.",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "observable-model"]
        ),
        GuidelineDefinition(
            title: "Enum-Based Model State",
            body: """
            Use enums to represent model state rather than multiple independent properties.

            Benefits: impossible invalid states, exhaustive handling, clear transitions, easier reasoning.

            Pattern:
            enum ModelState {
                case uninitialized
                case loading(prior: Snapshot?)
                case ready(Snapshot)
                case operating(UseCaseState, prior: Snapshot?)
                case error(Error, prior: Snapshot?)
            }

            State ownership: use cases own state data; models own state transitions. Model receives use case state and assigns via a trivial init(from:prior:).
            """,
            overview: "Enum-based state in @Observable models with use case state ownership and trivial state mapping.",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "observable-model"]
        ),
        GuidelineDefinition(
            title: "Model Composition and Lifecycle",
            body: """
            Parent/child model composition:
            - Child models own their state (single source of truth)
            - Parent models must not duplicate child state
            - Models call models, not use cases calling use cases
            - Optional child models for features requiring configuration

            Child-to-parent propagation: use AsyncStream factory methods for multi-subscriber state observation.

            Model lifecycle: models self-initialize on init — no view-triggered loading.
            """,
            overview: "Parent/child model composition, optional child models, AsyncStream propagation, and self-initializing lifecycle.",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "observable-model"]
        ),
        GuidelineDefinition(
            title: "Dependency Injection in SwiftUI",
            body: """
            Global models: inject via Environment at the App root.
            View-scoped models: use @State with initialization in init.

            Handling dependency changes:
            - .id(dependency) when the entire view should reset
            - .onChange(of: dependency) when only the model needs updating
            """,
            overview: "Environment injection for global models, @State for view-scoped models, with .id() and .onChange() for dependency changes.",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "view-patterns"]
        ),
        GuidelineDefinition(
            title: "View State vs Model State",
            body: """
            View state: UI-only concerns (selection, navigation, sheet visibility, scroll offset) → @State / @AppStorage in the view.
            Model state: fetched or created data (API responses, use case outputs) → @Observable model.

            Selection belongs in the view via @State, not in the model. Even when selection triggers data loading, the view owns selection and tells the model to load via .onChange.
            """,
            overview: "View state (@State) for UI concerns like selection; model state (@Observable) for data. Selection always in the view.",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "view-patterns"]
        ),
        GuidelineDefinition(
            title: "View Identity with .id()",
            body: """
            Use .id() when state or identity falls outside normal data-driven view updates:
            - @State initialized in init() with State(initialValue:) — only runs once per view identity
            - .task {}, .onAppear, .onDisappear that need to re-run when dependencies change
            - When you want to reset ALL internal view state

            When .id() receives a new value, SwiftUI destroys the old view instance and creates a fresh one.
            """,
            overview: "The .id() modifier resets view identity, re-running @State initialization and lifecycle hooks when dependencies change.",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "view-patterns"]
        ),
        GuidelineDefinition(
            title: "Model Scalability",
            body: """
            When entities carry heavyweight or streaming data:

            Approach 1 — Model as Provider: entity model returns heavyweight sub-state on demand via factory method. View holds it via @State.
            Approach 2 — Activation/Hydration: parent model owns heavyweight child but only while relevant. Uses activate()/deactivate() as a resource policy.

            Choose Provider when child doesn't need parent coordination. Choose Activation when child must coordinate with parent operations.
            """,
            overview: "Two approaches for heavyweight data in models: Provider (factory method) and Activation/Hydration (lifecycle management).",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "observable-model"]
        ),
        GuidelineDefinition(
            title: "Data Models and Prerequisite Data",
            body: """
            SwiftUI should be driven by well-formed structs representing domain data:
            - Use structs for domain data from services
            - Bundle data fetched together for a view in a struct
            - If a view has many properties for small pieces of data, a model struct is missing

            Prerequisite data: make data a non-optional requirement. Only navigate to the view when data is available. Show placeholders from the parent if data isn't ready.
            """,
            overview: "Domain structs drive views; prerequisite data is non-optional with parent-controlled navigation.",
            filePathGlobs: ["**/Apps/**", "**/apps/**"],
            categories: ["swiftui", "view-patterns"]
        ),
    ]
}
