import ClaudeChainService
import ClaudeChainSDK
import Foundation
import Logging

public struct StatisticsService {

    private let logger = Logger(label: "StatisticsService")
    private let repo: String
    private let projectRepository: ProjectRepository
    private let prService: PRService
    private let workflowFile: String
    
    /**
     * Initialize the statistics service
     *
     * Args:
     *     repo: GitHub repository (owner/name)
     *     projectRepository: ProjectRepository instance for loading project data
     *     prService: PRService instance for PR operations
     *     workflowFile: Name of the workflow that creates PRs (for artifact discovery)
     */
    public init(repo: String, projectRepository: ProjectRepository, prService: PRService, workflowFile: String) {
        self.repo = repo
        self.projectRepository = projectRepository
        self.prService = prService
        self.workflowFile = workflowFile
    }
    
    // MARK: - Public API methods
    
    public func collectAllStatistics(
        projects: [(String, String)],
        daysBack: Int = Constants.defaultStatsDaysBack,
        label: String = Constants.defaultPRLabel,
        showAssigneeStats: Bool = false
    ) -> StatisticsReport {
        /**
         * Collect statistics for provided projects and team members.
         *
         * Args:
         *     projects: List of (projectName, specBranch) tuples. The caller is
         *         responsible for discovering projects (single or multi-project mode).
         *     daysBack: Days to look back for team member stats
         *     label: GitHub label to filter PRs
         *     showAssigneeStats: Whether to collect reviewer statistics (default: false)
         *
         * Returns:
         *     Complete StatisticsReport
         */
        let startTime = Date()
        let report = StatisticsReport(repo: repo)
        report.generatedAt = startTime
        
        if repo.isEmpty {
            logger.warning("GITHUB_REPOSITORY not set")
            return report
        }

        if projects.isEmpty {
            logger.info("No projects provided")
            return report
        }
        
        // Load configurations for all projects
        var allAssignees = Set<String>()
        var projectConfigs: [(ProjectConfiguration, String)] = []  // List of (ProjectConfiguration, specBranch)
        
        for (projectName, specBranch) in projects {
            do {
                let config = try loadProjectConfig(projectName: projectName, baseBranch: specBranch)
                allAssignees = allAssignees.union(Set(config.assignees))
                projectConfigs.append((config, specBranch))
            } catch {
                logger.warning("Failed to load project \(projectName): \(error)")
                continue
            }
        }

        logger.info("Processing \(projectConfigs.count) project(s)...")
        logger.info("Tracking \(allAssignees.count) unique assignee(s)")
        
        // Collect project statistics
        for (config, specBranch) in projectConfigs {
            do {
                if let projectStats = collectProjectStats(
                    projectName: config.project.name,
                    baseBranch: specBranch,
                    label: label,
                    project: config.project,
                    stalePrDays: config.getStalePRDays(),
                    daysBack: daysBack
                ) {
                    report.addProject(projectStats)
                }
            } catch {
                logger.error("Error collecting stats for \(config.project.name): \(error)")
            }
        }
        
        // Collect team member statistics across all projects (only if enabled)
        if showAssigneeStats {
            if !allAssignees.isEmpty {
                do {
                    let teamStats = collectTeamMemberStats(
                        assignees: Array(allAssignees),
                        daysBack: daysBack,
                        label: label
                    )
                    for (username, stats) in teamStats {
                        report.addTeamMember(stats)
                    }
                } catch {
                    print("Error collecting team member stats: \(error)")
                }
            } else {
                logger.info("No assignees configured - skipping team member statistics")
            }
        } else {
            logger.info("Team member statistics disabled - skipping collection")
        }
        
        // Calculate generation time
        let endTime = Date()
        report.generationTimeSeconds = endTime.timeIntervalSince(startTime)
        
        return report
    }
    
