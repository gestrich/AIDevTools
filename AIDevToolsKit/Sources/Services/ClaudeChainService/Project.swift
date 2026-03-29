/// Domain model representing a ClaudeChain project
import Foundation

/// Domain model representing a ClaudeChain project with its paths and metadata
public struct Project {
    public let name: String
    public let basePath: String
    
    /// Initialize a Project
    ///
    /// - Parameters:
    ///   - name: Project name
    ///   - basePath: Optional custom base path. Defaults to claude-chain/{name}
    public init(name: String, basePath: String? = nil) {
        self.name = name
        self.basePath = basePath ?? "claude-chain/\(name)"
    }
    
    /// Path to configuration.yml file
    public var configPath: String {
        return "\(basePath)/configuration.yml"
    }
    
    /// Path to spec.md file
    public var specPath: String {
        return "\(basePath)/spec.md"
    }
    
    /// Extract project name from a spec.md file path
    ///
    /// Expected path format: claude-chain/{project_name}/spec.md
    ///
    /// - Parameter path: File path to parse
    /// - Returns: Project name if path matches expected format, nil otherwise
    ///
    /// Examples:
    ///     Project.parseSpecPathToProject("claude-chain/my-project/spec.md")  // returns "my-project"
    ///     Project.parseSpecPathToProject("claude-chain/another/spec.md")    // returns "another" 
    ///     Project.parseSpecPathToProject("invalid/path/spec.md")           // returns nil
    public static func parseSpecPathToProject(path: String) -> String? {
        let parts = path.components(separatedBy: "/")
        
        // Expected format: claude-chain/{project_name}/spec.md
        guard parts.count == 3,
              parts[0] == ClaudeChainConstants.projectDirectoryPrefix,
              parts[2] == ClaudeChainConstants.specFileName else {
            return nil
        }
        
        return parts[1]
    }

    /// Path to pr-template.md file
    public var prTemplatePath: String {
        return "\(basePath)/pr-template.md"
    }
    
    /// Path to metadata JSON file in claudechain-metadata branch
    public var metadataFilePath: String {
        return "\(name).json"
    }
    
    /// Factory: Extract project from config path
    ///
    /// - Parameter configPath: Path like 'claude-chain/my-project/configuration.yml'
    /// - Returns: Project instance
    public static func fromConfigPath(_ configPath: String) -> Project {
        let url = URL(fileURLWithPath: configPath)
        let parentPath = url.deletingLastPathComponent().path
        let projectName = URL(fileURLWithPath: parentPath).lastPathComponent
        return Project(name: projectName)
    }
    
    /// Factory: Parse project from branch name
    ///
    /// - Parameter branchName: Branch name like 'claude-chain-{project}-{hash}' where hash is 8-character hex string
    /// - Returns: Project instance or nil if branch name doesn't match pattern
    public static func fromBranchName(_ branchName: String) -> Project? {
        // Match hash-based format: claude-chain-{project}-{8-char-hex}
        let pattern = #"^claude-chain-(.+)-([0-9a-f]{8})$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(branchName.startIndex..<branchName.endIndex, in: branchName)
        
        if let match = regex?.firstMatch(in: branchName, options: [], range: range),
           let projectRange = Range(match.range(at: 1), in: branchName) {
            let projectName = String(branchName[projectRange])
            return Project(name: projectName)
        }
        return nil
    }
    
    /// Factory: Discover all projects in a directory
    ///
    /// Projects are identified by the presence of spec.md file (not configuration.yml).
    /// This allows projects to exist without a configuration file, using sensible defaults.
    ///
    /// - Parameter baseDir: Directory to scan for projects. Defaults to 'claude-chain'
    /// - Returns: List of Project instances, sorted by name
    public static func findAll(baseDir: String = "claude-chain") -> [Project] {
        var projects: [Project] = []
        
        guard FileManager.default.fileExists(atPath: baseDir) else {
            return projects
        }
        
        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: baseDir)
            for entry in entries {
                let projectPath = (baseDir as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                
                if FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    // Discover projects by spec.md, not configuration.yml
                    let specMd = (projectPath as NSString).appendingPathComponent("spec.md")
                    if FileManager.default.fileExists(atPath: specMd) {
                        projects.append(Project(name: entry))
                    }
                }
            }
        } catch {
            return projects
        }
        
        return projects.sorted { $0.name < $1.name }
    }
}

extension Project: Equatable {
    /// Check equality based on name and basePath
    public static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.name == rhs.name && lhs.basePath == rhs.basePath
    }
}

extension Project: Hashable {
    /// Hash based on name and basePath for use in sets/dicts
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(basePath)
    }
}

extension Project: CustomStringConvertible {
    /// String representation for debugging
    public var description: String {
        return "Project(name: '\(name)', basePath: '\(basePath)')"
    }
}