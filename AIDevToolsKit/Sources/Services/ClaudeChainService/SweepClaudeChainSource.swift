import Foundation
import GitSDK
import Logging
import PipelineSDK
import SweepService

/// `ClaudeChainSource` implementation for sweep-mode chains.
///
/// Iterates over files matching a glob pattern in sorted order, running the AI on each.
/// A cursor in `state.json` persists progress across batches. Skip detection uses
/// `git log` to identify files unchanged since they were last processed.
public actor SweepClaudeChainSource: ClaudeChainSource {

    private let taskName: String
    private let taskDirectory: URL
    private let repoPath: URL
    private let git: GitClient

    private var processedPaths: [String] = []
    private var scanCount: Int = 0
    private var modifyingTaskCount: Int = 0
    private var headHashAtTaskStart: String?
    private var cursorCommitWritten = false

    private static let logger = Logger(label: "SweepClaudeChainSource")

    public init(
        taskName: String,
        taskDirectory: URL,
        repoPath: URL,
        git: GitClient = GitClient()
    ) {
        self.taskName = taskName
        self.taskDirectory = taskDirectory
        self.repoPath = repoPath
        self.git = git
    }

    // MARK: - ClaudeChainSource

    public let kindBadge: String? = "sweep"

    public func loadProject() async throws -> ChainProject {
        let config = try loadSweepConfig()
        let state = try SweepState.load(from: stateURL)
        let paths = try candidatePaths(config: config)

        let tasks = paths.enumerated().map { index, path in
            ChainTask(index: index, description: path, isCompleted: false)
        }

        let pendingCount = nextPathIndex(in: paths, after: state.cursor) != nil ? 1 : 0

        return ChainProject(
            name: taskName,
            specPath: specURL.path,
            tasks: tasks,
            completedTasks: 0,
            pendingTasks: pendingCount,
            totalTasks: tasks.count,
            branchPrefix: "claude-chain-\(taskName)-",
            kindBadge: kindBadge,
            maxOpenPRs: 1
        )
    }

    /// Returns a basic unenriched project detail.
    ///
    /// For enriched PR data use `GetChainDetailUseCase` directly.
    public func loadDetail() async throws -> ChainProjectDetail {
        let project = try await loadProject()
        let enrichedTasks = project.tasks.map { EnrichedChainTask(task: $0) }
        return ChainProjectDetail(project: project, enrichedTasks: enrichedTasks, actionItems: [])
    }

    // MARK: - TaskSource

    public func nextTask() async throws -> PendingTask? {
        let config = try loadSweepConfig()

        if scanCount >= config.scanLimit || modifyingTaskCount >= config.changeLimit {
            Self.logger.debug("[\(taskName)] Batch limit reached: scanned=\(scanCount)/\(config.scanLimit), modified=\(modifyingTaskCount)/\(config.changeLimit)")
            try await finalizeBatch()
            return nil
        }

        let state = try SweepState.load(from: stateURL)
        let paths = try candidatePaths(config: config)
        let effectiveCursor = processedPaths.last ?? state.cursor

        guard let startIndex = nextPathIndex(in: paths, after: effectiveCursor) else {
            Self.logger.info("[\(taskName)] No more files after cursor, batch complete")
            try await finalizeBatch()
            return nil
        }

        for path in paths[startIndex...] {
            if try await canSkip(path: path) {
                Self.logger.debug("[\(taskName)] Skipping unchanged: \(path)")
                processedPaths.append(path)
                continue
            }

            headHashAtTaskStart = try? await git.getHeadHash(workingDirectory: repoPath.path)
            let specContent = try String(contentsOf: specURL, encoding: .utf8)
            return PendingTask(id: path, instructions: specContent + "\n\nFile: \(path)", skills: [])
        }

        Self.logger.info("[\(taskName)] All candidate paths exhausted, batch complete")
        try await finalizeBatch()
        return nil
    }

    public func markComplete(_ task: PendingTask) async throws {
        processedPaths.append(task.id)
        scanCount += 1

        if let before = headHashAtTaskStart,
           let after = try? await git.getHeadHash(workingDirectory: repoPath.path),
           after != before {
            modifyingTaskCount += 1
            Self.logger.debug("[\(taskName)] Task produced changes: \(task.id), modifyingTasks=\(modifyingTaskCount)")
        }
        headHashAtTaskStart = nil
    }

    // MARK: - Private

    private var stateURL: URL { taskDirectory.appendingPathComponent("state.json") }
    private var specURL: URL { taskDirectory.appendingPathComponent("spec.md") }
    private var configURL: URL { taskDirectory.appendingPathComponent("config.yaml") }

    private func loadSweepConfig() throws -> SweepConfig {
        let yaml = try Config.loadConfig(filePath: configURL.path)
        let scanLimit = yaml["scanLimit"] as? Int ?? 1
        let rawChangeLimit = yaml["changeLimit"] as? Int ?? 1
        let filePattern = yaml["filePattern"] as? String ?? ""

        let scope: SweepScope?
        if let scopeDict = yaml["scope"] as? [String: Any], let from = scopeDict["from"] as? String {
            scope = SweepScope(from: from, to: scopeDict["to"] as? String)
        } else {
            scope = nil
        }

        return SweepConfig(
            scanLimit: scanLimit,
            changeLimit: min(rawChangeLimit, scanLimit),
            filePattern: filePattern,
            scope: scope
        )
    }

    private func candidatePaths(config: SweepConfig) throws -> [String] {
        let allPaths = try expandGlob(pattern: config.filePattern).sorted()
        return applyScope(config.scope, to: allPaths)
    }

    private func expandGlob(pattern: String) throws -> [String] {
        let regexPattern = "^" + globToRegex(pattern) + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return [] }

        var results: [String] = []
        let rootPath = repoPath.path
        guard let enumerator = FileManager.default.enumerator(
            at: repoPath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegularFile else { continue }

            var relativePath = fileURL.path
            guard relativePath.hasPrefix(rootPath + "/") else { continue }
            relativePath = String(relativePath.dropFirst(rootPath.count + 1))

            let range = NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
            if regex.firstMatch(in: relativePath, range: range) != nil {
                results.append(relativePath)
            }
        }
        return results
    }

    private func globToRegex(_ pattern: String) -> String {
        var regex = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let char = pattern[index]
            let next = pattern.index(after: index)
            switch char {
            case "*":
                if next < pattern.endIndex && pattern[next] == "*" {
                    regex += ".*"
                    index = pattern.index(after: next)
                    if index < pattern.endIndex && pattern[index] == "/" {
                        index = pattern.index(after: index)
                    }
                    continue
                }
                regex += "[^/]*"
            case "?":
                regex += "[^/]"
            case ".", "+", "^", "$", "|", "(", ")", "[", "]", "{", "}", "\\":
                regex += "\\\(char)"
            default:
                regex += String(char)
            }
            index = next
        }
        return regex
    }

    private func applyScope(_ scope: SweepScope?, to paths: [String]) -> [String] {
        guard let scope else { return paths }
        if let to = scope.to {
            return paths.filter { $0 >= scope.from && $0 < to }
        }
        return paths.filter { $0.hasPrefix(scope.from) }
    }

    private func nextPathIndex(in paths: [String], after cursor: String?) -> Int? {
        guard let cursor else { return paths.isEmpty ? nil : 0 }
        if let i = paths.firstIndex(of: cursor) {
            let next = paths.index(after: i)
            return next < paths.endIndex ? next : nil
        }
        return paths.isEmpty ? nil : 0
    }

    private func canSkip(path: String) async throws -> Bool {
        guard let entry = try await git.logGrep(
            "claude-sweep.*task=\(taskName)",
            workingDirectory: repoPath.path
        ) else { return false }

        let processedLine = entry.body
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("processed:") })
        guard let processedLine else { return false }

        let processedFiles = processedLine
            .dropFirst("processed:".count)
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        guard processedFiles.contains(path) else { return false }

        let hashAtCommit = try? await git.getBlobHash(ref: entry.hash, path: path, workingDirectory: repoPath.path)
        let currentHash = try? await git.getBlobHash(ref: "HEAD", path: path, workingDirectory: repoPath.path)
        guard let hashAtCommit, let currentHash else { return false }
        return hashAtCommit == currentHash
    }

    private func finalizeBatch() async throws {
        guard !cursorCommitWritten, !processedPaths.isEmpty else { return }
        cursorCommitWritten = true

        let cursor = processedPaths.last ?? ""
        var state = try SweepState.load(from: stateURL)
        state.cursor = cursor
        state.lastRunDate = Date()
        try state.save(to: stateURL)

        let processedList = processedPaths.joined(separator: " ")
        let commitMessage = "[claude-sweep] task=\(taskName) cursor=\(cursor)\nprocessed: \(processedList)"
        try await git.add(files: [stateURL.path], workingDirectory: repoPath.path)
        try await git.commit(message: commitMessage, workingDirectory: repoPath.path)
        Self.logger.info("[\(taskName)] Cursor commit written: cursor=\(cursor), processed=\(processedPaths.count) files")
    }
}
