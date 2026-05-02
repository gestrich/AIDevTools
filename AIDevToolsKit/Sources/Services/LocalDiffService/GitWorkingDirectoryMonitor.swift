import Foundation
import GitSDK

#if canImport(CoreServices)
import CoreServices
#endif

#if canImport(Darwin)
import Darwin
#endif

public final class GitWorkingDirectoryMonitor: Sendable {
    private let debounceIntervalNanoseconds: UInt64
    private let gitClient: GitClient
    private let pollIntervalNanoseconds: UInt64
    private let _cancelSource = CancelSource()

    public init(
        gitClient: GitClient = GitClient(),
        debounceIntervalNanoseconds: UInt64 = 300_000_000,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.gitClient = gitClient
        self.debounceIntervalNanoseconds = debounceIntervalNanoseconds
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    /// Cancels the monitor, stopping all FSEventStreams, DispatchSources, and
    /// polling tasks. Safe to call from any thread.
    public func cancel() {
        _cancelSource.cancel()
    }

    public func changes(repoPath: String) -> AsyncStream<Set<GitWorkingDirectoryChange>> {
        let cancelSource = self._cancelSource
        return AsyncStream { continuation in
            let emitter = ChangeEmitter(
                continuation: continuation,
                debounceIntervalNanoseconds: debounceIntervalNanoseconds
            )
            let monitorState = MonitorState(
                emitter: emitter,
                pollIntervalNanoseconds: pollIntervalNanoseconds
            )

            let setupTask = Task {
                do {
                    let repoRoot = try await gitClient.getRepoRoot(workingDirectory: repoPath)
                    let gitDirectory = try await gitClient.getGitDirectory(workingDirectory: repoPath)
                    guard !Task.isCancelled else { return }
                    monitorState.start(repoRoot: repoRoot, gitDirectory: gitDirectory)
                } catch {
                    await emitter.finish()
                }
            }

            let cleanup = {
                setupTask.cancel()
                monitorState.stop()
                Task {
                    await emitter.finish()
                }
            }

            continuation.onTermination = { _ in
                cleanup()
            }

            // Register external cancel so cancel() works from any thread (GCD),
            // bypassing cooperative thread-pool saturation.
            cancelSource.onCancel(handler: cleanup)
        }
    }
}

/// Thread-safe cancellation token.
private final class CancelSource: @unchecked Sendable {
    private var handler: (() -> Void)?
    private var isCancelled = false
    private let lock = NSLock()

