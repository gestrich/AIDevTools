import ArgumentParser
import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import GitSDK

public struct PrepareCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Prepare everything for Claude Code execution"
    )
    
    public init() {}
    
    public func run() async throws {
        /**
         * Orchestrate preparation workflow using Service Layer classes.
         *
         * This command instantiates services and coordinates their operations but
         * does not implement business logic directly. Follows Service Layer pattern
         * where CLI acts as thin orchestration layer.
         *
         * Workflow: detect-project, setup, check-capacity, find-task, create-branch, prepare-prompt
         */
        do {
            // === Get common dependencies ===
            let env = ProcessInfo.processInfo.environment
            let repo = env["GITHUB_REPOSITORY"] ?? ""
            
            // Initialize GitClient
            let gitClient = GitClient()
            let workingDirectory = FileManager.default.currentDirectoryPath

            // Resolve GH_TOKEN via CredentialResolver so all child gh processes authenticate.
            // CredentialResolver checks GITHUB_TOKEN env → .env → keychain.
            // Falls back to GH_TOKEN env var for GitHub Actions compatibility.
            let credentialAccount = env["GITHUB_CREDENTIAL_ACCOUNT"] ?? "default"
            let credentialResolver = CredentialResolver(
                settingsService: CredentialSettingsService(),
                githubAccount: credentialAccount
            )
            if case .token(let token) = credentialResolver.getGitHubAuth() {
                setenv("GH_TOKEN", token, 1)
            } else if let existingToken = env["GH_TOKEN"], !existingToken.isEmpty {
                setenv("GH_TOKEN", existingToken, 1)
            }

            // Initialize infrastructure
            let projectRepository = ProjectRepository(repo: repo)
            
            // Initialize services
            let prService = PRService(repo: repo)
            let taskService = TaskService(repo: repo, prService: prService)
            let assigneeService = AssigneeService(repo: repo, prService: prService)
            
            // Initialize GitHub Actions helper
            let gh = GitHubActions()
            
            // === STEP 1: Detect Project ===
            print("=== Step 1/6: Detecting project ===")
            let projectName = env["PROJECT_NAME"] ?? ""
            let mergedPRNumber = env["MERGED_PR_NUMBER"] ?? ""
            
            // project_name is always provided by parse_event (for PR merges) or workflow input (for manual triggers)
            if projectName.isEmpty {
                gh.setError(message: "PROJECT_NAME must be provided (set by parse_event or workflow_dispatch input)")
                throw ExitCode(1)
            }
            
            if !mergedPRNumber.isEmpty {
                print("Processing merged PR #\(mergedPRNumber) for project '\(projectName)'")
                print("Proceeding to prepare next task...")
            } else {
                print("Using provided project name: \(projectName)")
            }
            
            // Create Project domain model
            let project = Project(name: projectName)
            
            // Get default base branch from environment (workflow provides this)
            // Use env var if set and non-empty, otherwise fall back to constant
            let envBaseBranch = env["BASE_BRANCH"] ?? ""
            let defaultBaseBranch = !envBaseBranch.isEmpty ? envBaseBranch : Constants.defaultBaseBranch
            
            // === STEP 2: Load Configuration and Resolve Base Branch ===
            print("\n=== Step 2/6: Loading configuration ===")
            
            // Load configuration from local filesystem (after checkout)
            // This is more efficient than GitHub API and works for all trigger types
            let config = try projectRepository.loadLocalConfiguration(project: project)
            
            // Resolve actual base branch (config override or default)
            let baseBranch = config.getBaseBranch(defaultBaseBranch: defaultBaseBranch)
            if baseBranch != defaultBaseBranch {
                print("Base branch: \(baseBranch) (overridden from default: \(defaultBaseBranch))")
            } else {
                print("Base branch: \(baseBranch)")
            }
            
            // Validate base branch matches expected target
            let mergeTargetBranch = env["MERGE_TARGET_BRANCH"] ?? ""
            if !mergeTargetBranch.isEmpty {
                // PR merge event
                if let result = validateBaseBranchForPRMerge(
                    gh: gh,
                    projectName: projectName,
                    expectedBaseBranch: baseBranch,
                    mergeTargetBranch: mergeTargetBranch
                ) {
                    throw ExitCode(Int32(result))
                }
            } else {
                // workflow_dispatch event
                if let result = validateBaseBranchForWorkflowDispatch(
                    gh: gh,
                    projectName: projectName,
                    configBaseBranch: config.baseBranch,
                    providedBaseBranch: defaultBaseBranch
                ) {
                    throw ExitCode(Int32(result))
                }
            }
            
            // Get default allowed tools and PR labels from environment
            let defaultAllowedTools = env["CLAUDE_ALLOWED_TOOLS"] ?? Constants.defaultAllowedTools
            let defaultPRLabels = env["PR_LABELS"] ?? ""
            
            // Resolve allowed tools (config override or default)
            let allowedTools = config.getAllowedTools(defaultAllowedTools: defaultAllowedTools)
            if allowedTools != defaultAllowedTools {
                print("Allowed tools: \(allowedTools) (overridden from default)")
            } else {
                print("Allowed tools: \(allowedTools)")
            }
            
            // Resolve PR labels (config override or default)
            let prLabels = config.getLabels(defaultLabels: defaultPRLabels)
            if prLabels != defaultPRLabels {
                print("PR labels: \(prLabels) (overridden from default)")
            } else if !prLabels.isEmpty {
                print("PR labels: \(prLabels)")
            }
            
            let slackWebhookUrl = env["SLACK_WEBHOOK_URL"] ?? ""  // From action input
            let label = env["PR_LABEL"] ?? "claudechain"  // From action input, defaults to "claudechain"
            
            // Ensure label exists
            GitHubOperations.ensureLabelExists(label: label, gh: gh)
            
            // Load spec from local filesystem (after checkout)
            print("Loading spec from local filesystem...")
            guard let spec = try projectRepository.loadLocalSpec(project: project) else {
                let errorMsg = """
                Error: spec.md not found at '\(project.specPath)'
                Required file:
                  - \(project.specPath)

                Please ensure your spec.md file exists and the checkout was successful.
                """
                gh.setError(message: errorMsg)
                throw ExitCode(1)
            }
            
            print("✅ spec.md loaded from local filesystem")
            
            _ = try Config.validateSpecFormatFromString(content: spec.content, sourceName: project.specPath)
            
            print("✅ Configuration loaded: label=\(label)")
            
            // === STEP 3: Check Capacity ===
            print("\n=== Step 3/6: Checking capacity ===")
            
            let capacityResult = assigneeService.checkCapacity(config: config, label: label, project: projectName)
            
            let summary = capacityResult.formatSummary()
            gh.writeStepSummary(text: summary)
            print("\n\(summary)")
            
            // Check capacity
            if !capacityResult.hasCapacity {
                gh.writeOutput(name: "has_capacity", value: "false")
                gh.writeOutput(name: "assignee", value: "")
                gh.writeOutput(name: "assignees", value: "")
                gh.writeOutput(name: "reviewers", value: "")
                gh.setNotice(message: "Project at capacity (\(capacityResult.maxOpenPRs) open PR limit), skipping PR creation")
                return  // Exit code 0 - not an error, just no capacity
            }
            
            gh.writeOutput(name: "has_capacity", value: "true")
            gh.writeOutput(name: "assignee", value: capacityResult.assignees.first ?? "")  // backward compat
            gh.writeOutput(name: "assignees", value: capacityResult.assignees.joined(separator: ","))
            gh.writeOutput(name: "reviewers", value: capacityResult.reviewers.joined(separator: ","))
            if !capacityResult.assignees.isEmpty {
                print("✅ Capacity available - assignees: \(capacityResult.assignees.joined(separator: ", "))")
            } else {
                print("✅ Capacity available (no assignee configured)")
            }
            
            // === STEP 4: Find Next Task ===
            print("\n=== Step 4/6: Finding next task ===")
            
            // Detect orphaned PRs (PRs for tasks that have been modified or removed)
            let orphanedPRs = taskService.detectOrphanedPrs(label: label, project: projectName, spec: spec)
            if !orphanedPRs.isEmpty {
                print("\n⚠️  Warning: Found \(orphanedPRs.count) orphaned PR(s):")
                
                // Build console output and GitHub Actions summary
                var orphanedList: [String] = []
                for pr in orphanedPRs {
                    if let taskHash = pr.taskHash {
                        let msg = "PR #\(pr.number) (\(pr.headRefName ?? "")) - task hash \(taskHash) no longer matches any task"
                        print("  - \(msg)")
                        orphanedList.append("- \(msg)")
                    } else if pr.headRefName?.contains("-") == true {
                        // Try to extract index from old-style branches
                        let components = pr.headRefName!.components(separatedBy: "-")
                        if let lastComponent = components.last, Int(lastComponent) != nil {
                            let msg = "PR #\(pr.number) (\(pr.headRefName!)) - task index \(lastComponent) no longer valid"
                            print("  - \(msg)")
                            orphanedList.append("- \(msg)")
                        }
                    }
                }
                
                print("\nTo resolve:")
                print("  1. Review these PRs and verify if they should be closed")
                print("  2. Close any PRs for modified/removed tasks")
                print("  3. ClaudeChain will automatically create new PRs for current tasks")
                print()
                
                // Add to GitHub Actions step summary with PR links
                if !repo.isEmpty {
                    var summaryText = "\n## ⚠️ Orphaned PRs Detected\n\n"
                    summaryText += "Found \(orphanedPRs.count) PR(s) for tasks that have been modified or removed:\n\n"
                    for pr in orphanedPRs {
                        let prUrl = "https://github.com/\(repo)/pull/\(pr.number)"
                        if let taskHash = pr.taskHash {
                            summaryText += "- [PR #\(pr.number)](\(prUrl)) (`\(pr.headRefName ?? "")`) - task hash `\(taskHash)` no longer matches any task\n"
                        } else if pr.headRefName?.contains("-") == true {
                            let components = pr.headRefName!.components(separatedBy: "-")
                            if let lastComponent = components.last, Int(lastComponent) != nil {
                                summaryText += "- [PR #\(pr.number)](\(prUrl)) (`\(pr.headRefName!)`) - task index `\(lastComponent)` no longer valid\n"
                            }
                        }
                    }
                    summaryText += "\n**To resolve:**\n"
                    summaryText += "1. Review these PRs and verify if they should be closed\n"
                    summaryText += "2. Close any PRs for modified/removed tasks\n"
                    summaryText += "3. ClaudeChain will automatically create new PRs for current tasks\n"
                    gh.writeStepSummary(text: summaryText)
                }
            }
            
            // Get in-progress tasks
            let inProgressHashes = taskService.getInProgressTasks(label: label, project: projectName)
            
            if !inProgressHashes.isEmpty {
                print("Found in-progress tasks: \(Array(inProgressHashes).sorted())")
            }
            
            guard let result = taskService.findNextAvailableTask(spec: spec, skipHashes: inProgressHashes) else {
                gh.writeOutput(name: "has_task", value: "false")
                gh.writeOutput(name: "all_tasks_done", value: "true")
                gh.setNotice(message: "No available tasks (all completed or in progress)")
                return  // Exit code 0 - not an error, just no tasks
            }
            
            let (taskIndex, task, taskHash) = result
            print("✅ Found task \(taskIndex): \(task)")
            print("   Task hash: \(taskHash)")
            
            // === STEP 5: Create Branch ===
            print("\n=== Step 5/6: Creating branch ===")
            // Use standard ClaudeChain branch format: claude-chain-{project}-{task_hash}
            let branchName = PRService.formatBranchName(projectName: projectName, taskHash: taskHash)
            
            do {
                _ = try await gitClient.checkout(ref: branchName, createBranch: true, workingDirectory: workingDirectory)
                print("✅ Created branch: \(branchName)")
            } catch {
                gh.setError(message: "Failed to create branch: \(error.localizedDescription)")
                throw ExitCode(1)
            }
            
            // === STEP 6: Prepare Claude Prompt ===
            print("\n=== Step 6/6: Preparing Claude prompt ===")
            
            // Create the prompt using spec content
            let claudePrompt = """
            Complete the following task from spec.md:

            Task: \(task)

            Instructions: Read the entire spec.md file below to understand both WHAT to do and HOW to do it. Follow all guidelines and patterns specified in the document.

            --- BEGIN spec.md ---
            \(spec.content)
            --- END spec.md ---

            Now complete the task '\(task)' following all the details and instructions in the spec.md file above.
            """
            
            print("✅ Prompt prepared (\(claudePrompt.count) characters)")
            
            // === Add label to merged PR (Phase 6) ===
            // This helps statistics discover all ClaudeChain-related PRs
            if !mergedPRNumber.isEmpty, let prNumber = Int(mergedPRNumber) {
                if GitHubOperations.addLabelToPr(repo: repo, prNumber: prNumber, label: label) {
                    print("✅ Added '\(label)' label to merged PR #\(mergedPRNumber)")
                }
            }
            
            // === Write All Outputs ===
            gh.writeOutput(name: "project_name", value: projectName)
            gh.writeOutput(name: "project_path", value: project.basePath)
            gh.writeOutput(name: "config_path", value: project.configPath)
            gh.writeOutput(name: "spec_path", value: project.specPath)
            gh.writeOutput(name: "pr_template_path", value: project.prTemplatePath)
            gh.writeOutput(name: "base_branch", value: baseBranch)
            gh.writeOutput(name: "allowed_tools", value: allowedTools)
            gh.writeOutput(name: "pr_labels", value: prLabels)
            gh.writeOutput(name: "label", value: label)
            gh.writeOutput(name: "slack_webhook_url", value: slackWebhookUrl)
            gh.writeOutput(name: "task_description", value: task)
            gh.writeOutput(name: "task_index", value: String(taskIndex))
            gh.writeOutput(name: "task_hash", value: taskHash)
            gh.writeOutput(name: "has_task", value: "true")
            gh.writeOutput(name: "all_tasks_done", value: "false")
            gh.writeOutput(name: "branch_name", value: branchName)
            gh.writeOutput(name: "claude_prompt", value: claudePrompt)
            gh.writeOutput(name: "json_schema", value: ClaudeSchemas.getMainTaskSchemaJSON() ?? "")
            gh.writeOutput(name: "tasks_completed", value: String(spec.completedTasks))
            gh.writeOutput(name: "tasks_total", value: String(spec.totalTasks))
            gh.writeOutput(name: "max_open_prs", value: String(capacityResult.maxOpenPRs))
            gh.writeOutput(name: "open_pr_count", value: String(capacityResult.openCount))
            
            print("\n✅ Preparation complete - ready to run Claude Code")
            
        } catch let error as FileNotFoundError {
            let gh = GitHubActions()
            gh.setError(message: "Preparation failed: \(error.message)")
            throw ExitCode(1)
        } catch let error as ConfigurationError {
            let gh = GitHubActions()
            gh.setError(message: "Preparation failed: \(error.message)")
            throw ExitCode(1)
        } catch let error as GitError {
            let gh = GitHubActions()
            gh.setError(message: "Preparation failed: \(error.message)")
            throw ExitCode(1)
        } catch let error as GitHubAPIError {
            let gh = GitHubActions()
            gh.setError(message: "Preparation failed: \(error.message)")
            throw ExitCode(1)
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            let gh = GitHubActions()
            gh.setError(message: "Unexpected error in prepare: \(error.localizedDescription)")
            print("Stacktrace: \(error)")
            throw ExitCode(1)
        }
    }
}

