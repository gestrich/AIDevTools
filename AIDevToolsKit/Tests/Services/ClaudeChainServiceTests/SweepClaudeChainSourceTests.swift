import Foundation
import Testing
@testable import ClaudeChainService

// MARK: - Helpers

private func makeTaskDir(
    in repoDir: URL,
    taskName: String = "test-task",
    scanLimit: Int = 2,
    changeLimit: Int = 2,
    filePattern: String = "Sources/**/*.swift",
    scope: String? = nil
) throws -> URL {
    let taskDir = repoDir.appendingPathComponent("claude-chain-sweep/\(taskName)")
    try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
    try "Review this file.".write(to: taskDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
    var configLines = ["scanLimit: \(scanLimit)", "changeLimit: \(changeLimit)", "filePattern: \(filePattern)"]
    if let scope { configLines.append(scope) }
    try configLines.joined(separator: "\n").write(to: taskDir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
    return taskDir
}

private func makeSourceFile(_ relativePath: String, in repoDir: URL) throws {
    let url = repoDir.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "// \(relativePath)".write(to: url, atomically: true, encoding: .utf8)
}

private func writeCursor(_ path: String?, to taskDir: URL) throws {
    let json = path.map { #"{"cursor":"\#($0)"}"# } ?? #"{"cursor":null}"#
    try json.write(to: taskDir.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
}

private func gitCommitAll(message: String, in dir: URL) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "git add -A && git commit -m '\(message)'"]
    p.currentDirectoryURL = dir
    try? p.run()
    p.waitUntilExit()
}

private func initGitRepo(at dir: URL) {
    let sh: (String) -> Void = { cmd in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        p.currentDirectoryURL = dir
        try? p.run()
        p.waitUntilExit()
    }
    sh("git init")
    sh("git config user.email test@test.com")
    sh("git config user.name Test")
    sh("git add -A && git commit -m 'Initial commit'")
}

private func makeSubDir(_ relativePath: String, in repoDir: URL) throws {
    let url = repoDir.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try "".write(to: url.appendingPathComponent(".gitkeep"), atomically: true, encoding: .utf8)
}

// MARK: - loadProject tests (no git required)

@Suite("SweepClaudeChainSource.loadProject")
struct SweepClaudeChainSourceLoadProjectTests {

    @Test("returns all candidate files as tasks")
    func returnsAllCandidateFilesAsTasks() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir)
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        try makeSourceFile("Sources/A/Two.swift", in: repoDir)
        try makeSourceFile("Sources/B/Three.swift", in: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.tasks.count == 3)
        #expect(project.totalTasks == 3)
    }

    @Test("nil cursor marks one file as pending")
    func nilCursorShowsOnePending() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir)
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        try makeSourceFile("Sources/A/Two.swift", in: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.pendingTasks == 1)
    }

    @Test("cursor at last file shows zero pending tasks")
    func cursorAtLastFileShowsZeroPending() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir)
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        try makeSourceFile("Sources/A/Two.swift", in: repoDir)
        // Cursor at the last file alphabetically
        try writeCursor("Sources/A/Two.swift", to: taskDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.pendingTasks == 0)
    }

    @Test("scope restricts candidate files")
    func scopeFiltersFiles() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(
            in: repoDir,
            scope: "scope:\n  from: Sources/A/"
        )
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        try makeSourceFile("Sources/A/Two.swift", in: repoDir)
        try makeSourceFile("Sources/B/Three.swift", in: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.tasks.count == 2)
        #expect(project.tasks.allSatisfy { $0.description.hasPrefix("Sources/A/") })
    }

    @Test("branchPrefix uses task name")
    func branchPrefixUsesTaskName() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, taskName: "my-sweep")
        try makeSourceFile("Sources/A/One.swift", in: repoDir)

        let source = SweepClaudeChainSource(taskName: "my-sweep", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.branchPrefix == "claude-chain-my-sweep-")
        #expect(project.kind == .sweep)
    }
}

// MARK: - nextTask nil-path tests (no git required)

@Suite("SweepClaudeChainSource.nextTask (no git)")
struct SweepClaudeChainSourceNextTaskNoGitTests {

    @Test("returns nil when no files match filePattern")
    func emptyCandidatesReturnsNil() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        // filePattern matches nothing (no .swift files anywhere)
        let taskDir = try makeTaskDir(in: repoDir, filePattern: "NonExistent/**/*.swift")

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let task = try await source.nextTask()

        #expect(task == nil)
    }

    @Test("returns nil when cursor is at last file")
    func cursorAtLastFileReturnsNil() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir)
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        try makeSourceFile("Sources/A/Two.swift", in: repoDir)
        try writeCursor("Sources/A/Two.swift", to: taskDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let task = try await source.nextTask()

        #expect(task == nil)
    }

    @Test("batchStats: initial values are zero")
    func batchStatsInitialValues() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let stats = await source.batchStats()

        #expect(stats.finalCursor == nil)
        #expect(stats.tasks == 0)
        #expect(stats.skipped == 0)
        #expect(stats.modifyingTasks == 0)
    }
}