    func onCancel(handler: @escaping () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            handler()
        } else {
            self.handler = handler
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else { lock.unlock(); return }
        isCancelled = true
        let h = handler
        handler = nil
        lock.unlock()
        h?()
    }
}

private actor ChangeEmitter {
    private let continuation: AsyncStream<Set<GitWorkingDirectoryChange>>.Continuation
    private let debounceIntervalNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?
    private var pendingChanges: Set<GitWorkingDirectoryChange> = []

    init(
        continuation: AsyncStream<Set<GitWorkingDirectoryChange>>.Continuation,
        debounceIntervalNanoseconds: UInt64
    ) {
        self.continuation = continuation
        self.debounceIntervalNanoseconds = debounceIntervalNanoseconds
    }

    func enqueue(_ change: GitWorkingDirectoryChange) {
        pendingChanges.insert(change)
        debounceTask?.cancel()
        let debounceIntervalNanoseconds = self.debounceIntervalNanoseconds
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    func finish() {
        debounceTask?.cancel()
        debounceTask = nil
        continuation.finish()
    }

    private func flush() {
        guard !pendingChanges.isEmpty else { return }
        let changes = pendingChanges
        pendingChanges.removeAll()
        continuation.yield(changes)
    }
}

private final class MonitorState {
    private let emitter: ChangeEmitter
    private let pollIntervalNanoseconds: UInt64

#if canImport(CoreServices)
    private var historyEventStream: FSEventStreamRef?
#endif
    private var historyPollTask: Task<Void, Never>?
#if canImport(Darwin)
    private var indexMonitor: DispatchSourceFileSystemObject?
#endif
    private var indexPollTask: Task<Void, Never>?
#if canImport(CoreServices)
    private var workingTreeEventStream: FSEventStreamRef?
#endif
    private var workingTreePollTask: Task<Void, Never>?
    private var historyCallbackContext: GitHistoryCallbackContext?
    private var workingTreeCallbackContext: WorkingTreeCallbackContext?

    init(emitter: ChangeEmitter, pollIntervalNanoseconds: UInt64) {
        self.emitter = emitter
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    func start(repoRoot: String, gitDirectory: String) {
        let standardizedRepoRoot = URL(fileURLWithPath: repoRoot).standardizedFileURL.path
        let standardizedGitDirectory = URL(fileURLWithPath: gitDirectory).standardizedFileURL.path
        let repoMetadataPath = URL(fileURLWithPath: standardizedRepoRoot).appendingPathComponent(".git").standardizedFileURL.path
        let indexPath = URL(fileURLWithPath: standardizedGitDirectory).appendingPathComponent("index").standardizedFileURL.path

        if !startHistoryEventStream(gitDirectory: standardizedGitDirectory) {
            startHistoryPolling(gitDirectory: standardizedGitDirectory)
        }
        startIndexMonitor(indexPath: indexPath)
        if !startWorkingTreeEventStream(
            repoRoot: standardizedRepoRoot,
            gitDirectory: standardizedGitDirectory,
            repoMetadataPath: repoMetadataPath
        ) {
            startWorkingTreePolling(
                repoRoot: standardizedRepoRoot,
                gitDirectory: standardizedGitDirectory,
                repoMetadataPath: repoMetadataPath
            )
        }
    }

    deinit {
        stop()
    }

    func stop() {
        historyPollTask?.cancel()
        historyPollTask = nil

#if canImport(CoreServices)
        if let stream = historyEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            historyEventStream = nil
        }
#endif
        historyCallbackContext = nil

#if canImport(Darwin)
        indexMonitor?.cancel()
        indexMonitor = nil
#endif

        indexPollTask?.cancel()
        indexPollTask = nil

        workingTreePollTask?.cancel()
        workingTreePollTask = nil

#if canImport(CoreServices)
        if let stream = workingTreeEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            workingTreeEventStream = nil
        }
#endif
        workingTreeCallbackContext = nil
    }

    private func startIndexMonitor(indexPath: String) {
#if canImport(Darwin)
        let fileDescriptor = open(indexPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            startIndexPolling(indexPath: indexPath)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.attrib, .delete, .extend, .rename, .write],
            queue: DispatchQueue(label: "GitWorkingDirectoryMonitor.index")
        )

        source.setEventHandler { [emitter] in
            Task {
                await emitter.enqueue(.index)
            }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        indexMonitor = source
        source.resume()
#else
        startIndexPolling(indexPath: indexPath)
#endif
    }

    private func startIndexPolling(indexPath: String) {
        indexPollTask?.cancel()
        indexPollTask = Task {
            var previousSnapshot = fileSnapshot(at: indexPath)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                let currentSnapshot = fileSnapshot(at: indexPath)
                if currentSnapshot != previousSnapshot {
                    previousSnapshot = currentSnapshot
                    await emitter.enqueue(.index)
                }
            }
        }
    }

