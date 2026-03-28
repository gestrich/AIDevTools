/// GitHub domain models for ClaudeChain
///
/// These models represent GitHub API objects with type-safe properties and methods.
/// They encapsulate JSON parsing to ensure the service layer works with well-formed
/// domain objects rather than raw dictionaries.
///
/// Following the principle: "Parse once into well-formed models"
import Foundation

/// State of a GitHub pull request.
///
/// Represents the three possible states of a PR as returned by GitHub API.
public enum PRState: String, CaseIterable {
    case open = "open"
    case closed = "closed"
    case merged = "merged"
    
    /// Parse PR state from string (case-insensitive).
    ///
    /// - Parameter state: State string from GitHub API (e.g., "OPEN", "open", "merged")
    /// - Returns: PRState enum value
    /// - Throws: ConfigurationError if state string is not a valid PR state
    public static func fromString(_ state: String) throws -> PRState {
        let normalized = state.lowercased()
        for member in PRState.allCases {
            if member.rawValue == normalized {
                return member
            }
        }
        throw ConfigurationError("Invalid PR state: \(state)")
    }
}

/// Domain model for GitHub user
///
/// Represents a GitHub user from API responses with type-safe properties.
public struct GitHubUser: Equatable {
    public let login: String
    public let name: String?
    public let avatarURL: String?
    
    public init(login: String, name: String? = nil, avatarURL: String? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
    
    /// Parse from GitHub API response
    ///
    /// - Parameter data: Dictionary from GitHub API (e.g., assignee object)
    /// - Returns: GitHubUser instance with parsed data
    public static func fromDict(_ data: [String: Any]) -> GitHubUser {
        return GitHubUser(
            login: data["login"] as? String ?? "",
            name: data["name"] as? String,
            avatarURL: data["avatar_url"] as? String
        )
    }
}

/// Domain model for GitHub pull request
///
/// Represents a PR from GitHub API with type-safe properties and helper methods.
/// All date parsing and JSON navigation happens in fromDict() constructor.
public struct GitHubPullRequest: Equatable {
    public let number: Int
    public let title: String
    public let state: String  // "open", "closed", "merged"
    public let createdAt: Date
    public let mergedAt: Date?
    public let assignees: [GitHubUser]
    public let labels: [String]
    public let headRefName: String?  // Branch name (source branch)
    public let baseRefName: String?  // Target branch (branch PR was merged into)
    public let url: String?  // PR URL (e.g., https://github.com/owner/repo/pull/123)
    
    public init(
        number: Int,
        title: String,
        state: String,
        createdAt: Date,
        mergedAt: Date? = nil,
        assignees: [GitHubUser] = [],
        labels: [String] = [],
        headRefName: String? = nil,
        baseRefName: String? = nil,
        url: String? = nil
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.createdAt = createdAt
        self.mergedAt = mergedAt
        self.assignees = assignees
        self.labels = labels
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.url = url
    }
    
    /// Parse from GitHub API response
    ///
    /// Handles all JSON parsing, date conversion, and nested object construction.
    /// Service layer receives clean, type-safe objects.
    ///
    /// - Parameter data: Dictionary from GitHub API (gh pr list --json output)
    /// - Returns: GitHubPullRequest instance with all fields parsed
    public static func fromDict(_ data: [String: Any]) -> GitHubPullRequest {
        // Parse created_at (always present)
        let createdAtString = data["createdAt"] as? String ?? ""
        let createdAt = parseISO8601Date(createdAtString) ?? Date()
        
        // Parse merged_at (optional)
        let mergedAt: Date?
        if let mergedAtString = data["mergedAt"] as? String {
            mergedAt = parseISO8601Date(mergedAtString)
        } else {
            mergedAt = nil
        }
        
        // Parse assignees (list of user objects)
        var assignees: [GitHubUser] = []
        if let assigneesData = data["assignees"] as? [[String: Any]] {
            for assigneeData in assigneesData {
                assignees.append(GitHubUser.fromDict(assigneeData))
            }
        }
        
        // Parse labels (list of label objects with "name" field)
        var labels: [String] = []
        if let labelsData = data["labels"] as? [Any] {
            for labelData in labelsData {
                if let labelDict = labelData as? [String: Any],
                   let name = labelDict["name"] as? String {
                    labels.append(name)
                } else if let labelString = labelData as? String {
                    // Handle case where labels are just strings
                    labels.append(labelString)
                }
            }
        }
        
        // Normalize state to lowercase for consistency
        let state = (data["state"] as? String ?? "").lowercased()
        
        // Get branch names if available
        let headRefName = data["headRefName"] as? String
        let baseRefName = data["baseRefName"] as? String
        
        // Get PR URL if available
        let url = data["url"] as? String
        
        return GitHubPullRequest(
            number: data["number"] as? Int ?? 0,
            title: data["title"] as? String ?? "",
            state: state,
            createdAt: createdAt,
            mergedAt: mergedAt,
            assignees: assignees,
            labels: labels,
            headRefName: headRefName,
            baseRefName: baseRefName,
            url: url
        )
    }
    