// MARK: - nextTask git tests

@Suite("SweepClaudeChainSource.nextTask (with git)")
struct SweepClaudeChainSourceNextTaskGitTests {

    @Test("returns first file when cursor is nil")
    func nilCursorReturnsFirstFile() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, scanLimit: 2, changeLimit: 2)
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        try makeSourceFile("Sources/A/Two.swift", in: repoDir)
        initGitRepo(at: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let task = try await source.nextTask()

        #expect(task != nil)
        #expect(task?.id == "Sources/A/One.swift")
        #expect(task?.instructions.contains("Sources/A/One.swift") == true)
        #expect(task?.instructions.contains("Review this file.") == true)
    }

    @Test("respects scanLimit: returns nil after limit is reached")
    func respectsScanLimit() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, scanLimit: 1, changeLimit: 1)
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        try makeSourceFile("Sources/A/Two.swift", in: repoDir)
        initGitRepo(at: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)

        let task1 = try await source.nextTask()
        let pendingTask = try #require(task1)
        try await source.markComplete(pendingTask)

        let task2 = try await source.nextTask()
        #expect(task2 == nil)

        let stats = await source.batchStats()
        #expect(stats.tasks == 1)
        #expect(stats.finalCursor == "Sources/A/One.swift")
    }

    @Test("skip detection: skips unchanged file after previous batch")
    func skipsUnchangedFilesAfterPreviousBatch() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskName = "test-skip"
        let taskDir = try makeTaskDir(in: repoDir, taskName: taskName, scanLimit: 2, changeLimit: 2)
        try makeSourceFile("Sources/A/One.swift", in: repoDir)
        initGitRepo(at: repoDir)

        // Batch 1: process One.swift; finalizeBatch() writes a cursor commit.
        let source1 = SweepClaudeChainSource(taskName: taskName, taskDirectory: taskDir, repoPath: repoDir)
        let firstTask = try await source1.nextTask()
        let pendingTask = try #require(firstTask)
        try await source1.markComplete(pendingTask)
        let done = try await source1.nextTask()  // triggers finalizeBatch, writes cursor commit
        #expect(done == nil)

        // Reset cursor so batch 2 starts from the beginning of the file list.
        // Overwrite (not delete) so the tracked file remains modified rather than absent.
        try #"{"cursor":null,"lastRunDate":null}"#.write(
            to: taskDir.appendingPathComponent("state.json"),
            atomically: true,
            encoding: .utf8
        )

        // Batch 2: One.swift is in the cursor commit and unchanged → should be skipped.
        let source2 = SweepClaudeChainSource(taskName: taskName, taskDirectory: taskDir, repoPath: repoDir)
        let task = try await source2.nextTask()

        // One.swift should be skipped; no other files → returns nil
        #expect(task == nil)

        let stats = await source2.batchStats()
        #expect(stats.skipped == 1)
        #expect(stats.tasks == 0)
    }
}

// MARK: - loadProject directory-mode tests (no git required)

@Suite("SweepClaudeChainSource.loadProject (directory mode)")
struct SweepClaudeChainSourceDirectoryLoadProjectTests {

    @Test("Sources/*/ expands to immediate subdirectories only")
    func singleStarExpandsImmediateSubdirsOnly() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, filePattern: "Sources/*/")
        try makeSubDir("Sources/A", in: repoDir)
        try makeSubDir("Sources/A/Sub", in: repoDir)
        try makeSubDir("Sources/B", in: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.tasks.count == 2)
        #expect(project.tasks.map(\.description).sorted() == ["Sources/A", "Sources/B"])
    }

    @Test("Sources/**/*/ expands to all nested subdirectories")
    func doubleStarExpandsRecursively() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, filePattern: "Sources/**/*/")
        try makeSubDir("Sources/A", in: repoDir)
        try makeSubDir("Sources/A/Sub", in: repoDir)
        try makeSubDir("Sources/B", in: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.tasks.count == 3)
        #expect(project.tasks.map(\.description).sorted() == ["Sources/A", "Sources/A/Sub", "Sources/B"])
    }

    @Test("SweepScope filters directory paths lexicographically")
    func scopeFiltersDirectoryPaths() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(
            in: repoDir,
            filePattern: "Sources/*/",
            scope: "scope:\n  from: Sources/A\n  to: Sources/C"
        )
        try makeSubDir("Sources/A", in: repoDir)
        try makeSubDir("Sources/B", in: repoDir)
        try makeSubDir("Sources/C", in: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let project = try await source.loadProject()

        #expect(project.tasks.count == 2)
        #expect(project.tasks.map(\.description).sorted() == ["Sources/A", "Sources/B"])
    }
}