    private func startHistoryPolling(gitDirectory: String) {
        historyPollTask?.cancel()
        historyPollTask = Task {
            var previousSnapshot = gitHistorySnapshot(gitDirectory: gitDirectory)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                let currentSnapshot = gitHistorySnapshot(gitDirectory: gitDirectory)
                if currentSnapshot != previousSnapshot {
                    previousSnapshot = currentSnapshot
                    await emitter.enqueue(.history)
                }
            }
        }
    }

    private func startHistoryEventStream(gitDirectory: String) -> Bool {
#if canImport(CoreServices)
        let callbackContext = GitHistoryCallbackContext(
            emitter: emitter,
            gitDirectory: gitDirectory
        )
        historyCallbackContext = callbackContext

        let pathsToWatch = [gitDirectory as CFString] as CFArray
        var streamContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(callbackContext).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<GitHistoryCallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, eventCount, eventPaths, eventFlags, _ in
                guard let info else { return }
                let context = Unmanaged<GitHistoryCallbackContext>.fromOpaque(info).takeUnretainedValue()
                let pathsPointer = eventPaths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>?.self)

                for index in 0..<eventCount {
                    let flag = eventFlags[index]
                    guard shouldEmitHistoryChange(flag: flag) else { continue }
                    guard let cString = pathsPointer[index] else { continue }
                    let path = URL(fileURLWithPath: String(cString: cString)).standardizedFileURL.path
                    guard context.shouldEmit(path: path) else { continue }

                    Task {
                        await context.emitter.enqueue(.history)
                    }
                    return
                }
            },
            &streamContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        ) else {
            historyCallbackContext = nil
            return false
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "GitWorkingDirectoryMonitor.history"))

        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            historyCallbackContext = nil
            return false
        }

        historyEventStream = stream
        return true
#else
        _ = gitDirectory
        return false
#endif
    }

    private func startWorkingTreePolling(repoRoot: String, gitDirectory: String, repoMetadataPath: String) {
        workingTreePollTask?.cancel()
        workingTreePollTask = Task {
            var previousSnapshot = directorySnapshot(
                rootPath: repoRoot,
                excludedPaths: [gitDirectory, repoMetadataPath]
            )

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                let currentSnapshot = directorySnapshot(
                    rootPath: repoRoot,
                    excludedPaths: [gitDirectory, repoMetadataPath]
                )
                if currentSnapshot != previousSnapshot {
                    previousSnapshot = currentSnapshot
                    await emitter.enqueue(.workingTree)
                }
            }
        }
    }

    private func directorySnapshot(rootPath: String, excludedPaths: [String]) -> DirectorySnapshot {
        let excluded = Set(excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey]
        let rootURL = URL(fileURLWithPath: rootPath)

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return DirectorySnapshot(fileCount: 0, latestModification: .distantPast)
        }

        var fileCount = 0
        var latestModification = Date.distantPast

        for case let fileURL as URL in enumerator {
            let standardizedPath = fileURL.standardizedFileURL.path
            if excluded.contains(where: { standardizedPath == $0 || standardizedPath.hasPrefix("\($0)/") }) {
                enumerator.skipDescendants()
                continue
            }

            fileCount += 1
            if
                let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                let modificationDate = resourceValues.contentModificationDate,
                modificationDate > latestModification
            {
                latestModification = modificationDate
            }
        }

        return DirectorySnapshot(fileCount: fileCount, latestModification: latestModification)
    }

    private func gitHistorySnapshot(gitDirectory: String) -> GitHistorySnapshot {
        let headPath = URL(fileURLWithPath: gitDirectory).appendingPathComponent("HEAD").standardizedFileURL.path
        let resolvedReferencePath = resolvedHeadReferencePath(gitDirectory: gitDirectory, headPath: headPath)

        return GitHistorySnapshot(
            head: fileSnapshot(at: headPath),
            resolvedReferencePath: resolvedReferencePath,
            resolvedReference: resolvedReferencePath.map(fileSnapshot(at:)) ?? .missing
        )
    }

    private func fileSnapshot(at path: String) -> FileSnapshot {
        let fileURL = URL(fileURLWithPath: path)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
            return FileSnapshot(exists: false, modificationDate: .distantPast, size: 0)
        }
        return FileSnapshot(
            exists: true,
            modificationDate: resourceValues.contentModificationDate ?? .distantPast,
            size: resourceValues.fileSize ?? 0
        )
    }

    private func resolvedHeadReferencePath(gitDirectory: String, headPath: String) -> String? {
        guard
            let headContents = try? String(contentsOfFile: headPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            headContents.hasPrefix("ref: ")
        else {
            return nil
        }

        let reference = String(headContents.dropFirst("ref: ".count))
        guard !reference.isEmpty else { return nil }

        return URL(fileURLWithPath: gitDirectory)
            .appendingPathComponent(reference)
            .standardizedFileURL
            .path
    }

    private func startWorkingTreeEventStream(repoRoot: String, gitDirectory: String, repoMetadataPath: String) -> Bool {
#if canImport(CoreServices)
        let callbackContext = WorkingTreeCallbackContext(
            emitter: emitter,
            excludedPaths: [gitDirectory, repoMetadataPath]
        )
        workingTreeCallbackContext = callbackContext

        let pathsToWatch = [repoRoot as CFString] as CFArray
        var streamContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(callbackContext).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<WorkingTreeCallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, eventCount, eventPaths, eventFlags, _ in
                guard let info else { return }
                let context = Unmanaged<WorkingTreeCallbackContext>.fromOpaque(info).takeUnretainedValue()
                let pathsPointer = eventPaths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>?.self)

                for index in 0..<eventCount {
                    let flag = eventFlags[index]
                    guard shouldEmitWorkingTreeChange(flag: flag) else { continue }
                    guard let cString = pathsPointer[index] else { continue }
                    let path = URL(fileURLWithPath: String(cString: cString)).standardizedFileURL.path
                    if context.shouldIgnore(path: path) {
                        continue
                    }

                    Task {
                        await context.emitter.enqueue(.workingTree)
                    }
                    return
                }
            },
            &streamContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        ) else {
            workingTreeCallbackContext = nil
            return false
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "GitWorkingDirectoryMonitor.workingTree"))

        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            workingTreeCallbackContext = nil
            return false
        }

        workingTreeEventStream = stream
        return true
