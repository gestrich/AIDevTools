import ArgumentParser
import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import GitHubService
import GitSDK
import OctokitSDK
import PRRadarCLIService

public struct FinalizeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "finalize",
        abstract: "Finalize after Claude Code execution (commit, PR, summary)"
    )
    
    public init() {}
    
    public func run() async throws {
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
            
            // Initialize GitClient
            let gitClient = GitClient()
            let workingDirectory = FileManager.default.currentDirectoryPath
            let reviewers = (environment["REVIEWERS"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let project = environment["PROJECT"] ?? ""
            let specPath = environment["SPEC_PATH"] ?? ""
            let prTemplatePath = environment["PR_TEMPLATE_PATH"] ?? ""
            // Resolve GH_TOKEN via CredentialResolver (env GITHUB_TOKEN → .env → keychain),
            // falling back to GH_TOKEN env var for GitHub Actions compatibility
            var ghToken = ""
            let credentialAccount = environment["GITHUB_CREDENTIAL_ACCOUNT"] ?? "default"
            let credentialResolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: credentialAccount
            )
            if case .token(let token) = credentialResolver.getGitHubAuth() {
                ghToken = token
            }
            if ghToken.isEmpty {
                ghToken = environment["GH_TOKEN"] ?? ""
            }
            // Inject resolved token so child gh processes authenticate correctly
            if !ghToken.isEmpty {
                setenv("GH_TOKEN", ghToken, 1)
            }
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

            let repoSlugParts = githubRepository.split(separator: "/")
            guard repoSlugParts.count == 2 else {
                throw ConfigurationError("Cannot parse GITHUB_REPOSITORY '\(githubRepository)' as owner/repo")
            }
            let githubService = GitHubServiceFactory.make(
                token: ghToken,
                owner: String(repoSlugParts[0]),
                repo: String(repoSlugParts[1])
            )
            
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
            _ = try await gitClient.config(key: "user.name", value: "github-actions[bot]", workingDirectory: workingDirectory)
            _ = try await gitClient.config(key: "user.email", value: "github-actions[bot]@users.noreply.github.com", workingDirectory: workingDirectory)
            
            // Check for any changes (staged, unstaged, or untracked)
            let statusOutput = try await gitClient.status(workingDirectory: workingDirectory)
            if !statusOutput.isEmpty {
                print("Found uncommitted changes, staging...")
                _ = try await gitClient.addAll(workingDirectory: workingDirectory)
                
                // Check if there are actually staged changes after git add
                let stagedStatus = try await gitClient.diffCachedNames(workingDirectory: workingDirectory)
                if !stagedStatus.isEmpty {
                    let fileCount = stagedStatus.count
                    print("Committing \(fileCount) file(s)...")
                    _ = try await gitClient.commit(message: "Complete task: \(task)", workingDirectory: workingDirectory)
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
            _ = try await gitClient.remoteSetURL(name: "origin", url: remoteUrl, workingDirectory: workingDirectory)
            
            // Fetch spec.md from base branch and mark task as complete
            print("Fetching spec.md from base branch...")
            do {
                var specContent: String?
                do {
                    specContent = try await githubService.fileContent(path: specPath, ref: baseBranch)
                } catch let e {
                    let desc = e.localizedDescription
                    if desc.contains("404") || desc.lowercased().contains("not found") {
                        specContent = nil
                    } else {
                        throw e
                    }
                }
                if let specContent {
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
                    _ = try await gitClient.add(files: [specFileURL.path], workingDirectory: workingDirectory)
                    let specStatus = try await gitClient.diffCachedNames(workingDirectory: workingDirectory)
                    if !specStatus.isEmpty {
                        print("Committing spec.md update...")
                        _ = try await gitClient.commit(message: "Mark task \(taskIndex) as complete in spec.md", workingDirectory: workingDirectory)
                    }
                } else {
                    print("Warning: Could not fetch spec.md from \(baseBranch), skipping spec update")
                }
            } catch {
                print("Warning: Failed to update spec.md: \(error)")
            }
            
            // Check if there are commits to push (after spec.md update)
            // Fetch base branch ref for shallow clone compatibility
            try await gitClient.ensureRefAvailable(ref: "origin/\(baseBranch)", workingDirectory: workingDirectory)
            
            let commitsCount: Int
            do {
                commitsCount = try await gitClient.revListCount(range: "origin/\(baseBranch)..HEAD", workingDirectory: workingDirectory)
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
            _ = try await gitClient.push(remote: "origin", branch: branchName, setUpstream: true, force: true, workingDirectory: workingDirectory)
            
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

            let prLabels = prLabelsStr
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var allLabels = [label].filter { !$0.isEmpty }
            allLabels.append(contentsOf: prLabels)

            let createdPR = try await githubService.createPullRequest(
                title: prTitle,
                body: prBody,
                head: branchName,
                base: baseBranch,
                draft: true,
                labels: allLabels,
                assignees: assignees.filter { !$0.isEmpty },
                reviewers: reviewers.filter { !$0.isEmpty }
            )
            let prUrl = createdPR.htmlURL
            let prNumber = createdPR.number

            print("✅ Created PR: \(prUrl)")
            
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