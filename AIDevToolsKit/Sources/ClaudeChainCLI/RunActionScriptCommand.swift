import ArgumentParser
import ClaudeChainService
import ClaudeChainInfrastructure
import Foundation

public struct RunActionScriptCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "run-action-script",
        abstract: "Run pre or post action script for a project"
    )

    @Option(name: .long, help: "Type of action script to run (pre|post)")
    public var type: String

    @Option(name: .long, help: "Path to the project directory")
    public var projectPath: String

    public init() {}

    public func run() throws {
        let workingDirectory = ProcessInfo.processInfo.environment["GITHUB_WORKSPACE"] ?? FileManager.default.currentDirectoryPath
        let exitCode = runActionScript(
            gh: GitHubActions(),
            scriptType: type,
            projectPath: projectPath,
            workingDirectory: workingDirectory
        )
        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }
}

func runActionScript(
    gh: GitHubActions,
    scriptType: String,
    projectPath: String,
    workingDirectory: String
) -> Int {
    print("=== Running \(scriptType)-action script ===")
    print("Project path: \(projectPath)")
    print("Working directory: \(workingDirectory)")

    do {
        let result = try ScriptRunner.runActionScript(
            projectPath: projectPath,
            scriptType: scriptType,
            workingDirectory: workingDirectory
        )

        if !result.scriptExists {
            print("No \(scriptType)-action.sh script found, continuing")
            return 0
        }

        print("✅ \(scriptType)-action.sh completed successfully")
        return 0

    } catch let error as ActionScriptError {
        gh.setError(message: "\(scriptType)-action script failed: \(error.message)")
        if !error.stdout.isEmpty {
            print("stdout: \(error.stdout)")
        }
        if !error.stderr.isEmpty {
            print("stderr: \(error.stderr)")
        }
        return error.exitCode
    } catch {
        gh.setError(message: "Unexpected error running \(scriptType)-action script: \(error)")
        return 1
    }
}
