import ClaudeChainService
import Foundation

/// Repository for loading project data from GitHub or local filesystem
public class ProjectRepository {
    private let repo: String
    private let gitHubOperations: GitHubOperationsProtocol
    
    /// Initialize repository
    ///
    /// - Parameter repo: GitHub repository in format 'owner/name'
    /// - Parameter gitHubOperations: GitHubOperations instance for dependency injection (defaults to real GitHubOperations)
    public init(repo: String, gitHubOperations: GitHubOperationsProtocol) {
        self.repo = repo
        self.gitHubOperations = gitHubOperations
    }
    
    // MARK: - Local Filesystem Methods (post-checkout)
    
    /// Load and parse project configuration from local filesystem.
    ///
    /// Use this method after checkout when the project files are available locally.
    /// This is more efficient than making GitHub API calls and is preferred for
    /// merge event handling.
    ///
    /// If configuration.yml doesn't exist, returns default configuration
    /// (no assignee, no base branch override). This allows projects to work
    /// with sensible defaults without requiring a configuration file.
    ///
    /// - Parameter project: Project domain model
    /// - Returns: Parsed ProjectConfiguration or default configuration if not found
    /// - Throws: ConfigurationError if configuration file exists but is invalid
    public func loadLocalConfiguration(project: Project) throws -> ProjectConfiguration {
        guard FileManager.default.fileExists(atPath: project.configPath) else {
            return ProjectConfiguration.default(project: project)
        }
        
        let configContent = try String(contentsOfFile: project.configPath, encoding: .utf8)
        return try ProjectConfiguration.fromYAMLString(project: project, yamlContent: configContent)
    }
    
    /// Load and parse spec.md from local filesystem.
    ///
    /// Use this method after checkout when the project files are available locally.
    ///
    /// - Parameter project: Project domain model
    /// - Returns: Parsed SpecContent or nil if not found
    public func loadLocalSpec(project: Project) throws -> SpecContent? {
        guard FileManager.default.fileExists(atPath: project.specPath) else {
            return nil
        }
        
        let specContent = try String(contentsOfFile: project.specPath, encoding: .utf8)
        
        if specContent.isEmpty {
            return nil
        }
        
        return SpecContent(project: project, content: specContent)
    }
    
    // MARK: - GitHub API Methods (remote fetch)
    
    /// Load and parse project configuration from GitHub
    ///
    /// If configuration.yml doesn't exist, returns default configuration
    /// (no assignee, no base branch override). This allows projects to work
    /// with sensible defaults without requiring a configuration file.
    ///
    /// - Parameter project: Project domain model
    /// - Parameter baseBranch: Branch to fetch from
    /// - Returns: Parsed ProjectConfiguration or default configuration if not found
    /// - Throws: GitHubAPIError if GitHub API fails, ConfigurationError if configuration is invalid
    public func loadConfiguration(project: Project, baseBranch: String = "main") throws -> ProjectConfiguration {
        let configContent = try gitHubOperations.getFileFromBranch(
            repo: repo,
            branch: baseBranch,
            filePath: project.configPath
        )
        
        guard let configContent = configContent else {
            return ProjectConfiguration.default(project: project)
        }
        
        return try ProjectConfiguration.fromYAMLString(project: project, yamlContent: configContent)
    }
    
    /// Load configuration only if it exists, returning nil otherwise.
    ///
    /// Use this method when you need to distinguish between projects with
    /// and without configuration files.
    ///
    /// - Parameter project: Project domain model
    /// - Parameter baseBranch: Branch to fetch from
    /// - Returns: Parsed ProjectConfiguration or nil if file doesn't exist
    /// - Throws: GitHubAPIError if GitHub API fails, ConfigurationError if configuration is invalid
    public func loadConfigurationIfExists(project: Project, baseBranch: String = "main") throws -> ProjectConfiguration? {
        let configContent = try gitHubOperations.getFileFromBranch(
            repo: repo,
            branch: baseBranch,
            filePath: project.configPath
        )
        
        guard let configContent = configContent else {
            return nil
        }
        
        return try ProjectConfiguration.fromYAMLString(project: project, yamlContent: configContent)
    }
    
    /// Load and parse spec.md from GitHub
    ///
    /// - Parameter project: Project domain model
    /// - Parameter baseBranch: Branch to fetch from
    /// - Returns: Parsed SpecContent or nil if not found
    /// - Throws: GitHubAPIError if GitHub API fails
    public func loadSpec(project: Project, baseBranch: String = "main") throws -> SpecContent? {
        let specContent = try gitHubOperations.getFileFromBranch(
            repo: repo,
            branch: baseBranch,
            filePath: project.specPath
        )
        
        guard let specContent = specContent else {
            return nil
        }
        
        if specContent.isEmpty {
            return nil
        }
        
        return SpecContent(project: project, content: specContent)
    }
    
    /// Load complete project data (config + spec)
    ///
    /// Configuration is optional - if not found, uses default configuration.
    /// Spec is required - if not found, returns nil.
    ///
    /// - Parameter projectName: Name of the project
    /// - Parameter baseBranch: Branch to fetch from
    /// - Returns: Tuple of (Project, ProjectConfiguration, SpecContent) or nil if spec not found
    public func loadProjectFull(projectName: String, baseBranch: String = "main") throws -> (Project, ProjectConfiguration, SpecContent)? {
        let project = Project(name: projectName)
        
        // Spec is required for a valid project
        guard let spec = try loadSpec(project: project, baseBranch: baseBranch) else {
            return nil
        }
        
        // Config is optional - uses defaults if not found
        let config = try loadConfiguration(project: project, baseBranch: baseBranch)
        
        return (project, config, spec)
    }
}