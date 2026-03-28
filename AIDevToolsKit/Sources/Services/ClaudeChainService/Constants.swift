/// Domain constants for ClaudeChain application.
///
/// Defines application-wide default values and constants that are reusable
/// across different layers of the application.
public struct Constants {
    
    /// Default GitHub label for ClaudeChain PRs
    public static let defaultPRLabel = "claudechain"
    
    /// Default base branch
    public static let defaultBaseBranch = "main"
    
    /// Default metadata branch
    public static let defaultMetadataBranch = "claudechain-metadata"
    
    /// Default statistics lookback period (days)
    public static let defaultStatsDaysBack = 30
    
    /// Default number of days before a PR is considered stale
    public static let defaultStalePRDays = 7
    
    /// Default allowed tools for Claude Code execution
    /// Minimal permissions: file operations + git staging/committing (required by ClaudeChain prompt)
    /// Users can override via CLAUDE_ALLOWED_TOOLS env var or project's allowedTools config
    public static let defaultAllowedTools = "Read,Write,Edit,Bash(git add:*),Bash(git commit:*)"
    
    /// PR Summary file path (used by action.yml and commands)
    public static let prSummaryFilePath = "/tmp/pr-summary.md"
}