#else
        _ = repoRoot
        _ = gitDirectory
        _ = repoMetadataPath
        return false
#endif
    }
}

private struct DirectorySnapshot: Equatable {
    let fileCount: Int
    let latestModification: Date
}

private struct FileSnapshot: Equatable {
    static let missing = FileSnapshot(exists: false, modificationDate: .distantPast, size: 0)

    let exists: Bool
    let modificationDate: Date
    let size: Int
}

private struct GitHistorySnapshot: Equatable {
    let head: FileSnapshot
    let resolvedReferencePath: String?
    let resolvedReference: FileSnapshot
}

private final class GitHistoryCallbackContext {
    let emitter: ChangeEmitter
    private let gitDirectory: String
    private let packedRefsPath: String
    private let refsPathPrefix: String

    init(emitter: ChangeEmitter, gitDirectory: String) {
        self.emitter = emitter
        self.gitDirectory = URL(fileURLWithPath: gitDirectory).standardizedFileURL.path
        self.packedRefsPath = URL(fileURLWithPath: gitDirectory)
            .appendingPathComponent("packed-refs")
            .standardizedFileURL
            .path
        self.refsPathPrefix = URL(fileURLWithPath: gitDirectory)
            .appendingPathComponent("refs")
            .standardizedFileURL
            .path + "/"
    }

    func shouldEmit(path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardizedPath == "\(gitDirectory)/HEAD" { return true }
        if standardizedPath == packedRefsPath { return true }
        if standardizedPath.hasPrefix(refsPathPrefix) { return true }
        return false
    }
}

private final class WorkingTreeCallbackContext {
    let emitter: ChangeEmitter
    private let excludedPaths: Set<String>

    init(emitter: ChangeEmitter, excludedPaths: [String]) {
        self.emitter = emitter
        self.excludedPaths = Set(excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    func shouldIgnore(path: String) -> Bool {
        excludedPaths.contains(where: { path == $0 || path.hasPrefix("\($0)/") })
    }
}

#if canImport(CoreServices)
private func shouldEmitWorkingTreeChange(flag: FSEventStreamEventFlags) -> Bool {
    if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return true }
    if flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 { return true }
    if flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { return true }
    if flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { return true }
    return false
}

private func shouldEmitHistoryChange(flag: FSEventStreamEventFlags) -> Bool {
    shouldEmitWorkingTreeChange(flag: flag)
}
#endif