    /// Check if PR was merged
    ///
    /// - Returns: True if PR is in merged state or has mergedAt timestamp
    public func isMerged() -> Bool {
        return state == "merged" || mergedAt != nil
    }
    
    /// Check if PR is open
    ///
    /// - Returns: True if PR is in open state
    public func isOpen() -> Bool {
        return state == "open"
    }
    
    /// Check if PR is closed (but not merged)
    ///
    /// - Returns: True if PR is closed but not merged
    public func isClosed() -> Bool {
        return state == "closed" && !isMerged()
    }
    
    /// Check if PR has a specific label
    ///
    /// - Parameter label: Label name to check
    /// - Returns: True if PR has the label
    public func hasLabel(_ label: String) -> Bool {
        return labels.contains(label)
    }
    
    /// Get list of assignee usernames
    ///
    /// - Returns: List of login names for all assignees
    public func getAssigneeLogins() -> [String] {
        return assignees.map { $0.login }
    }
    
    /// Extract project name from branch name.
    ///
    /// Parses the branch name using ClaudeChain branch naming convention
    /// (claude-chain-{project_name}-{index}) and returns the project name.
    ///
    /// - Returns: Project name if branch follows ClaudeChain pattern, nil otherwise
    public var projectName: String? {
        guard let headRefName = headRefName else { return nil }
        return Project.fromBranchName(headRefName)?.name
    }
    
    /// Extract task hash from branch name.
    ///
    /// Parses the branch name using ClaudeChain branch naming convention
    /// and returns the task hash.
    ///
    /// - Returns: Task hash (8-char hex string) if branch follows pattern, nil otherwise
    public var taskHash: String? {
        guard let headRefName = headRefName else { return nil }
        
        // Parse hash from claude-chain-{project}-{hash} format
        let pattern = #"^claude-chain-.+-([0-9a-f]{8})$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(headRefName.startIndex..<headRefName.endIndex, in: headRefName)
        
        if let match = regex?.firstMatch(in: headRefName, options: [], range: range),
           let hashRange = Range(match.range(at: 1), in: headRefName) {
            return String(headRefName[hashRange])
        }
        return nil
    }
    
    /// Get task description with 'ClaudeChain: ' prefix stripped.
    ///
    /// Returns the PR title with the ClaudeChain prefix removed if present.
    /// This is the user-facing task description without automation metadata.
    ///
    /// - Returns: Task description (title with prefix stripped)
    public var taskDescription: String {
        if title.hasPrefix("ClaudeChain: ") {
            return String(title.dropFirst("ClaudeChain: ".count))
        }
        return title
    }
    
    /// Check if PR follows ClaudeChain branch naming convention.
    ///
    /// - Returns: True if branch name matches claude-chain-{project}-{index} pattern
    public var isClaudeChainPR: Bool {
        guard let headRefName = headRefName else { return false }
        return Project.fromBranchName(headRefName) != nil
    }
    
