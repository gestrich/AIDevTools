import ArgumentParser
import Foundation
import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK

struct PlanRunnerDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a plan file"
    )

    @Option(help: "Path to the plan file")
    var plan: String?

    @Option(help: "Data directory path (default: ~/Desktop/ai-dev-tools)")
    var dataPath: String?

    func run() throws {
        let planURL: URL

        if let plan {
            planURL = URL(fileURLWithPath: (plan as NSString).standardizingPath)
        } else {
            guard let selected = selectPlan() else {
                throw ExitCode.failure
            }
            planURL = selected
        }

        printColored("Deleting: \(planURL.path)", color: .yellow)
        try DeletePlanUseCase().run(planURL: planURL)
        printColored("Deleted.", color: .green)
    }

    private func selectPlan() -> URL? {
        let store = ReposCommand.makeStore(dataPath: dataPath)
        let planSettings = PlanRepoSettingsStore.fromCLI(dataPath: dataPath)
        let repos = (try? store.loadAll()) ?? []

        var allPlans: [(url: URL, repoName: String)] = []
        for repo in repos {
            let proposedDir = planSettings.resolvedProposedDirectory(forRepo: repo)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: proposedDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "md" {
                allPlans.append((url: file, repoName: repo.name))
            }
        }

        guard !allPlans.isEmpty else {
            printColored("No plans found.", color: .red)
            return nil
        }

        let sorted = allPlans.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }

        printColored("Available plans:", color: .blue)
        print()
        for (i, plan) in sorted.enumerated() {
            print("  \(ANSIColor.yellow.rawValue)\(i + 1)\(ANSIColor.reset.rawValue)) \(plan.repoName)/\(plan.url.lastPathComponent)")
        }

        print()
        print("Select a plan to delete [1-\(sorted.count)]: ", terminator: "")

        let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let idx = Int(input), idx >= 1, idx <= sorted.count else {
            printColored("Invalid selection.", color: .red)
            return nil
        }

        return sorted[idx - 1].url
    }
}