// MARK: - Private helper functions

/// Validate base branch for PR merge events.
///
/// For PR merges, we SKIP (not error) if the merge target doesn't match
/// the expected base branch. This is normal - the PR just merged to a
/// different branch than this project uses.
///
/// - Parameters:
///   - gh: GitHub Actions helper for outputs
///   - projectName: Name of the project being processed
///   - expectedBaseBranch: Base branch from project config (or default)
///   - mergeTargetBranch: Branch the PR was merged INTO
/// - Returns: 0 to skip processing, nil to continue
private func validateBaseBranchForPRMerge(
    gh: GitHubActions,
    projectName: String,
    expectedBaseBranch: String,
    mergeTargetBranch: String
) -> Int? {
    if mergeTargetBranch != expectedBaseBranch {
        let skipMsg = "Skipping: Project '\(projectName)' expects base branch '\(expectedBaseBranch)' but PR merged into '\(mergeTargetBranch)'"
        print("\n⏭️  \(skipMsg)")
        gh.setNotice(message: skipMsg)
        gh.writeOutput(name: "has_capacity", value: "false")
        gh.writeOutput(name: "has_task", value: "false")
        gh.writeOutput(name: "base_branch_mismatch", value: "true")
        return 0  // Skip, not error
    }
    
    return nil  // Continue processing
}

/// Validate base branch for workflow_dispatch events.
///
/// For manual triggers, we ERROR (not skip) if the provided base branch
/// doesn't match the project's configured baseBranch. This catches user
/// errors where they selected the wrong branch in the GitHub UI.
///
/// - Parameters:
///   - gh: GitHub Actions helper for errors
///   - projectName: Name of the project being processed
///   - configBaseBranch: baseBranch from project config (nil if not set)
///   - providedBaseBranch: base_branch input from workflow_dispatch
/// - Returns: 1 to error, nil to continue
private func validateBaseBranchForWorkflowDispatch(
    gh: GitHubActions,
    projectName: String,
    configBaseBranch: String?,
    providedBaseBranch: String
) -> Int? {
    if let configBaseBranch = configBaseBranch, configBaseBranch != providedBaseBranch {
        let errorMsg = "Base branch mismatch: project '\(projectName)' expects '\(configBaseBranch)' but workflow was triggered with '\(providedBaseBranch)'"
        print("\n❌ \(errorMsg)")
        gh.setError(message: errorMsg)
        return 1  // Error, not skip
    }
    
    return nil  // Continue processing
}