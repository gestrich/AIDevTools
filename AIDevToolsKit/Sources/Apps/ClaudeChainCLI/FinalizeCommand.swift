import ArgumentParser
import ClaudeChainService
import ClaudeChainSDK
import ClaudeChainFeature
import Foundation

public struct FinalizeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "finalize",
        abstract: "Finalize after Claude Code execution (commit, PR, summary)"
    )
    
    public init() {}
    
    public func run() throws {
        /**
         * Orchestrate finalization workflow using Service Layer classes.
         *
         * This command instantiates services and coordinates their operations but
         * does not implement business logic directly. Follows Service Layer pattern
         * where CLI acts as thin orchestration layer.
         *
         * Workflow: commit changes, create-pr, summary
         *
         * Returns:
         *     Exit code (0 for success, 1 for failure)
         */
        do {
            // === Get common dependencies ===
            let environment = ProcessInfo.processInfo.environment
            let githubRepository = environment["GITHUB_REPOSITORY"] ?? ""
            
            // Get environment variables
            let branchName = environment["BRANCH_NAME"] ?? ""
            let task = environment["TASK_DESCRIPTION"] ?? ""
            let taskIndex = environment["TASK_INDEX"] ?? ""
            let assignees = (environment["ASSIGNEES"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let reviewers = (environment["REVIEWERS"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let project = environment["PROJECT"] ?? ""
            let specPath = environment["SPEC_PATH"] ?? ""
            let prTemplatePath = environment["PR_TEMPLATE_PATH"] ?? ""
            let ghToken = environment["GH_TOKEN"] ?? ""
            let githubRunId = environment["GITHUB_RUN_ID"] ?? ""
            let baseBranch = environment["BASE_BRANCH"] ?? "main"
            let hasCapacity = environment["HAS_CAPACITY"] ?? ""
            let hasTask = environment["HAS_TASK"] ?? ""
            let label = environment["LABEL"] ?? ""
            let prLabelsStr = environment["PR_LABELS"] ?? ""
            
            // Initialize GitHub Actions helper
            let gh = GitHubActions()
            
            // === Generate Summary Early (for all cases) ===
            print("\n=== Generating workflow summary ===")
            
            gh.writeStepSummary(text: "## ClaudeChain Summary")
            gh.writeStepSummary(text: "")
            
            // Check if we should skip (no capacity or no task)
            if hasCapacity != "true" {
                gh.writeStepSummary(text: "⏸️ **Status**: Project at capacity (1 open PR limit)")
                print("⏸️ Project at capacity - skipping")
                return
            }
            
            if hasTask != "true" {
                gh.writeStepSummary(text: "✅ **Status**: All tasks complete or in progress")
                print("✅ All tasks complete or in progress - skipping")
                return
            }
            
            // Validate required environment variables (reviewer is optional)
            if branchName.isEmpty || task.isEmpty || taskIndex.isEmpty || project.isEmpty || specPath.isEmpty || ghToken.isEmpty || githubRepository.isEmpty {
                throw ConfigurationError("Missing required environment variables")
            }
            
            // === STEP 1: Commit Any Uncommitted Changes ===
            print("=== Step 1/3: Committing changes ===")
            
            // Exclude .action directory from git tracking (checked out action code, not part of user's repo)
            // We can't remove it because GitHub Actions needs it for post-action cleanup
            // Instead, add it to .git/info/exclude so git ignores it
            let currentDir = FileManager.default.currentDirectoryPath
            let actionDir = URL(fileURLWithPath: currentDir).appendingPathComponent(".action")
            if FileManager.default.fileExists(atPath: actionDir.path) {
                let excludeFile = URL(fileURLWithPath: currentDir).appendingPathComponent(".git/info/exclude")
                do {
                    let excludeContent = try String(contentsOfFile: excludeFile.path)
                    if !excludeContent.contains(".action") {
                        let fileHandle = FileHandle(forWritingAtPath: excludeFile.path)
                        fileHandle?.seekToEndOfFile()
                        fileHandle?.write("\n.action\n".data(using: .utf8) ?? Data())
                        fileHandle?.closeFile()
                        print("Added .action to git exclude list")
                    }
                } catch {
                    // .git/info/exclude doesn't exist, create it
                    try FileManager.default.createDirectory(at: excludeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try ".action\n".write(to: excludeFile, atomically: true, encoding: .utf8)
                    print("Created git exclude list with .action")
                }
            }
            
            // Configure git user for commits
            _ = try GitOperations.runGitCommand(args: ["config", "user.name", "github-actions[bot]"])
            _ = try GitOperations.runGitCommand(args: ["config", "user.email", "github-actions[bot]@users.noreply.github.com"])
            
            // Check for any changes (staged, unstaged, or untracked)
            let statusOutput = try GitOperations.runGitCommand(args: ["status", "--porcelain"])
            if !statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Found uncommitted changes, staging...")
                _ = try GitOperations.runGitCommand(args: ["add", "-A"])
                
                // Check if there are actually staged changes after git add
                let stagedStatus = try GitOperations.runGitCommand(args: ["diff", "--cached", "--name-only"])
                if !stagedStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let fileCount = stagedStatus.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").count
                    print("Committing \(fileCount) file(s)...")
                    _ = try GitOperations.runGitCommand(args: ["commit", "-m", "Complete task: \(task)"])
                } else {
                    print("No changes to commit after staging (files may have been committed by Claude Code)")
                }
            } else {
                print("No uncommitted changes found")
            }
            
            // === STEP 2: Create PR ===
            print("\n=== Step 2/3: Creating pull request ===")
            
            // Reconfigure git auth (Claude Code action may have changed it)
            let remoteUrl = "https://x-access-token:\(ghToken)@github.com/\(githubRepository).git"
            _ = try GitOperations.runGitCommand(args: ["remote", "set-url", "origin", remoteUrl])
            
            // Fetch spec.md from base branch and mark task as complete
            print("Fetching spec.md from base branch...")
            do {
                if let specContent = try GitHubOperations.getFileFromBranch(repo: githubRepository, branch: baseBranch, filePath: specPath) {
                    // Write spec content to local file in PR branch
                    let specFileURL = URL(fileURLWithPath: currentDir).appendingPathComponent(specPath)
                    let specDir = specFileURL.deletingLastPathComponent()
                    if specFileURL.pathComponents.count > 1 { // Only create directory if there is one
                        try FileManager.default.createDirectory(at: specDir, withIntermediateDirectories: true)
                    }
                    try specContent.write(to: specFileURL, atomically: true, encoding: .utf8)
                    
                    // Mark task as complete in the spec file
                    print("Marking task \(taskIndex) as complete in spec.md...")
                    try TaskService.markTaskComplete(planFile: specFileURL.path, task: task)
                    
                    // Stage and commit the updated spec.md
                    _ = try GitOperations.runGitCommand(args: ["add", specFileURL.path])
                    let specStatus = try GitOperations.runGitCommand(args: ["diff", "--cached", "--name-only"])
                    if !specStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("Committing spec.md update...")
                        _ = try GitOperations.runGitCommand(args: ["commit", "-m", "Mark task \(taskIndex) as complete in spec.md"])
                    }
                } else {
                    print("Warning: Could not fetch spec.md from \(baseBranch), skipping spec update")
                }
            } catch {
                print("Warning: Failed to update spec.md: \(error)")
            }
            
            // Check if there are commits to push (after spec.md update)
            // Fetch base branch ref for shallow clone compatibility
            try GitOperations.ensureRefAvailable(ref: "origin/\(baseBranch)")
            
            let commitsCount: Int
            do {
                let commitsAhead = try GitOperations.runGitCommand(args: ["rev-list", "--count", "origin/\(baseBranch)..HEAD"])
                commitsCount = Int(commitsAhead) ?? 0
            } catch {
                commitsCount = 0
            }
            
            if commitsCount == 0 {
                gh.setWarning(message: "No changes made, skipping PR creation")
                gh.writeOutput(name: "pr_number", value: "")
                gh.writeOutput(name: "pr_url", value: "")
                gh.writeStepSummary(text: "ℹ️ **Status**: No changes to commit")
                return
            }
            
            print("Found \(commitsCount) commit(s) to push")
            
            // Push the branch
            _ = try GitOperations.runGitCommand(args: ["push", "-u", "origin", branchName, "--force"])
            
            // Load PR template and substitute
            var prBody: String
            if FileManager.default.fileExists(atPath: prTemplatePath) {
                let templateContent = try String(contentsOfFile: prTemplatePath)
                prBody = Config.substituteTemplate(templateContent, variables: ["TASK_DESCRIPTION": task])
            } else {
                prBody = "## Task\n\(task)"
            }
            
            // Add GitHub Actions run link
            if !githubRunId.isEmpty {
                let actionsUrl = "https://github.com/\(githubRepository)/actions/runs/\(githubRunId)"
                prBody += "\n\n---\n\n*Created by [ClaudeChain run](\(actionsUrl))*"
            }
            
            // Create PR using temp file for body to avoid command-line length/escaping issues
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
            try prBody.write(to: tempURL, atomically: true, encoding: .utf8)
            defer {
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            // Build PR title with truncation to avoid overly long titles
            let maxTitleLength = 80
            let titlePrefix = "ClaudeChain: [\(project)] "
            let availableForTask = maxTitleLength - titlePrefix.count
            let truncatedTask: String
            if task.count > availableForTask {
                truncatedTask = String(task.prefix(availableForTask - 3)) + "..."
            } else {
                truncatedTask = task
            }
            let prTitle = "\(titlePrefix)\(truncatedTask)"
            
            // Build PR creation command (assignee is optional)
            var prCreateArgs = [
                "pr", "create",
                "--draft",
                "--title", prTitle,
                "--body-file", tempURL.path,
                "--label", label,
                "--head", branchName,
                "--base", baseBranch
            ]
            for assignee in assignees {
                prCreateArgs.append(contentsOf: ["--assignee", assignee])
            }
            // Explicit reviewers (not assignees)
            for reviewer in reviewers {
                prCreateArgs.append(contentsOf: ["--reviewer", reviewer])
            }
            
            // Add additional PR labels (comma-separated)
            let prLabels = prLabelsStr
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for prLabel in prLabels {
                prCreateArgs.append(contentsOf: ["--label", prLabel])
            }
            
            let prUrl = try GitHubOperations.runGhCommand(args: prCreateArgs)
            
            print("✅ Created PR: \(prUrl)")
            
            // Query PR number and title
            let prOutput = try GitHubOperations.runGhCommand(args: [
                "pr", "view", branchName,
                "--json", "number,title"
            ])
            
            guard let data = prOutput.data(using: .utf8),
                  let prData = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let prNumber = prData["number"] as? Int else {
                throw GitHubAPIError("Failed to parse PR data")
            }
            
            // No metadata storage - PR state is tracked via GitHub API
            print("\n=== Step 3/3: Finalization complete ===")
            print("✅ PR created successfully (metadata tracked via GitHub API)")
            
            // Write outputs
            gh.writeOutput(name: "pr_number", value: String(prNumber))
            gh.writeOutput(name: "pr_url", value: prUrl)
            
            // Write final summary
            gh.writeStepSummary(text: "✅ **Status**: PR created successfully")
            gh.writeStepSummary(text: "")
            gh.writeStepSummary(text: "- **PR**: #\(prNumber)")
            if !assignees.isEmpty {
                gh.writeStepSummary(text: "- **Assignees**: \(assignees.joined(separator: ", "))")
            } else {
                gh.writeStepSummary(text: "- **Assignees**: (none)")
            }
            if !reviewers.isEmpty {
                gh.writeStepSummary(text: "- **Reviewers**: \(reviewers.joined(separator: ", "))")
            }
            gh.writeStepSummary(text: "- **Task**: \(task)")
            
            print("\n✅ Finalization complete")
            
        } catch let error as GitError {
            let gh = GitHubActions()
            gh.setError(message: "Finalization failed: \(error.message)")
            gh.writeStepSummary(text: "❌ **Status**: Failed to create PR")
            gh.writeStepSummary(text: "- **Error**: \(error.message)")
            throw ExitCode.failure
        } catch let error as GitHubAPIError {
            let gh = GitHubActions()
            gh.setError(message: "Finalization failed: \(error.message)")
            gh.writeStepSummary(text: "❌ **Status**: Failed to create PR")
            gh.writeStepSummary(text: "- **Error**: \(error.message)")
            throw ExitCode.failure
        } catch let error as ConfigurationError {
            let gh = GitHubActions()
            gh.setError(message: "Finalization failed: \(error.message)")
            gh.writeStepSummary(text: "❌ **Status**: Failed to create PR")
            gh.writeStepSummary(text: "- **Error**: \(error.message)")
            throw ExitCode.failure
        } catch {
            let gh = GitHubActions()
            gh.setError(message: "Unexpected error in finalize: \(error.localizedDescription)")
            gh.writeStepSummary(text: "❌ **Status**: Unexpected error")
            print("Exception details: \(error)")
            throw ExitCode.failure
        }
    }
}