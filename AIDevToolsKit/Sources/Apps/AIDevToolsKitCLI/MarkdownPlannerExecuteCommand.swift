import ArgumentParser
import DataPathsService
import Foundation
import MarkdownPlannerFeature
import MarkdownPlannerService
import PipelineSDK
import ProviderRegistryService
import RepositorySDK
import SettingsService

struct MarkdownPlannerExecuteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "execute",
        abstract: "Execute phases from a planning document"
    )

    @Option(help: "Path to planning document")
    var plan: String?

    @Option(help: "Maximum runtime in minutes")
    var maxMinutes: Int = 90

    @Flag(help: "Execute only the next incomplete phase")
    var next = false

    @Option(help: "Provider to use (default: first registered)")
    var provider: String?

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() async throws {
        let planURL: URL

        if let plan {
            planURL = URL(fileURLWithPath: (plan as NSString).standardizingPath)
        } else {
            guard let selected = selectPlanningDoc() else {
                throw ExitCode.failure
            }
            planURL = selected
        }

        let repoPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let repos = try settings.repositoryStore.loadAll()

        printColored(String(repeating: "=", count: 50), color: .blue)
        printColored("Phased Implementation Automation", color: .blue)
        printColored(String(repeating: "=", count: 50), color: .blue)
        print("Planning document: \(ANSIColor.green.rawValue)\(planURL.path)\(ANSIColor.reset.rawValue)")
        print("Max runtime: \(ANSIColor.green.rawValue)\(TimerDisplay.formatTime(maxMinutes * 60))\(ANSIColor.reset.rawValue)")
        printColored(String(repeating: "=", count: 50), color: .blue)
        print()

        let planPath = planURL.path(percentEncoded: false)
        let repository = repos.first { planPath.hasPrefix($0.path.path(percentEncoded: false)) }

        let registry = makeProviderRegistry()
        let client = provider.flatMap { registry.client(named: $0) } ?? registry.defaultClient!

        let service = MarkdownPlannerService(
            client: client,
            resolveProposedDirectory: { repo in
                (repo.planner ?? MarkdownPlannerRepoSettings()).resolvedProposedDirectory(repoPath: repo.path)
            }
        )

        printColored("Fetching phase information...", color: .cyan)
        let blueprint = try await service.buildExecutePipeline(
            options: MarkdownPlannerService.ExecuteOptions(
                executeMode: next ? .next : .all,
                planPath: planURL,
                repoPath: repoPath,
                maxMinutes: maxMinutes,
                repository: repository
            )
        )
        let totalPhases = blueprint.initialNodeManifest.count

        print()
        printColored(String(repeating: "=", count: 50), color: .blue)
        printColored("Implementation Steps", color: .blue)
        printColored(String(repeating: "=", count: 50), color: .blue)
        print("Total steps: \(ANSIColor.green.rawValue)\(totalPhases)\(ANSIColor.reset.rawValue)\n")
        for (i, node) in blueprint.initialNodeManifest.enumerated() {
            print("  \(ANSIColor.yellow.rawValue)\(i + 1): \(node.displayName)\(ANSIColor.reset.rawValue)")
        }
        printColored(String(repeating: "=", count: 50), color: .blue)
        print()

        let timer = TimerDisplay(maxRuntimeSeconds: maxMinutes * 60, scriptStartTime: Date())
        let state = PipelineCLIState(totalPhases: totalPhases)

        _ = try await PipelineRunner().run(
            nodes: blueprint.nodes,
            configuration: blueprint.configuration,
            onProgress: { [timer, state] event in
                Self.handlePipelineEvent(event, timer: timer, state: state)
            }
        )

        timer.stop()

        printColored(String(repeating: "=", count: 50), color: .blue)
        printColored("\u{2713} All steps completed successfully!", color: .green)
        printColored(String(repeating: "=", count: 50), color: .blue)
        printColored("Total steps executed: \(state.phasesExecuted)", color: .green)
        printColored("Total time: \(TimerDisplay.formatTime(state.totalElapsed))", color: .cyan)
        printColored("Planning document: \(planURL.path)", color: .green)
        print()

        playCompletionSound()
    }

    static func handlePipelineEvent(_ event: PipelineEvent, timer: TimerDisplay, state: PipelineCLIState) {
        switch event {
        case .nodeStarted(let id, let displayName):
            state.nodeStarted(id: id)
            let phaseNum = (Int(id) ?? 0) + 1
            printColored(String(repeating: "=", count: 50), color: .blue)
            printColored("Step \(phaseNum) of \(state.totalPhases) -> \(displayName)", color: .yellow)
            printColored(String(repeating: "-", count: 50), color: .blue)
            printColored("Running AI...\n", color: .blue)
            timer.start()

        case .nodeProgress(_, let progress):
            if case .output(let text) = progress {
                timer.setStatusLine(text)
            }

        case .nodeCompleted(let id, _):
            timer.stop()
            let phaseNum = (Int(id) ?? 0) + 1
            let elapsed = state.elapsed(for: id)
            let totalElapsed = state.totalElapsed
            state.nodeCompleted()
            printColored("\nStep \(phaseNum) completed", color: .green)
            printColored("\u{23F1}  Step time: \(TimerDisplay.formatTime(elapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
            printColored(String(repeating: "-", count: 50), color: .blue)
            print()

        case .completed, .pausedForReview:
            break
        }
    }

    private func selectPlanningDoc(proposedDir: String = MarkdownPlannerRepoSettings.defaultProposedDirectory) -> URL? {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(proposedDir)

        guard fm.fileExists(atPath: dir.path) else {
            printColored("Error: Directory not found: \(proposedDir)", color: .red)
            return nil
        }

        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "md" }
                .sorted { a, b in
                    let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return aDate > bDate
                }
        } catch {
            printColored("Error reading \(proposedDir): \(error.localizedDescription)", color: .red)
            return nil
        }

        let sorted = Array(files.prefix(5))

        guard !sorted.isEmpty else {
            printColored("No .md files found in \(proposedDir)", color: .red)
            return nil
        }

        printColored("No planning document specified.", color: .blue)
        print("Last \(ANSIColor.green.rawValue)\(sorted.count)\(ANSIColor.reset.rawValue) modified files in \(ANSIColor.green.rawValue)\(proposedDir)\(ANSIColor.reset.rawValue):\n")

        for (i, file) in sorted.enumerated() {
            print("  \(ANSIColor.yellow.rawValue)\(i + 1)\(ANSIColor.reset.rawValue)) \(file.lastPathComponent)")
        }

        print()
        Swift.print("Select a file to implement [1-\(sorted.count)] (default: 1): ", terminator: "")

        let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
        let selection = input.isEmpty ? "1" : input

        guard let idx = Int(selection), idx >= 1, idx <= sorted.count else {
            printColored("Invalid selection.", color: .red)
            return nil
        }

        return sorted[idx - 1]
    }

    private func playCompletionSound() {
        for _ in 0..<2 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = ["/System/Library/Sounds/Glass.aiff"]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

// MARK: - PipelineCLIState

final class PipelineCLIState: @unchecked Sendable {
    let scriptStart: Date
    let totalPhases: Int
    private(set) var phasesExecuted: Int = 0
    private var startTimes: [String: Date] = [:]
    private let lock = NSLock()

    init(totalPhases: Int) {
        self.scriptStart = Date()
        self.totalPhases = totalPhases
    }

    func nodeStarted(id: String) {
        lock.withLock { startTimes[id] = Date() }
    }

    func nodeCompleted() {
        lock.withLock { phasesExecuted += 1 }
    }

    func elapsed(for id: String) -> Int {
        lock.withLock { startTimes[id].map { Int(Date().timeIntervalSince($0)) } ?? 0 }
    }

    var totalElapsed: Int {
        Int(Date().timeIntervalSince(scriptStart))
    }
}