    /// Calculate days the PR was/is open.
    ///
    /// For open PRs: createdAt through now
    /// For closed/merged PRs: createdAt through mergedAt
    ///
    /// - Returns: Number of days the PR has been/was open
    public var daysOpen: Int {
        let endTime: Date
        if state == "open" {
            endTime = Date()
        } else {
            endTime = mergedAt ?? Date()
        }
        let timeInterval = endTime.timeIntervalSince(createdAt)
        return Int(timeInterval / 86400) // 86400 seconds in a day
    }
    
    /// Check if PR is stale based on threshold.
    ///
    /// A PR is considered stale if it has been open for at least
    /// stalePRDays days.
    ///
    /// - Parameter stalePRDays: Number of days before a PR is considered stale
    /// - Returns: True if PR has been open >= stalePRDays
    public func isStale(stalePRDays: Int) -> Bool {
        return daysOpen >= stalePRDays
    }
    
    /// Get the login of the first assignee, if any.
    ///
    /// - Returns: First assignee's login, or nil if no assignees
    public var firstAssignee: String? {
        return assignees.first?.login
    }
}

/// Collection of GitHub pull requests with filtering/grouping methods
///
/// Provides type-safe operations on PR lists without requiring service
/// layer to work with raw JSON arrays.
public struct GitHubPullRequestList {
    public let pullRequests: [GitHubPullRequest]
    
    public init(pullRequests: [GitHubPullRequest] = []) {
        self.pullRequests = pullRequests
    }
    
    /// Parse from GitHub API JSON array
    ///
    /// - Parameter data: List of PR dictionaries from GitHub API
    /// - Returns: GitHubPullRequestList with all PRs parsed
    public static func fromJSONArray(_ data: [[String: Any]]) -> GitHubPullRequestList {
        let prs = data.map { GitHubPullRequest.fromDict($0) }
        return GitHubPullRequestList(pullRequests: prs)
    }
    
    /// Filter PRs by state
    ///
    /// - Parameter state: State to filter by ("open", "closed", "merged")
    /// - Returns: New GitHubPullRequestList with filtered PRs
    public func filterByState(_ state: String) -> GitHubPullRequestList {
        let filtered = pullRequests.filter { $0.state == state.lowercased() }
        return GitHubPullRequestList(pullRequests: filtered)
    }
    
    /// Filter PRs by label
    ///
    /// - Parameter label: Label name to filter by
    /// - Returns: New GitHubPullRequestList with PRs that have the label
    public func filterByLabel(_ label: String) -> GitHubPullRequestList {
        let filtered = pullRequests.filter { $0.hasLabel(label) }
        return GitHubPullRequestList(pullRequests: filtered)
    }
    
    /// Get only merged PRs
    ///
    /// - Returns: New GitHubPullRequestList with only merged PRs
    public func filterMerged() -> GitHubPullRequestList {
        let filtered = pullRequests.filter { $0.isMerged() }
        return GitHubPullRequestList(pullRequests: filtered)
    }
    
    /// Get only open PRs
    ///
    /// - Returns: New GitHubPullRequestList with only open PRs
    public func filterOpen() -> GitHubPullRequestList {
        let filtered = pullRequests.filter { $0.isOpen() }
        return GitHubPullRequestList(pullRequests: filtered)
    }
    
    /// Filter PRs by date
    ///
    /// - Parameters:
    ///   - since: Minimum date (PRs on or after this date)
    ///   - dateField: Which date field to check ("created_at" or "merged_at")
    /// - Returns: New GitHubPullRequestList with PRs matching date criteria
    public func filterByDate(since: Date, dateField: String = "created_at") -> GitHubPullRequestList {
        let filtered = pullRequests.filter { pr in
            switch dateField {
            case "created_at":
                return pr.createdAt >= since
            case "merged_at":
                return pr.mergedAt?.timeIntervalSince(since) ?? -1 >= 0
            default:
                return false
            }
        }
        return GitHubPullRequestList(pullRequests: filtered)
    }
    
