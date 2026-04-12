import Logging
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature
import RepositorySDK
import SwiftUI

struct PRRadarContentView: View {

    private let logger = Logger(label: "PRRadarContentView")

    let isActive: Bool
    let repository: RepositoryConfiguration

    @Environment(WorkspaceModel.self) private var workspaceModel
    @State private var allPRsModel: AllPRsModel?
    @State private var selectedPR: PRModel?
    @State private var showNewReview = false
    @State private var newPRNumber = ""
    @State private var showAnalyzeAll = false
    @State private var showAnalyzeAllProgress = false
    @State private var analyzeAllRuleSets: [RuleSetGroup]? = nil
    @State private var showRefreshProgress = false
    @State private var showAnalyzePR = false
    @State private var analyzePRRuleSets: [RuleSetGroup]? = nil
    @State private var showDeleteConfirmation = false
    @State private var isDeletingPR = false
    @State private var isSearchingPR = false
    @State private var searchError: String?
    @AppStorage("prradar_daysLookBack") private var daysLookBack: Int = 7
    @AppStorage("prradar_selectedPRState") private var selectedPRStateString: String = "OPEN"
    @AppStorage("prradar_selectedRuleFilePaths") private var savedRuleFilePathsJSON: String = ""
    @AppStorage("prradar_baseBranchFilter") private var baseBranchFilter: String = ""
    @AppStorage("prradar_authorFilter") private var authorFilter: String = ""
    @AppStorage("prradar_lastSearchedPRNumber") private var lastSearchedPRNumber: String = ""

    private var showRefreshError: Binding<Bool> {
        Binding(
            get: { if let model = allPRsModel, case .failed = model.state { return true } else { return false } },
            set: { if !$0 { Task { await allPRsModel?.loadCached() } } }
        )
    }