    public func collectProjectStats(
        projectName: String,
        baseBranch: String = "main",
        label: String = Constants.defaultPRLabel,
        project: Project? = nil,
        stalePrDays: Int = Constants.defaultStalePRDays,
        daysBack: Int = Constants.defaultStatsDaysBack
    ) -> ProjectStats? {
        /**
         * Collect statistics for a single project
         *
         * Args:
         *     projectName: Name of the project
         *     baseBranch: Base branch to fetch spec from
         *     label: GitHub label for filtering
         *     project: Optional pre-loaded Project instance to avoid re-creating
         *     stalePrDays: Number of days before a PR is considered stale
         *     daysBack: Days to look back for merged PRs (default: 30)
         *
         * Returns:
         *     ProjectStats object, or nil if spec files don't exist in base branch
         */
        logger.info("Collecting statistics for project: \(projectName)")
        
        let proj = project ?? Project(name: projectName, basePath: "\(ClaudeChainConstants.projectDirectoryPrefix)/\(projectName)")
        let stats = ProjectStats(projectName: projectName, specPath: proj.specPath)
        
        // Fetch and parse spec.md using repository
        do {
            guard let spec = try projectRepository.loadSpec(project: proj, baseBranch: baseBranch) else {
                logger.warning("Spec file not found in branch '\(baseBranch)', skipping project")
                return nil
            }

            stats.totalTasks = spec.totalTasks
            stats.completedTasks = spec.completedTasks
            logger.info("Tasks: \(stats.completedTasks)/\(stats.totalTasks) completed")

            // Get PRs from GitHub (open and merged)
            let openPrs = prService.getOpenPrsForProject(project: projectName, label: label)
            stats.inProgressTasks = openPrs.count
            logger.info("In-progress: \(stats.inProgressTasks)")
            
            // Store open PRs and calculate stale count
            for pr in openPrs {
                stats.openPRs.append(pr)
                if pr.isStale(stalePRDays: stalePrDays) {
                    stats.stalePRCount += 1
                }
            }
            
            if stats.stalePRCount > 0 {
                logger.info("Stale PRs: \(stats.stalePRCount) (>\(stalePrDays) days)")
            }

            let mergedPrs = prService.getMergedPrsForProject(project: projectName, label: label, daysBack: daysBack)
            logger.info("Merged PRs (last \(daysBack) days): \(mergedPrs.count)")
            
            // Fetch costs from artifacts (keyed by PR number)
            let costsByPr = getCostsByPr(projectName: projectName)
            
            // Build task-PR mappings (with costs)
            buildTaskPrMappings(stats: stats, spec: spec, openPrs: openPrs, mergedPrs: mergedPrs, costsByPr: costsByPr)
            
            // Calculate pending tasks
            stats.pendingTasks = max(0, stats.totalTasks - stats.completedTasks - stats.inProgressTasks)
            logger.info("Pending: \(stats.pendingTasks)")

            // Aggregate total cost from all tasks
            stats.totalCostUSD = stats.tasks.reduce(0) { $0 + $1.costUSD }
            if stats.totalCostUSD > 0 {
                logger.info(String(format: "Cost: $%.2f", stats.totalCostUSD))
            }
            
            return stats
        } catch {
            logger.warning("Failed to fetch spec file: \(error)")
            return nil
        }
    }
    
    private func buildTaskPrMappings(
        stats: ProjectStats,
        spec: SpecContent,
        openPrs: [GitHubPullRequest],
        mergedPrs: [GitHubPullRequest],
        costsByPr: [Int: Double]
    ) {
        /**
         * Build task-PR mappings and identify orphaned PRs.
         *
         * For each task in spec.md:
         * - Find matching PR by task hash
         * - Determine status based on spec checkbox and PR state
         * - Look up cost from artifacts by PR number
         * - Create TaskWithPR object
         *
         * For each PR:
         * - If task hash doesn't match any spec task, add to orphaned_prs
         *
         * Args:
         *     stats: ProjectStats object to populate
         *     spec: SpecContent with parsed tasks
         *     openPrs: List of open PRs for the project
         *     mergedPrs: List of merged PRs for the project
         *     costsByPr: Dict mapping PR number -> cost in USD
         */
        // Build a lookup map: taskHash -> PR
        var prByHash: [String: GitHubPullRequest] = [:]
        let allPrs = openPrs + mergedPrs
        
        for pr in allPrs {
            if let taskHash = pr.taskHash {
                prByHash[taskHash] = pr
            }
        }
        
        // Track which task hashes we've seen (to identify orphaned PRs)
        var specTaskHashes = Set<String>()
        
        // Process each task from spec
        for task in spec.tasks {
            specTaskHashes.insert(task.taskHash)
            
            // Find matching PR
            let matchingPr = prByHash[task.taskHash]
            
            // Determine status
            let status: TaskStatus
            if task.isCompleted {
                status = .completed
            } else if let pr = matchingPr, pr.isOpen() {
                status = .inProgress
            } else {
                status = .pending
            }
            
            // Look up cost by PR number
            var costUsd = 0.0
            if let pr = matchingPr {
                costUsd = costsByPr[pr.number] ?? 0.0
            }
            
            // Create TaskWithPR
            let taskWithPr = TaskWithPR(
                taskHash: task.taskHash,
                description: task.description,
                status: status,
                pr: matchingPr,
                costUSD: costUsd
            )
            stats.tasks.append(taskWithPr)
        }
        
        // Identify orphaned PRs (PRs whose task hash doesn't match any spec task)
        for pr in allPrs {
            if let taskHash = pr.taskHash, !specTaskHashes.contains(taskHash) {
                stats.orphanedPRs.append(pr)
            }
        }
        
        if !stats.orphanedPRs.isEmpty {
            logger.info("Orphaned PRs: \(stats.orphanedPRs.count)")
        }
    }
    