    /// Group PRs by assignee
    ///
    /// PRs with multiple assignees appear in multiple groups.
    ///
    /// - Returns: Dictionary mapping assignee login to list of PRs
    public func groupByAssignee() -> [String: [GitHubPullRequest]] {
        var grouped: [String: [GitHubPullRequest]] = [:]
        for pr in pullRequests {
            for assignee in pr.assignees {
                if grouped[assignee.login] == nil {
                    grouped[assignee.login] = []
                }
                grouped[assignee.login]?.append(pr)
            }
        }
        return grouped
    }
    
    /// Get count of PRs in list
    ///
    /// - Returns: Number of PRs
    public func count() -> Int {
        return pullRequests.count
    }
}

/// Domain model for GitHub Actions workflow run
///
/// Represents a workflow run from GitHub API with type-safe properties.
/// Used for tracking workflow execution status in E2E tests and monitoring.
public struct WorkflowRun {
    public let databaseID: Int
    public let status: String  // "queued", "in_progress", "completed"
    public let conclusion: String?  // "success", "failure", "cancelled", etc.
    public let createdAt: Date
    public let headBranch: String
    public let url: String
    
    public init(
        databaseID: Int,
        status: String,
        conclusion: String?,
        createdAt: Date,
        headBranch: String,
        url: String
    ) {
        self.databaseID = databaseID
        self.status = status
        self.conclusion = conclusion
        self.createdAt = createdAt
        self.headBranch = headBranch
        self.url = url
    }
    
    /// Parse from GitHub API response
    ///
    /// - Parameter data: Dictionary from GitHub API (workflow run object)
    /// - Returns: WorkflowRun instance with parsed data
    public static func fromDict(_ data: [String: Any]) -> WorkflowRun {
        // Parse created_at
        let createdAtString = data["createdAt"] as? String ?? ""
        let createdAt = parseISO8601Date(createdAtString) ?? Date()
        
        return WorkflowRun(
            databaseID: data["databaseId"] as? Int ?? 0,
            status: data["status"] as? String ?? "",
            conclusion: data["conclusion"] as? String,
            createdAt: createdAt,
            headBranch: data["headBranch"] as? String ?? "",
            url: data["url"] as? String ?? ""
        )
    }
    
    /// Check if workflow run has completed
    ///
    /// - Returns: True if workflow run is completed
    public func isCompleted() -> Bool {
        return status == "completed"
    }
    
    /// Check if workflow run succeeded
    ///
    /// - Returns: True if workflow run completed successfully
    public func isSuccess() -> Bool {
        return isCompleted() && conclusion == "success"
    }
    
    /// Check if workflow run failed
    ///
    /// - Returns: True if workflow run completed with failure
    public func isFailure() -> Bool {
        return isCompleted() && conclusion == "failure"
    }
}

/// Domain model for GitHub pull request comment
///
/// Represents a comment on a pull request from GitHub API.
/// Used for testing and verification of automated PR interactions.
public struct PRComment {
    public let body: String
    public let author: String
    public let createdAt: Date
    
    public init(body: String, author: String, createdAt: Date) {
        self.body = body
        self.author = author
        self.createdAt = createdAt
    }
    
    /// Parse from GitHub API response
    ///
    /// - Parameter data: Dictionary from GitHub API (comment object)
    /// - Returns: PRComment instance with parsed data
    public static func fromDict(_ data: [String: Any]) -> PRComment {
        // Parse created_at
        let createdAtString = data["createdAt"] as? String ?? ""
        let createdAt = parseISO8601Date(createdAtString) ?? Date()
        
        // Extract author login
        let author: String
        if let authorDict = data["author"] as? [String: Any],
           let login = authorDict["login"] as? String {
            author = login
        } else if let authorString = data["author"] as? String {
            author = authorString
        } else {
            author = ""
        }
        
        return PRComment(
            body: data["body"] as? String ?? "",
            author: author,
            createdAt: createdAt
        )
    }
}

// MARK: - Helper Functions

/// Parse ISO8601 date string to Date
///
/// - Parameter dateString: ISO8601 date string (e.g., "2024-01-01T12:00:00Z")
/// - Returns: Date object or nil if parsing fails
private func parseISO8601Date(_ dateString: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: dateString) {
        return date
    }
    
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: dateString)
}