    var body: some View {
        HSplitView {
            prListView
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if isActive {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await selectedPR?.refreshPRData() }
                } label: {
                    if let pr = selectedPR, pr.operationMode == .refreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityIdentifier("refreshButton")
                .help("Refresh PR data")
                .disabled(isPRActionDisabled)

                Button {
                    analyzePRRuleSets = nil
                    showAnalyzePR = true
                } label: {
                    if let pr = selectedPR, pr.operationMode == .analyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .accessibilityIdentifier("analyzeButton")
                .help("Analyze PR")
                .disabled(isPRActionDisabled)
                .popover(isPresented: $showAnalyzePR, arrowEdge: .bottom) {
                    analyzePRPopover
                }

                Button {
                    if let pr = selectedPR {
                        let path = "\(pr.config.resolvedOutputDir)/\(pr.prNumber)"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityIdentifier("folderButton")
                .help("Open PR data in Finder")
                .disabled(selectedPR == nil || isDeletingPR)

                Button {
                    if let pr = selectedPR,
                       let urlString = pr.metadata.url,
                       let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityIdentifier("safariButton")
                .help("Open PR on GitHub")
                .disabled(selectedPR?.metadata.url == nil || isDeletingPR)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    if isDeletingPR {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .accessibilityIdentifier("deleteButton")
                .help("Delete all local data for this PR")
                .disabled(isPRActionDisabled)
                .popover(isPresented: $showDeleteConfirmation, arrowEdge: .bottom) {
                    deleteConfirmationPopover
                }
            }
            }
        }
        .sheet(isPresented: $showAnalyzeAllProgress) {
            if let model = allPRsModel {
                AnalyzeAllProgressView(model: model, isPresented: $showAnalyzeAllProgress)
            }
        }
        .sheet(isPresented: $showRefreshProgress) {
            if let model = allPRsModel {
                RefreshAllProgressView(model: model, isPresented: $showRefreshProgress)
            }
        }
        .alert("Refresh Failed", isPresented: showRefreshError) {
            Button("OK") { Task { await allPRsModel?.loadCached() } }
        } message: {
            if let model = allPRsModel, case .failed(let error, _) = model.state {
                Text(error)
            }
        }
        .alert("PR Search Failed", isPresented: Binding(get: { searchError != nil }, set: { if !$0 { searchError = nil } })) {
            Button("OK") { searchError = nil }
        } message: {
            if let error = searchError {
                Text(error)
            }
        }
        .task(id: repository.id) {
            selectedPR = nil
            guard let config = workspaceModel.prradarConfig(for: repository) else {
                allPRsModel = nil
                return
            }
            let model = AllPRsModel(config: config)
            allPRsModel = model
            await model.refresh(filter: buildFilter())
        }
        .onChange(of: selectedPR) { old, new in
            old?.cancelRefresh()
            logger.info("selectedPR changed", metadata: [
                "old": "\(old?.prNumber.description ?? "nil")",
                "new": "\(new?.prNumber.description ?? "nil")",
            ])
            if let pr = new {
                Task {
                    await pr.loadDetailAsync()
                    if !pr.isPhaseCompleted(.diff) {
                        Task { await pr.refreshDiff() }
                    }
                }
            }
        }
        .background {
            ArrowKeyListener(
                onLeft: { canNavigatePRViolation(by: -1) ? { navigatePRViolation(by: -1) } : nil },
                onRight: { canNavigatePRViolation(by: 1) ? { navigatePRViolation(by: 1) } : nil }
            )
        }
        .onChange(of: filteredPRModels.count) { _, _ in
            if selectedPR == nil, let first = filteredPRModels.first {
                selectedPR = first
            }
        }
    }

    // MARK: - PR List

    private var prListView: some View {
        VStack(spacing: 0) {
            if allPRsModel != nil {
                prListFilterBar
                prViolationNavigationBar
                Divider()
                if filteredPRModels.isEmpty {
                    if allPRsModel?.isLoading == true {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let model = allPRsModel, case .failed(let error, let prior) = model.state, prior == nil {
                        ContentUnavailableView(
                            "PR Radar Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(inTabErrorMessage(error))
                        )
                    } else {
                        ContentUnavailableView(
                            "No Reviews Found",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(allPRsModel?.showOnlyWithPendingComments == true ? "No PRs with pending comments found." : "No PR review data found in the output directory.")
                        )
                    }
                } else {
                    ScrollViewReader { proxy in
                        List(filteredPRModels, selection: $selectedPR) { prModel in
                            PRListRow(prModel: prModel)
                                .id(prModel.id)
                                .tag(prModel)
                        }
                        .listStyle(.sidebar)
                        .accessibilityIdentifier("prList")
                        .onChange(of: selectedPR) { _, newPR in
                            if let pr = newPR {
                                withAnimation {
                                    proxy.scrollTo(pr.id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "PR Radar Not Configured",
                    systemImage: "eye.slash",
                    description: Text("Configure this repository's PR Radar settings in Settings → Repositories.")
                )
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var prListFilterBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Menu("\(daysLookBack)d") {
                    ForEach([1, 7, 14, 30, 60, 90], id: \.self) { days in
                        Button("\(days) days") { daysLookBack = days }
                    }
                }
                .fixedSize()
                .accessibilityIdentifier("daysFilter")
                .help("Days to look back")

                Menu(stateFilterLabel) {
                    ForEach(PRState.allCases, id: \.self) { state in
                        Button(state.displayName) { selectedPRStateString = state.rawValue }
                    }
                }
                .fixedSize()
                .accessibilityIdentifier("stateFilter")
                .help("Filter by PR state")

                Toggle(isOn: Binding(
                    get: { allPRsModel?.showOnlyWithPendingComments ?? false },
                    set: { allPRsModel?.showOnlyWithPendingComments = $0 }
                )) {
                    Image(systemName: "text.bubble")
                }
                .accessibilityIdentifier("pendingCommentsToggle")
                .help("Show only PRs with pending comments")
                .toggleStyle(.button)

                Button {
                    if let model = allPRsModel, model.refreshAllState.isRunning {
                        showRefreshProgress = true
                    } else {
                        Task { await allPRsModel?.refresh(filter: buildFilter()) }
                    }
                } label: {
                    if let model = allPRsModel, model.refreshAllState.isRunning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            if let progressText = model.refreshAllState.progressText {
                                Text(progressText)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
                        .fixedSize()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityIdentifier("refreshListButton")
                .help(allPRsModel?.refreshAllState.isRunning == true ? "Show progress" : "Refresh PR list")

                Spacer()

                Button {
                    if let model = allPRsModel, model.analyzeAllState.isRunning {
                        showAnalyzeAllProgress = true
                    } else {
                        analyzeAllRuleSets = nil
                        showAnalyzeAll = true
                    }
                } label: {
                    if let model = allPRsModel, model.analyzeAllState.isRunning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            if let progressText = model.analyzeAllState.progressText {
                                Text(progressText)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
                        .fixedSize()
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .accessibilityIdentifier("analyzeAllButton")
                .help(allPRsModel?.analyzeAllState.isRunning == true ? "Show progress" : "Analyze all PRs since a date")
                .popover(isPresented: $showAnalyzeAll, arrowEdge: .bottom) {
                    analyzeAllPopover
                }

                Button {
                    newPRNumber = lastSearchedPRNumber
                    showNewReview = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityIdentifier("newReviewButton")
                .help("Search for a PR by number")
                .popover(isPresented: $showNewReview, arrowEdge: .bottom) {
                    newReviewPopover
                }
            }

            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                    TextField(allPRsModel?.config.defaultBaseBranch ?? "Base branch", text: $baseBranchFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                }
                .accessibilityIdentifier("baseBranchFilter")
                .help("Filter by base branch (empty uses config default: \(allPRsModel?.config.defaultBaseBranch ?? "main"))")

                Menu(authorFilterLabel) {
                    Button("All Authors") { authorFilter = "" }
                    if !availableAuthors.isEmpty {
                        Divider()
                        ForEach(availableAuthors, id: \.login) { author in
                            Button(author.displayLabel) { authorFilter = author.login }
                        }
                    }
                }
                .fixedSize()
                .accessibilityIdentifier("authorFilter")
                .help("Filter by PR author")

                Spacer()
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - PR Violation Navigation

    private var prsWithViolations: [PRModel] {
        filteredPRModels.filter { $0.pendingCommentCount > 0 }
    }

    @ViewBuilder
    private var prViolationNavigationBar: some View {
        let violationPRs = prsWithViolations
        if !violationPRs.isEmpty {
            HStack(spacing: 6) {
                Button {
                    navigatePRViolation(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canNavigatePRViolation(by: -1))

                Text(globalViolationLabel(violationPRs: violationPRs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 120)

                Button {
                    navigatePRViolation(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canNavigatePRViolation(by: 1))

                Spacer()
            }
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    private var previousViolationPR: PRModel? {
        let violationPRs = prsWithViolations
        guard let current = selectedPR,
              let currentIndex = violationPRs.firstIndex(of: current)
        else {
            return nil
        }
        let prev = currentIndex - 1
        return prev >= 0 ? violationPRs[prev] : nil
    }

    private var nextViolationPR: PRModel? {
        let violationPRs = prsWithViolations
        guard !violationPRs.isEmpty else { return nil }
        guard let current = selectedPR else {
            return violationPRs.first
        }
        guard let currentIndex = violationPRs.firstIndex(of: current) else {
            return violationPRs.first
        }
        let next = currentIndex + 1
        return next < violationPRs.count ? violationPRs[next] : nil
    }

    private func canNavigatePRViolation(by delta: Int) -> Bool {
        guard let pr = selectedPR else {
            return !prsWithViolations.isEmpty
        }
        if delta > 0 {
            return pr.currentViolationIndex < pr.pendingCommentCount - 1 || nextViolationPR != nil
        } else {
            return pr.currentViolationIndex > 0 || previousViolationPR != nil
        }
    }

    private func navigatePRViolation(by delta: Int) {
        guard let pr = selectedPR else {
            if let first = prsWithViolations.first {
                selectedPR = first
                first.pendingViolationNavigation = .first
            }
            return
        }

        let canAdvanceWithinPR = delta > 0
            ? pr.currentViolationIndex < pr.pendingCommentCount - 1
            : pr.currentViolationIndex > 0

        if canAdvanceWithinPR {
            pr.pendingViolationNavigation = delta > 0 ? .next : .previous
        } else {
            let target = delta > 0 ? nextViolationPR : previousViolationPR
            guard let target else { return }
            selectedPR = target
            target.pendingViolationNavigation = delta > 0 ? .first : .last
        }
    }

    private func globalViolationLabel(violationPRs: [PRModel]) -> String {
        let total = violationPRs.reduce(0) { $0 + $1.pendingCommentCount }
        guard let current = selectedPR,
              let prIndex = violationPRs.firstIndex(of: current) else {
            return "\(total) violations"
        }
        let preceding = violationPRs.prefix(upTo: prIndex).reduce(0) { $0 + $1.pendingCommentCount }
        let currentPosition = preceding + max(current.currentViolationIndex, 0) + 1
        return "\(currentPosition) of \(total) violations"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if allPRsModel != nil {
            if isSearchingPR {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Fetching PR data...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let pr = selectedPR {
                if pr.detailLoaded {
                    ReviewDetailView()
                        .environment(pr)
                        .id(pr.metadata.number)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Select a Pull Request",
                    systemImage: "arrow.left.circle",
                    description: Text("Choose a PR from the list to view its review data.")
                )
            }
        } else {
            ContentUnavailableView(
                "PR Radar Not Configured",
                systemImage: "eye.slash",
                description: Text("Configure this repository's PR Radar settings in Settings → Repositories.")
            )
        }
    }

    // MARK: - Popovers

    @ViewBuilder
    private var newReviewPopover: some View {
        VStack(spacing: 12) {
            Text("New PR Review")
                .font(.headline)

            TextField("PR number", text: $newPRNumber)
                .accessibilityIdentifier("prNumberField")
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit {
                    submitNewReview()
                }

            Button("Start Review") {
                submitNewReview()
            }
            .accessibilityIdentifier("startReviewButton")
            .disabled(Int(newPRNumber) == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    @ViewBuilder
    private var analyzePRPopover: some View {
        rulePickerPopover(
            ruleSets: analyzePRRuleSets,
            title: "Analyze PR",
            subtitle: selectedPR.map { "PR #\($0.prNumber)" },
            onLoad: { analyzePRRuleSets = await loadRuleSets() },
            onStart: { selectedRules in
                saveRuleFilePaths(selectedRules)
                let ruleFilePaths = selectedRules.map(\.filePath)
                showAnalyzePR = false
                Task { await selectedPR?.runAnalysis(ruleFilePaths: ruleFilePaths) }
            },
            onCancel: { showAnalyzePR = false }
        )
    }

    @ViewBuilder
    private var analyzeAllPopover: some View {
        rulePickerPopover(
            ruleSets: analyzeAllRuleSets,
            title: "Analyze All PRs",
            subtitle: "Last \(daysLookBack) days \u{00B7} State: \(stateFilterLabel)",
            onLoad: { analyzeAllRuleSets = await loadRuleSets() },
            onStart: { selectedRules in
                saveRuleFilePaths(selectedRules)
                let ruleFilePaths = selectedRules.map(\.filePath)
                showAnalyzeAll = false
                Task { await allPRsModel?.analyzeAll(filter: buildFilter(), ruleFilePaths: ruleFilePaths) }
            },
            onCancel: { showAnalyzeAll = false }
        )
    }

    @ViewBuilder
    private func rulePickerPopover(
        ruleSets: [RuleSetGroup]?,
        title: String,
        subtitle: String?,
        onLoad: @escaping () async -> Void,
        onStart: @escaping ([ReviewRule]) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        if let ruleSets {
            if ruleSets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Rules Configured")
                        .font(.headline)
                    Text("Add a rule path for this repo in Settings → Repositories → PR Radar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                    Button("Cancel") { onCancel() }
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    Text(title)
                        .font(.headline)
                        .padding(.top, 12)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                    Divider()
                    RulePickerView(
                        ruleSets: ruleSets,
                        initialSelectedFilePaths: savedRuleFilePaths,
                        onStart: onStart,
                        onCancel: onCancel
                    )
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading rules...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .task { await onLoad() }
        }
    }

    private func loadRuleSets() async -> [RuleSetGroup] {
        guard let config = allPRsModel?.config else { return [] }
        do {
            let loaded = try await LoadRulesUseCase(config: config).execute()
            return loaded.map { RuleSetGroup(rulePath: $0.rulePath, rules: $0.rules) }
        } catch {
            logger.error("Failed to load rule sets", metadata: ["error": "\(error.localizedDescription)"])
            return []
        }
    }

    @ViewBuilder
    private var deleteConfirmationPopover: some View {
        VStack(spacing: 12) {
            Text("Delete PR Data")
                .font(.headline)

            Text("All local review data for PR #\(selectedPR.map { "\($0.prNumber)" } ?? "") will be deleted and re-fetched from GitHub.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    showDeleteConfirmation = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Delete", role: .destructive) {
                    showDeleteConfirmation = false
                    guard let pr = selectedPR else { return }
                    isDeletingPR = true
                    Task {
                        defer { isDeletingPR = false }
                        do {
                            try await allPRsModel?.deletePRData(for: pr)
                        } catch {
                            searchError = error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private var selectedPRStateFilter: PRState {
        PRState(rawValue: selectedPRStateString) ?? .open
    }

    private var stateFilterLabel: String {
        selectedPRStateFilter.displayName
    }

    private var sinceDate: Date {
        Calendar.current.date(byAdding: .day, value: -daysLookBack, to: Date()) ?? Date()
    }

    private func submitNewReview() {
        guard let number = Int(newPRNumber), let model = allPRsModel else { return }
        lastSearchedPRNumber = newPRNumber
        showNewReview = false

        if let existing = currentPRModels.first(where: { $0.metadata.number == number }) {
            selectedPR = existing
            return
        }

        isSearchingPR = true
        Task {
            defer { isSearchingPR = false }
            do {
                if let pr = try await model.refresh(number: number) {
                    selectedPR = pr
                }
            } catch {
                searchError = error.localizedDescription
            }
        }
    }

    private var currentPRModels: [PRModel] {
        allPRsModel?.currentPRModels ?? []
    }

    private var filteredPRModels: [PRModel] {
        allPRsModel?.filteredPRModels(filter: buildFilter()) ?? []
    }

    private func buildFilter() -> PRFilter {
        guard let config = allPRsModel?.config else {
            return PRFilter(dateFilter: .updatedSince(sinceDate), state: selectedPRStateFilter)
        }
        return config.makeFilter(
            dateFilter: .updatedSince(sinceDate),
            state: selectedPRStateFilter,
            baseBranch: baseBranchFilter.isEmpty ? nil : baseBranchFilter,
            authorLogin: authorFilter.isEmpty ? nil : authorFilter
        )
    }

    private var authorFilterLabel: String {
        guard !authorFilter.isEmpty else { return "All Authors" }
        if let match = allPRsModel?.availableAuthors.first(where: { $0.login == authorFilter }) {
            return match.displayLabel
        }
        return authorFilter
    }

    private var availableAuthors: [AuthorOption] {
        allPRsModel?.availableAuthors ?? []
    }

    private var isPRActionDisabled: Bool {
        guard let pr = selectedPR else { return true }
        return pr.isAnyPhaseRunning || isDeletingPR
    }

    private var savedRuleFilePaths: Set<String>? {
        guard !savedRuleFilePathsJSON.isEmpty,
              let data = savedRuleFilePathsJSON.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return Set(paths)
    }

    private func saveRuleFilePaths(_ rules: [ReviewRule]) {
        let paths = rules.map(\.filePath)
        if let data = try? JSONEncoder().encode(paths),
           let json = String(data: data, encoding: .utf8) {
            savedRuleFilePathsJSON = json
        }
    }

    private func inTabErrorMessage(_ error: String) -> String {
        if error.contains("No GitHub token") || error.contains("GITHUB_TOKEN") {
            return "No GitHub credentials configured for this repo. Add them in Settings → Credentials."
        }
        return error
    }
}
