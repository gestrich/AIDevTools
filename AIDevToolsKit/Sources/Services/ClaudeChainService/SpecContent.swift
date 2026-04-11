/// Domain models for spec.md content parsing
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Generate stable hash identifier for a task description.
///
/// Uses SHA-256 hash truncated to 8 characters. Normalizes whitespace before hashing
/// so "  Add auth  " and "Add auth" produce the same hash.
public func generateTaskHash(_ description: String) -> String {
    let normalized = description.split(separator: " ").joined(separator: " ")
    let data = normalized.data(using: .utf8) ?? Data()
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).lowercased()
}

public struct SpecTask {
    public let index: Int
    public let description: String
    public let isCompleted: Bool
    public let rawLine: String
    public let taskHash: String

    public init(index: Int, description: String, isCompleted: Bool, rawLine: String, taskHash: String) {
        self.index = index
        self.description = description
        self.isCompleted = isCompleted
        self.rawLine = rawLine
        self.taskHash = taskHash
    }

    public static func fromMarkdownLine(_ line: String, index: Int) -> SpecTask? {
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

    public func toMarkdownLine() -> String {
        let checkbox = isCompleted ? "[x]" : "[ ]"
        return "- \(checkbox) \(description)"
    }
}

public struct SpecContent {
    public let project: Project
    public let content: String
    public let tasks: [SpecTask]

    public init(project: Project, content: String) {
        self.project = project
        self.content = content
        self.tasks = Self.parseTasks(from: content)
    }

    private static func parseTasks(from content: String) -> [SpecTask] {
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

    public var totalTasks: Int {
        tasks.count
    }

    public var completedTasks: Int {
        tasks.filter { $0.isCompleted }.count
    }

    public var pendingTasks: Int {
        totalTasks - completedTasks
    }

    public func getTaskByIndex(_ index: Int) -> SpecTask? {
        (index >= 1 && index <= tasks.count) ? tasks[index - 1] : nil
    }

    public func getNextAvailableTask(skipHashes: Set<String>? = nil) -> SpecTask? {
        let skipHashes = skipHashes ?? Set<String>()
        return tasks.first { !$0.isCompleted && !skipHashes.contains($0.taskHash) }
    }

    public func getPendingTaskIndices() -> [Int] {
        tasks.filter { !$0.isCompleted }.map { $0.index }
    }

    public func toMarkdown() -> String {
        tasks.map { $0.toMarkdownLine() }.joined(separator: "\n")
    }
}
