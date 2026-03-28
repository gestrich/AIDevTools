/// Domain models for auto-start detection
import Foundation

/// Type of change detected for a project spec file
public enum ProjectChangeType: String, CaseIterable {
    case added = "added"
    case modified = "modified"
    case deleted = "deleted"
}

/// Domain model representing a project detected for potential auto-start
public struct AutoStartProject {
    /// Project name extracted from spec path
    public let name: String
    
    /// Type of change (added, modified, deleted)
    public let changeType: ProjectChangeType
    
    /// Path to the spec.md file (e.g., claude-chain/project-name/spec.md)
    public let specPath: String
    
    public init(name: String, changeType: ProjectChangeType, specPath: String) {
        self.name = name
        self.changeType = changeType
        self.specPath = specPath
    }
}

extension AutoStartProject: CustomStringConvertible {
    /// String representation for debugging
    public var description: String {
        return "AutoStartProject(name: '\(name)', changeType: \(changeType.rawValue), specPath: '\(specPath)')"
    }
}

/// Domain model representing a decision about whether to auto-trigger a project
public struct AutoStartDecision {
    /// The project being evaluated
    public let project: AutoStartProject
    
    /// Whether the workflow should be triggered for this project
    public let shouldTrigger: Bool
    
    /// Human-readable reason for the decision
    public let reason: String
    
    public init(project: AutoStartProject, shouldTrigger: Bool, reason: String) {
        self.project = project
        self.shouldTrigger = shouldTrigger
        self.reason = reason
    }
}

extension AutoStartDecision: CustomStringConvertible {
    /// String representation for debugging
    public var description: String {
        let action = shouldTrigger ? "TRIGGER" : "SKIP"
        return "AutoStartDecision(\(action): \(project.name) - \(reason))"
    }
}