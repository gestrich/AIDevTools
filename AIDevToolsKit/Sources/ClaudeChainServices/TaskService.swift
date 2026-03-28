/**
 * Core service for task management operations.
 *
 * Follows Service Layer pattern (Fowler, PoEAA) - encapsulates business logic
 * for task finding, marking, and tracking operations.
 */

import ClaudeChainService
import ClaudeChainSDK
import Foundation

public class TaskService {
    /**
     * Core service for task management operations.
     *
     * Coordinates task finding, marking, and tracking by orchestrating
     * domain models and infrastructure operations. Implements business
     * logic for ClaudeChain's task workflow.
     */
    
    private let repo: String
    private let prService: PRService
    
    /**
     * Initialize TaskService
     *
     * Args:
     *     repo: GitHub repository (owner/name)
     *     prService: Service for PR operations
     */
    public init(repo: String, prService: PRService) {
        self.repo = repo
        self.prService = prService
    }
    
    // MARK: - Public API methods
    
    public func findNextAvailableTask(spec: SpecContent, skipHashes: Set<String>? = nil) -> (Int, String, String)? {
        /**
         * Find first unchecked task not in skipHashes
         *
         * Args:
         *     spec: SpecContent domain model
         *     skipHashes: Set of task hashes to skip (in-progress tasks)
         *
         * Returns:
         *     Tuple of (taskIndex, taskText, taskHash) or nil if no available task found
         *     taskIndex is 1-based position in spec.md
         *     taskHash is 8-character hash of task description
         */
        let skipHashesSet = skipHashes ?? Set<String>()
        
        guard let task = spec.getNextAvailableTask(skipHashes: skipHashesSet) else {
            return nil
        }
        
        // Print skip messages for any tasks we're skipping
        for skippedTask in spec.tasks {
            if !skippedTask.isCompleted && skippedTask.index < task.index {
                if skipHashesSet.contains(skippedTask.taskHash) {
                    let shortHash = String(skippedTask.taskHash.prefix(6))
                    print("Skipping task \(skippedTask.index) (already in progress - hash \(shortHash)...)")
                }
            }
        }
        
        return (task.index, task.description, task.taskHash)
    }
    
    public static func markTaskComplete(planFile: String, task: String) throws {
        /**
         * Mark a task as complete in the spec file
         *
         * Args:
         *     planFile: Path to spec.md file
         *     task: Task description to mark complete
         *
         * Throws:
         *     FileNotFoundError: If spec file doesn't exist
         */
        let fileURL = URL(fileURLWithPath: planFile)
        
        guard FileSystemOperations.fileExists(path: fileURL) else {
            throw FileNotFoundError("Spec file not found: \(planFile)")
        }
        
        let content = try FileSystemOperations.readFile(path: fileURL)
        
        // Replace the unchecked task with checked version
        // Match the task with surrounding whitespace preserved
        let pattern = #"(\s*)- \[ \] "#.appending(NSRegularExpression.escapedPattern(for: task))
        let replacement = "$1- [x] \(task)"
        
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: content.utf16.count)
        let updatedContent = regex.stringByReplacingMatches(
            in: content,
            options: [],
            range: range,
            withTemplate: replacement
        )
        
        try FileSystemOperations.writeFile(path: fileURL, content: updatedContent)
    }
    
    public func getInProgressTasks(label: String, project: String) -> Set<String> {
        /**
         * Get task hashes currently being worked on
         *
         * Args:
         *     label: GitHub label to filter PRs
         *     project: Project name to match
         *
         * Returns:
         *     Set of task hashes from hash-based PRs
         */
        do {
            // Query open PRs for this project using service abstraction
            let openPrs = prService.getOpenPrsForProject(project: project, label: label)
            
            // Extract task hashes using domain model properties
            var taskHashes = Set<String>()
            
            for pr in openPrs {
                if let taskHash = pr.taskHash {
                    taskHashes.insert(taskHash)
                }
            }
            
            return taskHashes
        } catch {
            print("Error: Failed to query GitHub PRs: \(error)")
            return Set<String>()
        }
    }
    
    public func detectOrphanedPrs(label: String, project: String, spec: SpecContent) -> [GitHubPullRequest] {
        /**
         * Detect PRs that reference tasks no longer in spec (orphaned PRs)
         *
         * An orphaned PR is one where the task hash doesn't match any current
         * task hash in spec.md.
         *
         * Args:
         *     label: GitHub label to filter PRs
         *     project: Project name to match
         *     spec: SpecContent domain model with current tasks
         *
         * Returns:
         *     List of orphaned GitHubPullRequest objects
         */
        do {
            // Query all open PRs for this project
            let openPrs = prService.getOpenPrsForProject(project: project, label: label)
            
            // Build set of valid task hashes from current spec
            let validHashes = Set(spec.tasks.map { $0.taskHash })
            
            var orphanedPrs: [GitHubPullRequest] = []
            
            for pr in openPrs {
                if let taskHash = pr.taskHash {
                    if !validHashes.contains(taskHash) {
                        orphanedPrs.append(pr)
                    }
                }
            }
            
            return orphanedPrs
        } catch {
            print("Warning: Failed to detect orphaned PRs: \(error)")
            return []
        }
    }
    
    // MARK: - Static utility methods
    
    public static func generateTaskHash(description: String) -> String {
        /**
         * Generate stable hash identifier for a task description.
         *
         * Uses SHA-256 hash truncated to 8 characters for readability.
         * This provides a stable identifier that doesn't change when tasks
         * are reordered in spec.md, only when the description itself changes.
         *
         * Args:
         *     description: Task description text
         *
         * Returns:
         *     8-character hash string (lowercase hexadecimal)
         *
         * Examples:
         *     TaskService.generateTaskHash("Add user authentication")  // "a3f2b891"
         *     TaskService.generateTaskHash("  Add user authentication  ")  // "a3f2b891" (same hash after whitespace normalization)
         *     TaskService.generateTaskHash("")  // "e3b0c442" (hash of empty string)
         */
        // Delegate to domain model function
        return ClaudeChainService.generateTaskHash(description)
    }
    
    public static func generateTaskId(task: String, maxLength: Int = 30) -> String {
        /**
         * Generate sanitized task ID from task description
         *
         * Args:
         *     task: Task description text
         *     maxLength: Maximum length for the ID
         *
         * Returns:
         *     Sanitized task ID (lowercase, alphanumeric + dashes, truncated)
         */
        // Convert to lowercase and replace non-alphanumeric with dashes
        let sanitized = task.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(maxLength)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        return String(sanitized)
    }
}