    private func getCostsByPr(projectName: String) -> [Int: Double] {
        /**
         * Get costs from task metadata artifacts, keyed by PR number.
         *
         * Downloads artifacts for the project and builds a dict mapping PR number
         * to total cost for that PR.
         *
         * Args:
         *     projectName: Name of the project
         *
         * Returns:
         *     Dict mapping PR number -> cost in USD
         */
        let artifacts = ArtifactService.findProjectArtifacts(
            repo: repo,
            project: projectName,
            workflowFile: workflowFile,
            downloadMetadata: true
        )
        
        var costsByPr: [Int: Double] = [:]
        for artifact in artifacts {
            if let metadata = artifact.metadata {
                let prNumber = metadata.prNumber
                let cost = metadata.costUSD
                // Sum costs in case there are multiple artifacts for same PR
                costsByPr[prNumber] = (costsByPr[prNumber] ?? 0.0) + cost
            }
        }
        
        return costsByPr
    }
    
    public func collectTeamMemberStats(
        assignees: [String],
        daysBack: Int = Constants.defaultStatsDaysBack,
        label: String = Constants.defaultPRLabel
    ) -> [String: TeamMemberStats] {
        /**
         * Collect PR statistics for team members from GitHub API
         *
         * Args:
         *     assignees: List of GitHub usernames to track
         *     daysBack: Number of days to look back
         *     label: GitHub label for filtering PRs
         *
         * Returns:
         *     Dict of username -> TeamMemberStats
         */
        var statsDict: [String: TeamMemberStats] = [:]
        
        // Initialize stats for all assignees
        for username in assignees {
            statsDict[username] = TeamMemberStats(username: username)
        }
        
        logger.info("Collecting team member statistics for \(assignees.count) assignee(s)...")
        
        // Calculate cutoff date
        let cutoffDate = Date().addingTimeInterval(-Double(daysBack * 24 * 60 * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let cutoffIso = formatter.string(from: cutoffDate)
        
        logger.info("Looking for PRs since \(cutoffIso)...")
        
        var mergedCount = 0
        var openCount = 0
        
        do {
            // Query all PRs with claudechain label from GitHub using PRService
            let allPrs = prService.getAllPrs(label: label, state: "all", limit: 500)
            
            for pr in allPrs {
                // Skip if no assignee or not a ClaudeChain PR
                if pr.assignees.isEmpty || !pr.isClaudeChainPR {
                    continue
                }
                
                // Use domain model properties instead of manual parsing
                guard let projectName = pr.projectName,
                      let taskHash = pr.taskHash else {
                    continue
                }
                
                // Create PRReference from GitHub PR
                let title = "Task \(String(taskHash.prefix(8))): \(pr.taskDescription)"
                
                // Determine timestamp based on state
                let timestamp = pr.state == "merged" && pr.mergedAt != nil ? pr.mergedAt! : pr.createdAt
                
                let prRef = PRReference(
                    prNumber: pr.number,
                    title: title,
                    project: projectName,
                    timestamp: timestamp
                )
                
                // Add to each assignee's stats (use login strings, not GitHubUser objects)
                for assigneeLogin in pr.getAssigneeLogins() {
                    if let memberStats = statsDict[assigneeLogin] {
                        if pr.state == "merged" {
                            memberStats.addMergedPR(prRef)
                            mergedCount += 1
                        } else if pr.state == "open" {
                            memberStats.addOpenPR(prRef)
                            openCount += 1
                        }
                    }
                }
            }
        } catch {
            logger.warning("Failed to query GitHub PRs: \(error)")
        }

        logger.info("Found \(mergedCount) merged PR(s)")
        logger.info("Found \(openCount) open PR(s)")
        
        return statsDict
    }
    
    // MARK: - Private helper methods
    
    private func loadProjectConfig(projectName: String, baseBranch: String) throws -> ProjectConfiguration {
        /**
         * Load project configuration using repository
         *
         * Args:
         *     projectName: Name of the project
         *     baseBranch: Base branch to fetch config from
         *
         * Returns:
         *     ProjectConfiguration domain model, or throws if config couldn't be loaded
         */
        let project = Project(name: projectName, basePath: "\(ClaudeChainConstants.projectDirectoryPrefix)/\(projectName)")
        return try projectRepository.loadConfiguration(project: project, baseBranch: baseBranch)
    }
    
    // MARK: - Static utility methods
    
    public static func extractCostFromComment(commentBody: String) -> Double? {
        /**
         * Extract total cost from a cost breakdown comment
         *
         * Args:
         *     commentBody: The PR comment body text
         *
         * Returns:
         *     Total cost in USD, or nil if not found
         */
        // Look for the total cost line: | **Total** | **$X.XXXXXX** |
        let pattern = #"\|\s*\*\*Total\*\*\s*\|\s*\*\*\$(\d+\.\d+)\*\*\s*\|"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: commentBody.utf16.count)
            
            if let match = regex.firstMatch(in: commentBody, options: [], range: range) {
                guard let costRange = Range(match.range(at: 1), in: commentBody) else { return nil }
                let costString = String(commentBody[costRange])
                return Double(costString)
            }
        } catch {
            logger.error("Error parsing cost from comment: \(error)")
        }
        
        return nil
    }
}