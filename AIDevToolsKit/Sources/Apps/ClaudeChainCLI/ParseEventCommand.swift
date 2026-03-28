import ArgumentParser
import ClaudeChainService
import ClaudeChainSDK
import ClaudeChainFeature
import Foundation

public struct ParseEventCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "parse-event",
        abstract: "Parse GitHub event context and output action parameters"
    )
    
    @Option(name: .long, help: "GitHub event name (e.g., pull_request, push, workflow_dispatch)")
    public var eventName: String?
    
    @Option(name: .long, help: "GitHub event JSON payload")
    public var eventJson: String?
    
    @Option(name: .long, help: "Optional project name override")
    public var projectName: String?
    
    @Option(name: .long, help: "Default base branch if not determined from event (default: main)")
    public var defaultBaseBranch: String = "main"
    
    @Option(name: .long, help: "Required label for PR events (default: claudechain)")
    public var prLabel: String = "claudechain"
    
    public init() {}
    
    public func run() throws {
        // Get environment variables (following Python main() function logic)
        let env = ProcessInfo.processInfo.environment
        
        // GitHub built-in env vars
        let eventName = self.eventName ?? env["GITHUB_EVENT_NAME"] ?? ""
        let eventPath = env["GITHUB_EVENT_PATH"] ?? ""
        let repo = env["GITHUB_REPOSITORY"] ?? ""
        
        // Read event JSON from file or use provided value
        var eventJson = self.eventJson ?? "{}"
        if eventJson == "{}" && !eventPath.isEmpty && FileManager.default.fileExists(atPath: eventPath) {
            do {
                eventJson = try String(contentsOfFile: eventPath, encoding: .utf8)
            } catch {
                eventJson = "{}"
            }
        }
        
        // Custom env vars (with command line overrides)
        let projectName = self.projectName ?? env["PROJECT_NAME"]
        let defaultBaseBranch = self.defaultBaseBranch == "main" ? (env["DEFAULT_BASE_BRANCH"] ?? "main") : self.defaultBaseBranch
        
        let exitCode = try cmdParseEvent(
            eventName: eventName,
            eventJson: eventJson,
            projectName: projectName,
            defaultBaseBranch: defaultBaseBranch,
            repo: repo.isEmpty ? nil : repo
        )
        
        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }
    
    /// Parse GitHub event and output action parameters.
    ///
    /// This function is invoked by the action.yml to handle the simplified workflow.
    /// It parses the GitHub event payload and determines:
    /// - Whether execution should be skipped (and why)
    /// - The git ref to checkout
    /// - The project name (from changed spec.md files or workflow_dispatch input)
    /// - The base branch for PR creation
    /// - The merged PR number (for pull_request events)
    ///
    /// - Parameters:
    ///   - eventName: GitHub event name (e.g., "pull_request", "push", "workflow_dispatch")
    ///   - eventJson: JSON payload from ${{ toJson(github.event) }}
    ///   - projectName: Optional project name override (for workflow_dispatch)
    ///   - defaultBaseBranch: Default base branch if not determined from event
    ///   - repo: GitHub repository (owner/name) for API calls
    /// - Returns: 0 on success, 1 on error
    ///
    /// Outputs (via GITHUB_OUTPUT):
    ///   - skip: "true" or "false"
    ///   - skip_reason: Reason for skipping (if skip is true)
    ///   - checkout_ref: Git ref to checkout
    ///   - project_name: Resolved project name
    ///   - base_branch: Base branch for PR creation
    ///   - merged_pr_number: PR number (for pull_request events)
    private func cmdParseEvent(
        eventName: String,
        eventJson: String,
        projectName: String?,
        defaultBaseBranch: String?,
        repo: String?
    ) throws -> Int {
        let gh = GitHubActions()
        
        do {
            print("=== ClaudeChain Event Parsing ===")
            print("Event name: \(eventName)")
            print("Project name override: \(projectName ?? "(none)")")
            print("Default base branch: \(defaultBaseBranch ?? "")")
            
            // Parse the event
            let context = try GitHubEventContext.fromJSON(eventName: eventName, eventJSON: eventJson)
            print("\nParsed event context:")
            print("  Event type: \(context.eventName)")
            if let prNumber = context.prNumber {
                print("  PR number: \(prNumber)")
                print("  PR merged: \(context.prMerged)")
                print("  PR labels: \(context.prLabels)")
            }
            if let headRef = context.headRef {
                print("  Head ref: \(headRef)")
            }
            if let baseRef = context.baseRef {
                print("  Base ref: \(baseRef)")
            }
            if let refName = context.refName {
                print("  Ref name: \(refName)")
            }
            
            // Resolve project name based on event type (mutually exclusive branches)
            var resolvedProject: String?
            
            if context.eventName == "workflow_dispatch" {
                // workflow_dispatch: project_name is required from input
                guard let projectName = projectName else {
                    let errorMsg = "workflow_dispatch requires project_name input"
                    print("\n❌ \(errorMsg)")
                    gh.setError(message: errorMsg)
                    return 1
                }
                resolvedProject = projectName
                
            } else if context.eventName == "pull_request" {
                // PR merge: skip if not merged
                if !context.prMerged {
                    let reason = "PR was closed but not merged"
                    print("\n⏭️  Skipping: \(reason)")
                    gh.writeOutput(name: "skip", value: "true")
                    gh.writeOutput(name: "skip_reason", value: reason)
                    return 0
                }
                
                // Detect projects from PR files
                if let repo = repo, let prNumber = context.prNumber {
                    let detectedProjects = try detectProjectsFromPRFiles(prNumber: prNumber, repo: repo)
                    resolvedProject = selectProjectAndOutputAll(gh: gh, projects: detectedProjects)
                }
                
                // Fallback: detect project from branch name for ClaudeChain PRs
                if resolvedProject == nil, let headRef = context.headRef {
                    resolvedProject = detectProjectFromBranchName(headRef: headRef)
                }
                
                if resolvedProject == nil {
                    let reason = "No spec.md changes detected and branch name is not a ClaudeChain branch"
                    print("\n⏭️  Skipping: \(reason)")
                    gh.writeOutput(name: "skip", value: "true")
                    gh.writeOutput(name: "skip_reason", value: reason)
                    return 0
                }
                
            } else if context.eventName == "push" {
                // Push: detect projects from changed files
                if let repo = repo {
                    let detectedProjects = try detectProjectsFromChangedFiles(context: context, repo: repo)
                    resolvedProject = selectProjectAndOutputAll(gh: gh, projects: detectedProjects)
                }
                
                if resolvedProject == nil {
                    let reason = "No spec.md changes detected"
                    print("\n⏭️  Skipping: \(reason)")
                    gh.writeOutput(name: "skip", value: "true")
                    gh.writeOutput(name: "skip_reason", value: reason)
                    return 0
                }
                
            } else {
                let errorMsg = "Unsupported event type: \(context.eventName)"
                print("\n❌ \(errorMsg)")
                gh.setError(message: errorMsg)
                return 1
            }
            
            // Determine what to checkout based on the event type
            // - PR merge: checkout base_ref (branch the PR merged INTO) - this has the merged changes
            // - push: checkout ref_name (branch that was pushed to)
            // - workflow_dispatch: checkout default_base_branch (where the spec file lives)
            let checkoutRef: String
            if context.eventName == "workflow_dispatch" {
                // For workflow_dispatch, checkout the configured base branch, not the trigger branch
                // The trigger branch (ref_name) is just where the user clicked "Run workflow"
                // but we need to checkout the branch where the spec file and code live
                guard let defaultBaseBranch = defaultBaseBranch else {
                    let reason = "workflow_dispatch requires default_base_branch to be set"
                    print("\n⏭️  Skipping: \(reason)")
                    gh.writeOutput(name: "skip", value: "true")
                    gh.writeOutput(name: "skip_reason", value: reason)
                    return 0
                }
                checkoutRef = defaultBaseBranch
            } else {
                do {
                    checkoutRef = try context.getCheckoutRef()
                } catch {
                    let reason = "Could not determine checkout ref: \(error.localizedDescription)"
                    print("\n⏭️  Skipping: \(reason)")
                    gh.writeOutput(name: "skip", value: "true")
                    gh.writeOutput(name: "skip_reason", value: reason)
                    return 0
                }
            }
            
            // Output results
            print("\n✓ Event parsing complete")
            print("  Skip: false")
            print("  Project: \(resolvedProject!)")
            print("  Checkout ref: \(checkoutRef)")
            
            gh.writeOutput(name: "skip", value: "false")
            gh.writeOutput(name: "project_name", value: resolvedProject!)
            gh.writeOutput(name: "checkout_ref", value: checkoutRef)
            
            // For pull_request events, output the merge target branch and PR number
            // The merge target is the branch the PR was merged INTO (base_ref)
            if context.eventName == "pull_request", let baseRef = context.baseRef {
                print("  Merge target branch: \(baseRef)")
                gh.writeOutput(name: "merge_target_branch", value: baseRef)
            }
            
            if let prNumber = context.prNumber {
                print("  Merged PR number: \(prNumber)")
                gh.writeOutput(name: "merged_pr_number", value: String(prNumber))
            }
            
            return 0
            
        } catch {
            let errorMsg = "Event parsing failed: \(error.localizedDescription)"
            print("\n❌ \(errorMsg)")
            gh.setError(message: errorMsg)
            return 1
        }
    }
    
    /// Select first project to process and output all detected projects as JSON.
    ///
    /// When multiple projects are detected, this function:
    /// 1. Logs a warning about additional projects
    /// 2. Outputs the full list as JSON for advanced users who want matrix workflows
    /// 3. Returns the first project name for processing
    ///
    /// - Parameters:
    ///   - gh: GitHubActions helper for writing outputs
    ///   - projects: List of detected Project objects
    /// - Returns: Name of the first project to process, or nil if no projects detected
    private func selectProjectAndOutputAll(gh: GitHubActions, projects: [Project]) -> String? {
        if projects.isEmpty {
            gh.writeOutput(name: "detected_projects", value: "[]")
            return nil
        }
        
        // Build JSON array with project info
        let projectsData = projects.map { ["name": $0.name, "base_path": $0.basePath] }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: projectsData, options: [])
            let projectsJson = String(data: jsonData, encoding: .utf8) ?? "[]"
            gh.writeOutput(name: "detected_projects", value: projectsJson)
        } catch {
            gh.writeOutput(name: "detected_projects", value: "[]")
        }
        
        if projects.count > 1 {
            let projectNames = projects.map { $0.name }
            print("\n::warning::Multiple projects detected: \(projectNames). Processing '\(projects[0].name)'. Others require separate workflow runs.")
            print("  Tip: Use the 'detected_projects' output with a matrix strategy for parallel processing.")
        }
        
        return projects[0].name
    }
    
    /// Detect projects from changed spec.md files.
    ///
    /// Works for both PR merge events (comparing base..head branches) and push events
    /// (comparing before..after SHAs). This enables the "changed files" triggering model
    /// where spec.md changes automatically trigger ClaudeChain.
    ///
    /// - Parameters:
    ///   - context: Parsed GitHub event context (must have changed files context)
    ///   - repo: GitHub repository (owner/name) for API calls
    /// - Returns: List of Project objects for projects with changed spec.md files.
    ///            Empty list if no spec files were changed or detection failed.
    private func detectProjectsFromChangedFiles(context: GitHubEventContext, repo: String) throws -> [Project] {
        guard let changedFilesContext = context.getChangedFilesContext() else {
            return []
        }
        
        let baseRef = changedFilesContext.baseRef
        let headRef = changedFilesContext.headRef
        
        // Format refs for display (truncate SHAs for push events)
        let baseDisplay = baseRef.count == 40 ? String(baseRef.prefix(8)) : baseRef
        let headDisplay = headRef.count == 40 ? String(headRef.prefix(8)) : headRef
        
        print("\n  Detecting project from changed files...")
        print("  Comparing \(baseDisplay)...\(headDisplay)")
        
        do {
            let changedFiles = try GitHubOperations.compareCommits(repo: repo, base: baseRef, head: headRef)
            print("  Found \(changedFiles.count) changed files")
            let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
            if !projects.isEmpty {
                let projectNames = projects.map { $0.name }
                print("  Detected \(projects.count) project(s) from spec.md changes: \(projectNames)")
            }
            return projects
        } catch {
            // Compare API may fail if branch was deleted after merge
            print("  Could not detect from changed files: \(error.localizedDescription)")
        }
        
        return []
    }
    
    /// Detect project from ClaudeChain branch name pattern.
    ///
    /// This is a fallback for when the PR files API returns no spec.md changes,
    /// which can happen for ClaudeChain PRs that only modify task files.
    ///
    /// ClaudeChain branches follow the pattern: claude-chain-{project}-{hash}
    ///
    /// - Parameter headRef: The head branch name from the PR
    /// - Returns: Project name if the branch matches the ClaudeChain pattern, nil otherwise
    private func detectProjectFromBranchName(headRef: String) -> String? {
        if let branchInfo = BranchInfo.fromBranchName(headRef) {
            print("  Detected project from branch name: \(branchInfo.projectName)")
            return branchInfo.projectName
        }
        return nil
    }
    
    /// Detect projects from files changed in a pull request.
    ///
    /// Uses the GitHub PR Files API which is more reliable than branch comparison
    /// for merged PRs because:
    /// - Works regardless of merge strategy (merge, squash, rebase)
    /// - Returns the actual files changed by the PR, not a branch comparison
    /// - Avoids timing issues where branches point to same commit post-merge
    ///
    /// - Parameters:
    ///   - prNumber: Pull request number
    ///   - repo: GitHub repository (owner/name) for API calls
    /// - Returns: List of Project objects for projects with changed spec.md files.
    ///            Empty list if no spec files were changed or detection failed.
    private func detectProjectsFromPRFiles(prNumber: Int, repo: String) throws -> [Project] {
        print("\n  Detecting project from PR #\(prNumber) files...")
        
        do {
            let changedFiles = try GitHubOperations.getPullRequestFiles(repo: repo, prNumber: prNumber)
            print("  Found \(changedFiles.count) changed files")
            let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
            if !projects.isEmpty {
                let projectNames = projects.map { $0.name }
                print("  Detected \(projects.count) project(s) from spec.md changes: \(projectNames)")
            }
            return projects
        } catch {
            print("  Could not detect from PR files: \(error.localizedDescription)")
        }
        
        return []
    }
}