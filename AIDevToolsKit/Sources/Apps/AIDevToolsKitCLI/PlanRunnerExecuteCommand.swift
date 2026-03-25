import ArgumentParser
import DataPathsService
import Foundation
import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK

struct PlanRunnerExecuteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "execute",
        abstract: "Execute phases from a planning document"
    )

    @Option(help: "Path to planning document")
    var plan: String?

    @Option(help: "Maximum runtime in minutes")
    var maxMinutes: Int = 90

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

        let service = try DataPathsService.fromCLI(dataPath: dataPath)
        let store = try ReposCommand.makeStore(service)
        let planSettings = try ReposCommand.makePlanSettingsStore(service)

        let repos = try store.loadAll()

        let timer = TimerDisplay(maxRuntimeSeconds: maxMinutes * 60, scriptStartTime: Date())

        printColored(String(repeating: "=", count: 50), color: .blue)
        printColored("Phased Implementation Automation", color: .blue)
        printColored(String(repeating: "=", count: 50), color: .blue)
        print("Planning document: \(ANSIColor.green.rawValue)\(planURL.path)\(ANSIColor.reset.rawValue)")
        print("Max runtime: \(ANSIColor.green.rawValue)\(TimerDisplay.formatTime(maxMinutes * 60))\(ANSIColor.reset.rawValue)")
        printColored(String(repeating: "=", count: 50), color: .blue)
        print()

        let planPath = planURL.path(percentEncoded: false)
        let repository = repos.first { planPath.hasPrefix($0.path.path(percentEncoded: false)) }
        let completedDirectory = try repository.map { try planSettings.resolvedCompletedDirectory(forRepo: $0) }

        let resolvedDataPath = ResolveDataPathUseCase().resolve(explicit: dataPath).path
        let useCase = ExecutePlanUseCase(
            completedDirectory: completedDirectory,
            dataPath: resolvedDataPath
        )
        let result = try await useCase.run(
            ExecutePlanUseCase.Options(
                planPath: planURL,
                repoPath: repoPath,
                maxMinutes: maxMinutes,
                repository: repository
            )
        ) { progress in
            Self.handleProgress(progress, timer: timer)
        }

        timer.stop()

        printColored(String(repeating: "=", count: 50), color: .blue)
        if result.allCompleted {
            printColored("\u{2713} All steps completed successfully!", color: .green)
        }
        printColored(String(repeating: "=", count: 50), color: .blue)
        printColored("Total steps executed: \(result.phasesExecuted)", color: .green)
        printColored("Total time: \(TimerDisplay.formatTime(result.totalSeconds))", color: .cyan)
        printColored("Planning document: \(planURL.path)", color: .green)
        print()

        if result.allCompleted {
            playCompletionSound()
        }
    }

    private static func handleProgress(_ progress: ExecutePlanUseCase.Progress, timer: TimerDisplay) {
        switch progress {
        case .fetchingStatus:
            printColored("Fetching phase information...", color: .cyan)

        case .phaseOverview(let phases):
            print()
            printColored(String(repeating: "=", count: 50), color: .blue)
            printColored("Implementation Steps", color: .blue)
            printColored(String(repeating: "=", count: 50), color: .blue)
            print("Total steps: \(ANSIColor.green.rawValue)\(phases.count)\(ANSIColor.reset.rawValue)\n")
            for (i, phase) in phases.enumerated() {
                let color: ANSIColor = phase.isCompleted ? .green : .yellow
                print("  \(color.rawValue)\(i + 1): \(phase.description)\(ANSIColor.reset.rawValue)")
            }
            printColored(String(repeating: "=", count: 50), color: .blue)
            print()

        case .startingPhase(let index, let total, let description):
            printColored(String(repeating: "=", count: 50), color: .blue)
            printColored("Step \(index + 1) of \(total) -> \(description)", color: .yellow)
            printColored(String(repeating: "-", count: 50), color: .blue)
            printColored("Running claude...\n", color: .blue)
            timer.start()

        case .phaseOutput(let text):
            timer.setStatusLine(text)

        case .phaseCompleted(let index, let elapsed, let totalElapsed):
            timer.stop()
            printColored("\nStep \(index + 1) completed", color: .green)
            printColored("\u{23F1}  Step time: \(TimerDisplay.formatTime(elapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
            printColored(String(repeating: "-", count: 50), color: .blue)
            print()

        case .phaseFailed(let index, let description, let error):
            timer.stop()
            printColored("\nStep \(index + 1) failed: \(description)", color: .red)
            printColored("Error: \(error)", color: .red)

        case .allCompleted(let phasesExecuted, let totalSeconds):
            printColored("\u{2713} All \(phasesExecuted) steps completed in \(TimerDisplay.formatTime(totalSeconds))", color: .green)

        case .timeLimitReached(let remaining, let totalSeconds):
            printColored("Time limit reached — \(remaining) steps may remain (total: \(TimerDisplay.formatTime(totalSeconds)))", color: .yellow)
        }
    }

    private func selectPlanningDoc(proposedDir: String = PlanRepoSettings.defaultProposedDirectory) -> URL? {
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