// MARK: - nextTask directory-mode tests (with git)

@Suite("SweepClaudeChainSource.nextTask (directory mode)")
struct SweepClaudeChainSourceDirectoryNextTaskTests {

    @Test("returns first directory with Directory label in instructions")
    func returnsFirstDirectoryWithLabel() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, scanLimit: 2, changeLimit: 2, filePattern: "Sources/*/")
        try makeSubDir("Sources/A", in: repoDir)
        initGitRepo(at: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)
        let task = try await source.nextTask()

        #expect(task?.id == "Sources/A")
        #expect(task?.instructions.contains("Directory: Sources/A") == true)
    }

    @Test("cursor advances through directory list")
    func cursorAdvancesThroughDirectories() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, scanLimit: 3, changeLimit: 3, filePattern: "Sources/*/")
        try makeSubDir("Sources/A", in: repoDir)
        try makeSubDir("Sources/B", in: repoDir)
        initGitRepo(at: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)

        let task1 = try await source.nextTask()
        #expect(task1?.id == "Sources/A")
        try await source.markComplete(try #require(task1))

        let task2 = try await source.nextTask()
        #expect(task2?.id == "Sources/B")
        try await source.markComplete(try #require(task2))

        let task3 = try await source.nextTask()
        #expect(task3 == nil)
    }

    @Test("scanLimit limits directories processed")
    func scanLimitLimitsDirectories() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskDir = try makeTaskDir(in: repoDir, scanLimit: 1, changeLimit: 1, filePattern: "Sources/*/")
        try makeSubDir("Sources/A", in: repoDir)
        try makeSubDir("Sources/B", in: repoDir)
        initGitRepo(at: repoDir)

        let source = SweepClaudeChainSource(taskName: "test-task", taskDirectory: taskDir, repoPath: repoDir)

        let task1 = try await source.nextTask()
        try await source.markComplete(try #require(task1))

        let task2 = try await source.nextTask()
        #expect(task2 == nil)

        let stats = await source.batchStats()
        #expect(stats.tasks == 1)
        #expect(stats.finalCursor == "Sources/A")
    }

    @Test("skips unchanged directory after previous batch")
    func skipsUnchangedDirectoryAfterPreviousBatch() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskName = "test-dir-skip"
        let taskDir = try makeTaskDir(in: repoDir, taskName: taskName, scanLimit: 2, changeLimit: 2, filePattern: "Sources/*/")
        try makeSubDir("Sources/A", in: repoDir)
        initGitRepo(at: repoDir)

        let source1 = SweepClaudeChainSource(taskName: taskName, taskDirectory: taskDir, repoPath: repoDir)
        let firstTask = try await source1.nextTask()
        try await source1.markComplete(try #require(firstTask))
        let done = try await source1.nextTask()
        #expect(done == nil)

        try #"{"cursor":null,"lastRunDate":null}"#.write(
            to: taskDir.appendingPathComponent("state.json"),
            atomically: true,
            encoding: .utf8
        )

        let source2 = SweepClaudeChainSource(taskName: taskName, taskDirectory: taskDir, repoPath: repoDir)
        let task = try await source2.nextTask()

        #expect(task == nil)
        let stats = await source2.batchStats()
        #expect(stats.skipped == 1)
        #expect(stats.tasks == 0)
    }

    @Test("processes directory when it contains changes since last batch")
    func processesDirectoryWithChanges() async throws {
        let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: repoDir) }
        let taskName = "test-dir-changed"
        let taskDir = try makeTaskDir(in: repoDir, taskName: taskName, scanLimit: 2, changeLimit: 2, filePattern: "Sources/*/")
        try makeSubDir("Sources/A", in: repoDir)
        initGitRepo(at: repoDir)

        let source1 = SweepClaudeChainSource(taskName: taskName, taskDirectory: taskDir, repoPath: repoDir)
        let firstTask = try await source1.nextTask()
        try await source1.markComplete(try #require(firstTask))
        let done = try await source1.nextTask()
        #expect(done == nil)

        try makeSourceFile("Sources/A/NewFile.swift", in: repoDir)
        gitCommitAll(message: "Add new file", in: repoDir)

        try #"{"cursor":null,"lastRunDate":null}"#.write(
            to: taskDir.appendingPathComponent("state.json"),
            atomically: true,
            encoding: .utf8
        )

        let source2 = SweepClaudeChainSource(taskName: taskName, taskDirectory: taskDir, repoPath: repoDir)
        let task = try await source2.nextTask()

        #expect(task != nil)
        #expect(task?.id == "Sources/A")
    }
}
