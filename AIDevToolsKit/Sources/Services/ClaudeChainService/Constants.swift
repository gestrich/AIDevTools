/// ClaudeChain project constants
public struct ClaudeChainConstants {
    /// Spec file name
    public static let specFileName = "spec.md"
    
    /// ClaudeChain projects directory prefix
    public static let projectDirectoryPrefix = "claude-chain"
    
    /// Spec file path pattern for detecting project changes
    /// Format: claude-chain/*/spec.md
    public static let specPathPattern = "\(projectDirectoryPrefix)/*/\(specFileName)"
    
    /// Expected spec file path format: claude-chain/{project_name}/spec.md
    public static let specPathFormat = "\(projectDirectoryPrefix)/{project_name}/\(specFileName)"
    
    /// Default number of days before a PR is considered stale
    public static let defaultStalePRDays = 7
    
    /// Default number of days to look back for statistics
    public static let defaultStatsDaysBack = 30
    
    /// Default PR label for ClaudeChain PRs
    public static let defaultPRLabel = "claudechain"
    
    /// Default base branch for PRs
    public static let defaultBaseBranch = "main"
    
    /// Default PR summary file path
    public static let prSummaryFilePath = "pr-summary.md"
    
    /// Default allowed tools for Claude
    public static let defaultAllowedTools = "computer_20241022"
    
    /// Workflow input parameter keys
    public static let workflowProjectNameKey = "project_name"
    public static let workflowBaseBranchKey = "base_branch"
}

/// Backwards compatibility alias
public typealias Constants = ClaudeChainConstants