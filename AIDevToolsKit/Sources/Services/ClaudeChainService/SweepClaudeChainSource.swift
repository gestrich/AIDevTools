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

    private let logger = Logger(label: "SweepClaudeChainSource")
    private static let sweepCommitPrefix = "[claude-sweep]"
    private static let processedKey = "processed:"
    private var sweepLogPattern: String { "claude-sweep.*task=\(taskName)" }
    private var sweepCommitMessage: String { return "\(Self.sweepCommitPrefix) task=\(taskName)" }

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
    nonisolated public var projectName: String { taskName }
    nonisolated public var projectBasePath: String { taskDirectory.path }

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

    /// Returns paths that would be enumerated in the next batch, limited by scanLimit.
    public func candidatesForNextBatch() throws -> [String] {
        let config = try loadSweepConfig()
        let state = try SweepState.load(from: stateURL)
        let paths = try candidatePaths(config: config)
        guard let startIndex = nextPathIndex(in: paths, after: state.cursor) else { return [] }
        return Array(paths[startIndex...].prefix(config.scanLimit))
    }

    /// Evaluates the next batch with skip detection and returns stats without modifying the repo.
    ///
    /// Examines the next `scanLimit`-wide window of paths, reporting how many would be skipped
    /// vs. actually processed (up to `changeLimit`).
    public func dryRunStats() async throws -> SweepBatchStats {
        let config = try loadSweepConfig()
        let state = try SweepState.load(from: stateURL)
        let paths = try candidatePaths(config: config)
        guard let startIndex = nextPathIndex(in: paths, after: state.cursor) else {
            return SweepBatchStats(finalCursor: nil, modifyingTasks: 0, skipped: 0, tasks: 0)
        }

        let window = Array(paths[startIndex...].prefix(config.scanLimit))
        var tasks: [String] = []
        var skippedPaths: [String] = []

        for path in window {
            if tasks.count >= config.changeLimit { break }
            let skip = config.isDirectoryMode
                ? try await canSkipDirectory(path: path)
                : try await canSkip(path: path)
            if skip {
                skippedPaths.append(path)
            } else {
                tasks.append(path)
            }
        }

        let allProcessed = skippedPaths + tasks
        return SweepBatchStats(
            finalCursor: allProcessed.last,
            modifyingTasks: 0,
            skipped: skippedPaths.count,
            tasks: tasks.count
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
            logger.debug("[\(taskName)] Batch limit reached: scanned=\(scanCount)/\(config.scanLimit), modified=\(modifyingTaskCount)/\(config.changeLimit)")
            try await finalizeBatch()
            return nil
        }

        let state = try SweepState.load(from: stateURL)
        let paths = try candidatePaths(config: config)
        // On the first call in a batch, processedPaths is empty so we resume from the persisted cursor.
        let effectiveCursor = processedPaths.last ?? state.cursor

        guard let startIndex = nextPathIndex(in: paths, after: effectiveCursor) else {
            logger.info("[\(taskName)] No more paths after cursor, batch complete")
            try await finalizeBatch()
            return nil
        }

        for path in paths[startIndex...] {
            let skip = config.isDirectoryMode
                ? try await canSkipDirectory(path: path)
                : try await canSkip(path: path)
            if skip {
                logger.debug("[\(taskName)] Skipping unchanged: \(path)")
                processedPaths.append(path)
                continue
            }

            headHashAtTaskStart = try await git.getHeadHash(workingDirectory: repoPath.path)
            let specContent = try String(contentsOf: specURL, encoding: .utf8)
            let scopeLabel = config.isDirectoryMode ? "Directory" : "File"
            return PendingTask(id: path, instructions: specContent + "\n\n\(scopeLabel): \(path)", skills: [])
        }

        logger.info("[\(taskName)] All candidate paths exhausted, batch complete")
        try await finalizeBatch()
        return nil
    }

    public func markComplete(_ task: PendingTask) async throws {
        processedPaths.append(task.id)
        scanCount += 1

        // Commit any AI-produced changes before checking HEAD hash
        let status = try await git.status(workingDirectory: repoPath.path)
        if !status.isEmpty {
            _ = try await git.addAll(workingDirectory: repoPath.path)
            let staged = try await git.diffCachedNames(workingDirectory: repoPath.path)
            if !staged.isEmpty {
                _ = try await git.commit(
                    message: "Sweep [\(taskName)]: \(task.id)",
                    workingDirectory: repoPath.path
                )
            }
        }

        let after = try await git.getHeadHash(workingDirectory: repoPath.path)
        if let before = headHashAtTaskStart, after != before {
            modifyingTaskCount += 1
            logger.debug("[\(taskName)] Task produced changes: \(task.id), modifyingTasks=\(modifyingTaskCount)")
        }
        headHashAtTaskStart = nil
    }

    public func batchStats() -> SweepBatchStats {
        SweepBatchStats(
            finalCursor: processedPaths.last,
            modifyingTasks: modifyingTaskCount,
            skipped: processedPaths.count - scanCount,
            tasks: scanCount
        )
    }

    // MARK: - Static matching

    /// Returns the project name if `path` is a sweep chain spec path, nil otherwise.
    public static func matchesSpecPath(_ path: String) -> String? {
        let parts = path.components(separatedBy: "/")
        guard parts.count == 3,
              parts[0] == ClaudeChainConstants.sweepChainDirectory,
              parts[2] == ClaudeChainConstants.specFileName else { return nil }
        return parts[1]
    }

    /// Returns the project name if `branch` follows the ClaudeChain naming convention, nil otherwise.
    public static func matchesBranchName(_ branch: String) -> String? {
        let pattern = #"^claude-chain-(.+)-([0-9a-f]{8})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(branch.startIndex..<branch.endIndex, in: branch)
        guard let match = regex.firstMatch(in: branch, range: range),
              let nameRange = Range(match.range(at: 1), in: branch) else { return nil }
        return String(branch[nameRange])
    }

    // MARK: - Private

    private var stateURL: URL { taskDirectory.appendingPathComponent("state.json") }
    private var specURL: URL { taskDirectory.appendingPathComponent("spec.md") }
    private var configURL: URL { taskDirectory.appendingPathComponent("config.yaml") }

    private func loadSweepConfig() throws -> SweepConfig {
        let yaml = try Config.loadConfig(filePath: configURL.path)
        let scanLimit = yaml["scanLimit"] as? Int ?? 1
        let rawChangeLimit = yaml["changeLimit"] as? Int ?? 1
        guard let filePattern = yaml["filePattern"] as? String, !filePattern.isEmpty else {
            throw SweepConfigError.missingFilePattern(path: configURL.path)
        }

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
        let allPaths: [String]
        if config.isDirectoryMode {
            allPaths = try expandDirectories(pattern: config.filePattern, repoPath: repoPath.path)
        } else {
            allPaths = try expandGlob(pattern: config.filePattern).sorted()
        }
        return applyScope(config.scope, to: allPaths)
    }

    private func expandDirectories(pattern: String, repoPath: String) throws -> [String] {
        let trimmedPattern = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
        let regexPattern = "^" + globToRegex(trimmedPattern) + "$"
        let regex = try NSRegularExpression(pattern: regexPattern)

        var results: [String] = []
        let resolvedRepo = URL(fileURLWithPath: repoPath).resolvingSymlinksInPath()
        let rootPath = resolvedRepo.path
        guard let enumerator = FileManager.default.enumerator(
            at: resolvedRepo,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let itemURL as URL in enumerator {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }

            var relativePath = itemURL.resolvingSymlinksInPath().path
            guard relativePath.hasPrefix(rootPath + "/") else { continue }
            relativePath = String(relativePath.dropFirst(rootPath.count + 1))

            let range = NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
            if regex.firstMatch(in: relativePath, range: range) != nil {
                results.append(relativePath)
            }
        }
        return results.sorted()
    }

    private func expandGlob(pattern: String) throws -> [String] {
        let regexPattern = "^" + globToRegex(pattern) + "$"
        let regex = try NSRegularExpression(pattern: regexPattern)

        var results: [String] = []
        // Resolve symlinks so that fileURL.path and rootPath share the same base (macOS /var → /private/var).
        let resolvedRepo = repoPath.resolvingSymlinksInPath()
        let rootPath = resolvedRepo.path
        guard let enumerator = FileManager.default.enumerator(
            at: resolvedRepo,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            // File may disappear between enumeration and the resource fetch; treat as non-regular and skip.
            let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegularFile else { continue }

            var relativePath = fileURL.resolvingSymlinksInPath().path
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
        return scope.apply(to: paths)
    }

    private func nextPathIndex(in paths: [String], after cursor: String?) -> Int? {
        guard let cursor else { return paths.isEmpty ? nil : 0 }
        if let i = paths.firstIndex(of: cursor) {
            let next = paths.index(after: i)
            return next < paths.endIndex ? next : nil
        }
        return paths.isEmpty ? nil : 0
    }

    private func canSkipDirectory(path: String) async throws -> Bool {
        let entries = try await git.logGrepAll(sweepLogPattern, workingDirectory: repoPath.path)
        for entry in entries {
            let processedLine = entry.body
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix(Self.processedKey) })
            guard let processedLine else { continue }

            let processedDirs = processedLine
                .dropFirst(Self.processedKey.count)
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }
            guard processedDirs.contains(path) else { continue }

            let hasChanges = try await git.hasDirectoryChanges(from: entry.hash, to: "HEAD", path: path, workingDirectory: repoPath.path)
            return !hasChanges
        }
        return false
    }

    private func canSkip(path: String) async throws -> Bool {
        guard let entry = try await git.logGrep(
            sweepLogPattern,
            workingDirectory: repoPath.path
        ) else { return false }

        let processedLine = entry.body
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix(Self.processedKey) })
        guard let processedLine else { return false }

        let processedFiles = processedLine
            .dropFirst(Self.processedKey.count)
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        guard processedFiles.contains(path) else { return false }

        let hashAtCommit = try await git.getBlobHash(ref: entry.hash, path: path, workingDirectory: repoPath.path)
        let currentHash = try await git.getBlobHash(ref: "HEAD", path: path, workingDirectory: repoPath.path)
        return hashAtCommit == currentHash
    }

    private func finalizeBatch() async throws {
        guard !cursorCommitWritten, !processedPaths.isEmpty else { return }
        cursorCommitWritten = true

        guard let cursor = processedPaths.last else { return }
        var state = try SweepState.load(from: stateURL)
        state.cursor = cursor
        state.lastRunDate = Date()
        try state.save(to: stateURL)

        let processedList = processedPaths.joined(separator: " ")
        let commitMessage = "\(sweepCommitMessage) cursor=\(cursor)\n\(Self.processedKey) \(processedList)"
        // Resolve symlinks so git add/commit work correctly on macOS where /var and /tmp are symlinks.
        let resolvedStatePath = stateURL.resolvingSymlinksInPath().path
        let resolvedRepoPath = repoPath.resolvingSymlinksInPath().path
        try await git.add(files: [resolvedStatePath], workingDirectory: resolvedRepoPath)
        let staged = try await git.diffCachedNames(workingDirectory: resolvedRepoPath)
        guard !staged.isEmpty else {
            logger.info("[\(taskName)] Cursor unchanged, no commit needed: cursor=\(cursor)")
            return
        }
        try await git.commit(message: commitMessage, workingDirectory: resolvedRepoPath)
        logger.info("[\(taskName)] Cursor commit written: cursor=\(cursor), processed=\(processedPaths.count) paths")
    }
}

private enum SweepConfigError: LocalizedError {
    case missingFilePattern(path: String)

    var errorDescription: String? {
        switch self {
        case .missingFilePattern(let path):
            return "'\(path)' is missing required 'filePattern'. Add a 'filePattern' key with a glob pattern (e.g. 'src/**/*.swift' or 'src/*/')."
        }
    }
}

public struct SweepBatchStats: Sendable {
    public let finalCursor: String?
    public let modifyingTasks: Int
    public let skipped: Int
    public let tasks: Int

    public init(finalCursor: String?, modifyingTasks: Int, skipped: Int, tasks: Int) {
        self.finalCursor = finalCursor
        self.modifyingTasks = modifyingTasks
        self.skipped = skipped
        self.tasks = tasks
    }
}
