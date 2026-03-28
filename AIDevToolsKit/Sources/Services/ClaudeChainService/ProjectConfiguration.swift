/// Domain models for project configuration
import Foundation

/// Domain model for parsed project configuration
///
/// ClaudeChain enforces a single open PR per project. The optional assignees
/// are assigned to PRs when created. Use the `reviewers` list for people who
/// review but should not be assigned.
public struct ProjectConfiguration {
    public let project: Project
    
    /// Optional override for target base branch
    public let baseBranch: String?
    
    /// Optional override for Claude's allowed tools
    public let allowedTools: String?
    
    /// Days before a PR is considered stale
    public let stalePRDays: Int?
    
    /// Optional comma-separated labels to apply to PRs
    public let labels: String?
    
    /// Max concurrent open PRs per project
    public let maxOpenPRs: Int?
    
    public let assignees: [String]
    public let reviewers: [String]
    
    public init(
        project: Project,
        baseBranch: String? = nil,
        allowedTools: String? = nil,
        stalePRDays: Int? = nil,
        labels: String? = nil,
        maxOpenPRs: Int? = nil,
        assignees: [String] = [],
        reviewers: [String] = []
    ) {
        self.project = project
        self.baseBranch = baseBranch
        self.allowedTools = allowedTools
        self.stalePRDays = stalePRDays
        self.labels = labels
        self.maxOpenPRs = maxOpenPRs
        self.assignees = assignees
        self.reviewers = reviewers
    }
    
    /// Factory: Create default configuration when no config file exists.
    ///
    /// Default configuration:
    /// - No assignee (PRs created without assignee)
    /// - No base branch override (uses workflow default)
    /// - No allowed tools override (uses workflow default)
    /// - No labels override (uses workflow default)
    ///
    /// - Parameter project: Project domain model
    /// - Returns: ProjectConfiguration with sensible defaults
    public static func `default`(project: Project) -> ProjectConfiguration {
        return ProjectConfiguration(
            project: project,
            baseBranch: nil,
            allowedTools: nil,
            stalePRDays: nil,
            labels: nil,
            maxOpenPRs: nil
        )
    }
    
    /// Factory: Parse configuration from YAML string
    ///
    /// - Parameters:
    ///   - project: Project domain model
    ///   - yamlContent: YAML content as string
    /// - Returns: ProjectConfiguration instance
    /// - Throws: Configuration errors if YAML is invalid
    public static func fromYAMLString(project: Project, yamlContent: String) throws -> ProjectConfiguration {
        let config = try Config.loadConfigFromString(content: yamlContent, sourceName: project.configPath)
        
        let baseBranch = config["baseBranch"] as? String
        let allowedTools = config["allowedTools"] as? String
        let stalePRDays = config["stalePRDays"] as? Int
        let labels = config["labels"] as? String
        let maxOpenPRs = config["maxOpenPRs"] as? Int
        
        // `assignees` list takes precedence; legacy `assignee` is folded in here at parse time
        let assignees: [String]
        if let yamlAssignees = config["assignees"] {
            assignees = normalizeStringOrList(yamlAssignees)
        } else if let assignee = config["assignee"] as? String {
            assignees = [assignee]
        } else {
            assignees = []
        }
        
        let reviewers: [String]
        if let yamlReviewers = config["reviewers"] {
            reviewers = normalizeStringOrList(yamlReviewers)
        } else {
            reviewers = []
        }
        
        return ProjectConfiguration(
            project: project,
            baseBranch: baseBranch,
            allowedTools: allowedTools,
            stalePRDays: stalePRDays,
            labels: labels,
            maxOpenPRs: maxOpenPRs,
            assignees: assignees,
            reviewers: reviewers
        )
    }
    
    /// Resolve base branch from project config or fall back to default.
    ///
    /// - Parameter defaultBaseBranch: Default from workflow/CLI (required, no default here)
    /// - Returns: Project's baseBranch if set, otherwise the default
    public func getBaseBranch(defaultBaseBranch: String) -> String {
        return baseBranch ?? defaultBaseBranch
    }
    
    /// Resolve allowed tools from project config or fall back to default.
    ///
    /// - Parameter defaultAllowedTools: Default from workflow/CLI (required, no default here)
    /// - Returns: Project's allowedTools if set, otherwise the default
    public func getAllowedTools(defaultAllowedTools: String) -> String {
        return allowedTools ?? defaultAllowedTools
    }
    
    /// Get the number of days before a PR is considered stale.
    ///
    /// - Parameter defaultValue: Default value if not configured (default: DEFAULT_STALE_PR_DAYS)
    /// - Returns: stalePRDays from config if set, otherwise the default
    public func getStalePRDays(defaultValue: Int = Constants.defaultStalePRDays) -> Int {
        return stalePRDays ?? defaultValue
    }
    
    /// Get the maximum number of concurrent open PRs allowed.
    ///
    /// - Parameter defaultValue: Default value if not configured (default: 1)
    /// - Returns: maxOpenPRs from config if set, otherwise the default
    public func getMaxOpenPRs(defaultValue: Int = 1) -> Int {
        return maxOpenPRs ?? defaultValue
    }
    
    /// Resolve labels from project config or fall back to default.
    ///
    /// - Parameter defaultLabels: Default from workflow/CLI (required, no default here)
    /// - Returns: Project's labels if set, otherwise the default
    public func getLabels(defaultLabels: String) -> String {
        return labels ?? defaultLabels
    }
    
    /// Convert to dictionary representation
    ///
    /// - Returns: Dictionary with project and configuration
    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "project": project.name
        ]
        
        if !assignees.isEmpty {
            result["assignees"] = assignees
        }
        if !reviewers.isEmpty {
            result["reviewers"] = reviewers
        }
        if let baseBranch = baseBranch {
            result["baseBranch"] = baseBranch
        }
        if let allowedTools = allowedTools {
            result["allowedTools"] = allowedTools
        }
        if let stalePRDays = stalePRDays {
            result["stalePRDays"] = stalePRDays
        }
        if let labels = labels {
            result["labels"] = labels
        }
        if let maxOpenPRs = maxOpenPRs {
            result["maxOpenPRs"] = maxOpenPRs
        }
        
        return result
    }
}

/// Normalize a YAML value that may be a string or list into a list of strings.
///
/// YAML parses `reviewers: alice` as a string and `reviewers: [alice]` or
/// the block form as a list. This handles both so users don't need to worry
/// about the distinction.
private func normalizeStringOrList(_ value: Any) -> [String] {
    if let stringValue = value as? String {
        return [stringValue]
    } else if let arrayValue = value as? [Any] {
        return arrayValue.map { String(describing: $0) }
    } else {
        return []
    }
}