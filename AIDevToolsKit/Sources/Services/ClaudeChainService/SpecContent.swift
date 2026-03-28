/// Domain models for spec.md content parsing
import CryptoKit
import Foundation

/// Generate stable hash identifier for a task description.
///
/// Uses SHA-256 hash truncated to 8 characters for readability.
/// This provides a stable identifier that doesn't change when tasks
/// are reordered in spec.md, only when the description itself changes.
///
/// - Parameter description: Task description text
/// - Returns: 8-character hash string (lowercase hexadecimal)
///
/// Examples:
/// ```swift
/// generateTaskHash("Add user authentication") // "a3f2b891"
/// generateTaskHash("  Add user authentication  ") // "a3f2b891" (same hash after whitespace normalization)
/// ```
public func generateTaskHash(_ description: String) -> String {
    // Normalize whitespace: strip leading/trailing, collapse internal whitespace
    let normalized = description.split(separator: " ").joined(separator: " ")
    
    // Compute SHA-256 hash of normalized description
    let data = normalized.data(using: .utf8) ?? Data()
    let hash = SHA256.hash(data: data)
    
    // Convert to hex and truncate to 8 characters
    // 8 hex chars = 32 bits = ~4 billion combinations (sufficient for task lists)
    return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).lowercased()
}

/// Domain model for a task in spec.md
public struct SpecTask {
    /// 1-based position in file
    public let index: Int
    
    public let description: String
    public let isCompleted: Bool
    
    /// Original markdown line
    public let rawLine: String
    
    /// 8-character hash of task description
    public let taskHash: String
    
    public init(index: Int, description: String, isCompleted: Bool, rawLine: String, taskHash: String) {
        self.index = index
        self.description = description
        self.isCompleted = isCompleted
        self.rawLine = rawLine
        self.taskHash = taskHash
    }
    
    /// Parse task from markdown checklist line
    ///
    /// - Parameters:
    ///   - line: Markdown line to parse (e.g., "- [ ] Task description")
    ///   - index: Task index (1-based)
    /// - Returns: SpecTask instance or nil if line doesn't match task pattern
    public static func fromMarkdownLine(_ line: String, index: Int) -> SpecTask? {
        // Pattern: "- [ ]" or "- [x]" or "- [X]"
        let pattern = #"^\s*- \[([xX ])\]\s*(.+)$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        
        guard let match = regex?.firstMatch(in: line, options: [], range: range),
              let checkboxRange = Range(match.range(at: 1), in: line),
              let descriptionRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        
        let checkbox = String(line[checkboxRange])
        let description = String(line[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompleted = checkbox.lowercased() == "x"
        
        return SpecTask(
            index: index,
            description: description,
            isCompleted: isCompleted,
            rawLine: line,
            taskHash: generateTaskHash(description)
        )
    }
    
    /// Convert task back to markdown format
    ///
    /// - Returns: Markdown string like "- [ ] Task description" or "- [x] Task description"
    public func toMarkdownLine() -> String {
        let checkbox = isCompleted ? "[x]" : "[ ]"
        return "- \(checkbox) \(description)"
    }
}

/// Domain model for parsed spec.md content
public class SpecContent {
    public let project: Project
    public let content: String
    
    private var _tasks: [SpecTask]?
    
    /// Initialize SpecContent
    ///
    /// - Parameters:
    ///   - project: Project domain model
    ///   - content: Raw spec.md content
    public init(project: Project, content: String) {
        self.project = project
        self.content = content
    }
    
    /// Lazily parse and return all tasks from spec
    ///
    /// - Returns: List of SpecTask instances
    public var tasks: [SpecTask] {
        if _tasks == nil {
            _tasks = parseTasks()
        }
        return _tasks!
    }
    
    /// Parse all tasks from markdown content
    ///
    /// - Returns: List of SpecTask instances
    private func parseTasks() -> [SpecTask] {
        var tasks: [SpecTask] = []
        var taskIndex = 1
        
        for line in content.components(separatedBy: .newlines) {
            if let task = SpecTask.fromMarkdownLine(line, index: taskIndex) {
                tasks.append(task)
                taskIndex += 1
            }
        }
        
        return tasks
    }
    
    /// Count total tasks
    ///
    /// - Returns: Number of tasks in spec
    public var totalTasks: Int {
        return tasks.count
    }
    
    /// Count completed tasks
    ///
    /// - Returns: Number of completed tasks
    public var completedTasks: Int {
        return tasks.filter { $0.isCompleted }.count
    }
    
    /// Count pending tasks
    ///
    /// - Returns: Number of uncompleted tasks
    public var pendingTasks: Int {
        return totalTasks - completedTasks
    }
    
    /// Get task by 1-based index
    ///
    /// - Parameter index: Task index (1-based)
    /// - Returns: SpecTask instance or nil if index out of range
    public func getTaskByIndex(_ index: Int) -> SpecTask? {
        return (index >= 1 && index <= tasks.count) ? tasks[index - 1] : nil
    }
    
    /// Find the next uncompleted task
    ///
    /// - Parameter skipHashes: Optional set of task hashes to skip
    /// - Returns: Next available SpecTask or nil if all tasks completed
    public func getNextAvailableTask(skipHashes: Set<String>? = nil) -> SpecTask? {
        let skipHashes = skipHashes ?? Set<String>()
        
        for task in tasks {
            // Skip if task is completed
            if task.isCompleted {
                continue
            }
            // Skip if task hash is in skipHashes
            if skipHashes.contains(task.taskHash) {
                continue
            }
            // Found an available task
            return task
        }
        
        return nil
    }
    
    /// Get indices of all pending tasks
    ///
    /// - Returns: List of task indices (1-based)
    public func getPendingTaskIndices() -> [Int] {
        return tasks.filter { !$0.isCompleted }.map { $0.index }
    }
    
    /// Convert all tasks back to markdown format
    ///
    /// - Returns: Markdown string with all tasks
    public func toMarkdown() -> String {
        return tasks.map { $0.toMarkdownLine() }.joined(separator: "\n")
    }
}