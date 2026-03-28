import ArgumentParser
import Foundation
import ClaudeChainInfrastructure

public struct AutoStartSummaryCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "auto-start-summary",
        abstract: "Generate summary for auto-start workflow"
    )
    
    @Option(help: "Space-separated list of successfully triggered projects")
    var triggeredProjects: String = ""
    
    @Option(help: "Space-separated list of projects that failed to trigger")
    var failedProjects: String = ""
    
    public init() {}
    
    public func run() throws {
        let gh = GitHubActions()
        let exitCode = autoStartSummary(
            gh: gh,
            triggeredProjects: triggeredProjects,
            failedProjects: failedProjects
        )
        
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }
}

private func autoStartSummary(
    gh: GitHubActions,
    triggeredProjects: String,
    failedProjects: String
) -> Int32 {
    do {
        // Parse project lists
        let triggeredList = triggeredProjects.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let failedList = failedProjects.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        
        // Write step summary header
        gh.writeStepSummary(text: "# ClaudeChain Auto-Start Summary")
        gh.writeStepSummary(text: "")
        
        // Determine overall status
        if !triggeredList.isEmpty && failedList.isEmpty {
            // All succeeded
            gh.writeStepSummary(text: "✅ **Status**: All workflows triggered successfully")
            gh.writeStepSummary(text: "")
            gh.writeStepSummary(text: "**Triggered Projects** (\(triggeredList.count)):")
            gh.writeStepSummary(text: "")
            for project in triggeredList {
                gh.writeStepSummary(text: "- `\(project)` - Workflow started")
            }
            gh.writeStepSummary(text: "")
            
        } else if !triggeredList.isEmpty && !failedList.isEmpty {
            // Partial success
            gh.writeStepSummary(text: "⚠️ **Status**: Partial success - some workflows failed to trigger")
            gh.writeStepSummary(text: "")
            gh.writeStepSummary(text: "**Successfully Triggered** (\(triggeredList.count)):")
            gh.writeStepSummary(text: "")
            for project in triggeredList {
                gh.writeStepSummary(text: "- `\(project)` ✓")
            }
            gh.writeStepSummary(text: "")
            gh.writeStepSummary(text: "**Failed to Trigger** (\(failedList.count)):")
            gh.writeStepSummary(text: "")
            for project in failedList {
                gh.writeStepSummary(text: "- `\(project)` ✗")
            }
            gh.writeStepSummary(text: "")
            
        } else if !failedList.isEmpty && triggeredList.isEmpty {
            // All failed
            gh.writeStepSummary(text: "❌ **Status**: All workflow triggers failed")
            gh.writeStepSummary(text: "")
            gh.writeStepSummary(text: "**Failed Projects** (\(failedList.count)):")
            gh.writeStepSummary(text: "")
            for project in failedList {
                gh.writeStepSummary(text: "- `\(project)` ✗")
            }
            gh.writeStepSummary(text: "")
            
        } else {
            // No projects detected
            gh.writeStepSummary(text: "ℹ️ **Status**: No new projects detected")
            gh.writeStepSummary(text: "")
            gh.writeStepSummary(text: "No spec.md changes found that require auto-start.")
            gh.writeStepSummary(text: "")
        }
        
        // Add helpful information
        gh.writeStepSummary(text: "---")
        gh.writeStepSummary(text: "")
        gh.writeStepSummary(text: "**What happens next?**")
        gh.writeStepSummary(text: "")
        if !triggeredList.isEmpty {
            gh.writeStepSummary(text: "- Triggered workflows will process the first task from each project's spec.md")
            gh.writeStepSummary(text: "- Pull requests will be created automatically for each task")
            gh.writeStepSummary(text: "- Check the Actions tab to monitor workflow progress")
        } else {
            gh.writeStepSummary(text: "- Auto-start only triggers for new projects (projects with no existing PRs)")
            gh.writeStepSummary(text: "- Existing projects must be triggered manually or via scheduled workflows")
        }
        gh.writeStepSummary(text: "")
        
        print("✅ Auto-start summary generated successfully")
        return 0
        
    } catch {
        gh.setError(message: "Auto-start summary generation failed: \(error)")
        gh.writeStepSummary(text: "# ClaudeChain Auto-Start Summary")
        gh.writeStepSummary(text: "")
        gh.writeStepSummary(text: "❌ **Error**: \(error)")
        return 1
    }
}