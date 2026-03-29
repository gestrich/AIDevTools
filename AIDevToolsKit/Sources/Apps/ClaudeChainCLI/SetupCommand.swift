import ArgumentParser
import CLISDK
import ClaudeChainSDK
import ClaudeChainService
import Foundation
import GitSDK

public struct SetupCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Set up ClaudeChain configuration for a repository"
    )
    
    @Argument(help: "Path to the repository to set up")
    var repositoryPath: String
    
    public init() {}
    
    public func run() async throws {
        let resolvedPath = URL(fileURLWithPath: repositoryPath).standardizedFileURL.path
        
        print("ClaudeChain Interactive Setup")
        print(String(repeating: "=", count: 40))
        print("")
        print("Repository: \(resolvedPath)")
        
        if !FileManager.default.fileExists(atPath: resolvedPath) {
            print("\nError: Path does not exist: \(resolvedPath)")
            throw ExitCode.failure
        }
        
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            print("\nError: Path is not a directory: \(resolvedPath)")
            throw ExitCode.failure
        }
        
        // Main menu
        let choice = promptMenu(
            title: "What would you like to do?",
            options: [
                ("Setup repository", "Create workflow files and configure GitHub settings"),
                ("Create new spec (project)", "Add a new project with spec.md and supporting files"),
                ("Deploy spec (project)", "Push changes to GitHub and trigger first workflow")
            ]
        )
        
        switch choice {
        case 0:
            let result = try await setupNewRepo(repoPath: resolvedPath)
            if result != 0 {
                throw ExitCode.failure
            }
        case 1:
            let result = try await addProject(repoPath: resolvedPath)
            if result == nil {
                throw ExitCode.failure
            } else {
                let (projectName, _) = result!
                print("\n" + String(repeating: "=", count: 50))
                print("Spec Created!")
                print(String(repeating: "=", count: 50))
                print("""

Project '\(projectName)' is ready.

Next step: Deploy spec (project)
  Run this command again and select 'Deploy spec (project)' to push
  your changes and trigger the first workflow.
""")
            }
        case 2:
            let result = try await deployToGitHub(repoPath: resolvedPath)
            if result != 0 {
                throw ExitCode.failure
            }
        default:
            break
        }
    }
}

// MARK: - Helper Functions

/// Prompt user for yes/no with a default
private func promptYesNo(question: String, defaultValue: Bool = true) -> Bool {
    let suffix = defaultValue ? "[Y/n]" : "[y/N]"
    print(question + " " + suffix + " ", terminator: "")
    
    guard let response = readLine() else {
        return defaultValue
    }
    
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    
    if trimmed.isEmpty {
        return defaultValue
    }
    return trimmed == "y" || trimmed == "yes"
}

/// Prompt user for input with optional default
private func promptInput(question: String, defaultValue: String = "") -> String {
    if !defaultValue.isEmpty {
        print(question + " [\(defaultValue)]: ", terminator: "")
        guard let response = readLine() else {
            return defaultValue
        }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    } else {
        print(question + ": ", terminator: "")
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// Display a menu and get user selection
private func promptMenu(title: String, options: [(String, String)]) -> Int {
    print("\n\(title)")
    print(String(repeating: "-", count: title.count))
    for (i, (label, description)) in options.enumerated() {
        print("  \(i + 1). \(label)")
        if !description.isEmpty {
            print("     \(description)")
        }
    }
    print("")
    
    while true {
        print("Select option [1-\(options.count)]: ", terminator: "")
        guard let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            continue
        }
        
        if let choice = Int(response), choice >= 1, choice <= options.count {
            return choice - 1
        }
        print("Please enter a number between 1 and \(options.count)")
    }
}

// MARK: - Validation Functions

/// Check if path is a git repository
private func validateGitRepo(repoPath: String) -> Bool {
    let gitPath = (repoPath as NSString).appendingPathComponent(".git")
    return FileManager.default.fileExists(atPath: gitPath)
}

/// Check if repo has GitHub remote
private func validateGitHubRepo(repoPath: String) -> Bool {
    let gitConfigPath = (repoPath as NSString).appendingPathComponent(".git/config")
    
    guard FileManager.default.fileExists(atPath: gitConfigPath) else {
        return false
    }
    
    guard let content = try? String(contentsOfFile: gitConfigPath, encoding: .utf8) else {
        return false
    }
    
    return content.contains("github.com")
}

/// Check if ClaudeChain workflow already exists
private func hasClaudeChainWorkflow(repoPath: String) -> Bool {
    let workflowsDir = (repoPath as NSString).appendingPathComponent(".github/workflows")
    
    guard FileManager.default.fileExists(atPath: workflowsDir) else {
        return false
    }
    
    do {
        let files = try FileManager.default.contentsOfDirectory(atPath: workflowsDir)
        for file in files {
            if file.hasSuffix(".yml") || file.hasSuffix(".yaml") {
                let filePath = (workflowsDir as NSString).appendingPathComponent(file)
                if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                    if content.contains("gestrich/claude-chain") || content.lowercased().contains("claudechain") {
                        return true
                    }
                }
            }
        }
    } catch {
        return false
    }
    
    return false
}

/// Get the current git branch name
private func getCurrentBranch(repoPath: String) async -> String {
    do {
        let gitClient = GitClient()
        return try await gitClient.getCurrentBranch(workingDirectory: repoPath)
    } catch {
        return "main"  // fallback on error
    }
}

/// Get the ClaudeChain workflow name from the workflow file
private func getWorkflowName(repoPath: String) -> String {
    let workflowFile = (repoPath as NSString).appendingPathComponent(".github/workflows/claudechain.yml")
    
    guard let content = try? String(contentsOfFile: workflowFile, encoding: .utf8) else {
        return "ClaudeChain"
    }
    
    for line in content.components(separatedBy: "\n") {
        if line.hasPrefix("name:") {
            return String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    return "ClaudeChain"
}

// MARK: - Main Setup Functions

/// Walk through full repository setup
private func setupNewRepo(repoPath: String) async throws -> Int {
    print("\n" + String(repeating: "=", count: 50))
    print("Setup Repository")
    print(String(repeating: "=", count: 50))
    
    // Step 1: Validate git repo
    print("\nStep 1: Validating repository")
    print(String(repeating: "-", count: 30))
    
    if !validateGitRepo(repoPath: repoPath) {
        print("Error: \(repoPath) is not a git repository.")
        print("Please run 'git init' first or provide a valid git repository path.")
        return 1
    }
    
    print("  Git repository found")
    
    if !validateGitHubRepo(repoPath: repoPath) {
        print("  Warning: No GitHub remote detected.")
        if !promptYesNo(question: "  Continue anyway?", defaultValue: false) {
            return 1
        }
    } else {
        print("  GitHub remote detected")
    }
    
    if hasClaudeChainWorkflow(repoPath: repoPath) {
        print("  ClaudeChain workflow already exists!")
        if !promptYesNo(question: "  Continue and overwrite?", defaultValue: false) {
            print("\nTip: Use 'Add project' to add a new project to your existing setup.")
            return 0
        }
    }
    
    // Step 2: Create workflow file
    print("\nStep 2: Create GitHub Actions Workflow")
    print(String(repeating: "-", count: 30))
    
    if promptYesNo(question: "  Create ClaudeChain workflow file? (Recommended)", defaultValue: true) {
        try createWorkflowFile(repoPath: repoPath)
        print("  Created .github/workflows/claudechain.yml")
    } else {
        print("  Skipped workflow creation")
    }
    
    // Step 3: Statistics workflow (optional)
    print("\nStep 3: Statistics Workflow (Optional)")
    print(String(repeating: "-", count: 30))
    print("  The statistics workflow posts progress reports to Slack.")
    
    if promptYesNo(question: "  Create statistics workflow?", defaultValue: false) {
        try createStatisticsWorkflow(repoPath: repoPath)
        print("  Created .github/workflows/claudechain-statistics.yml")
    } else {
        print("  Skipped statistics workflow")
    }
    
    // Step 4: GitHub configuration instructions
    print("\nStep 4: Configure GitHub Settings")
    print(String(repeating: "-", count: 30))
    print("""

  You'll need to configure these settings in your GitHub repository:

  1. Add secret: CLAUDE_CHAIN_ANTHROPIC_API_KEY
     Settings -> Secrets and variables -> Actions -> New repository secret
     Get your API key from: https://console.anthropic.com

  2. Enable PR creation:
     Settings -> Actions -> General -> Workflow permissions
     Check "Allow GitHub Actions to create and approve pull requests"

  3. (Optional) Add secret: CLAUDE_CHAIN_SLACK_WEBHOOK_URL
     For Slack notifications when PRs are created
""")
    
    print("  Press Enter when you've completed these steps...", terminator: "")
    _ = readLine()
    
    // Step 5: Create first project
    print("\nStep 5: Create Your First Project")
    print(String(repeating: "-", count: 30))
    
    if promptYesNo(question: "  Create a project now? (Recommended)", defaultValue: true) {
        let result = try await addProject(repoPath: repoPath)
        if result == nil {
            return 1
        }
    } else {
        print("  Skipped project creation")
        print("\n  Run 'claudechain setup \(repoPath)' again and select 'Add project' when ready.")
    }
    
    // Done - point to deploy step
    print("\n" + String(repeating: "=", count: 50))
    print("Setup Complete!")
    print(String(repeating: "=", count: 50))
    print("""

Your ClaudeChain configuration is ready!

Next step: Deploy spec (project)
  Run this command again and select 'Deploy spec (project)' to:
  - Push your changes to GitHub
  - Trigger your first workflow

  Or manually:
  1. Commit and push the generated files to your default branch
  2. Go to GitHub -> Actions and trigger the ClaudeChain workflow
""")
    
    return 0
}

/// Add a new ClaudeChain project to the repository
private func addProject(repoPath: String) async throws -> (String, String)? {
    print("\n" + String(repeating: "=", count: 50))
    print("Create New Spec (Project)")
    print(String(repeating: "=", count: 50))
    
    // Get project name
    print("")
    let projectName = promptInput(question: "Project name (e.g., 'auth-refactor', 'api-cleanup')")
    if projectName.isEmpty {
        print("Error: Project name is required.")
        return nil
    }
    
    // Sanitize project name
    let sanitizedProjectName = projectName.lowercased().replacingOccurrences(of: " ", with: "-")
    let projectDir = (repoPath as NSString).appendingPathComponent("claude-chain/\(sanitizedProjectName)")
    
    if FileManager.default.fileExists(atPath: projectDir) {
        print("Error: Project '\(sanitizedProjectName)' already exists at \(projectDir)")
        return nil
    }
    
    // Base branch
    print("")
    let currentBranch = await getCurrentBranch(repoPath: repoPath)
    let baseBranch = promptInput(question: "Base branch for PRs", defaultValue: currentBranch)
    
    // Optional: assignee
    print("")
    var assignee = ""
    if promptYesNo(question: "Assign PRs to a specific GitHub user?", defaultValue: false) {
        assignee = promptInput(question: "GitHub username")
    }
    
    // Create the project
    print("")
    print("Creating project '\(sanitizedProjectName)'...")
    
    try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true, attributes: nil)
    
    // Create spec.md with sample tasks
    let specContent = """
# \(sanitizedProjectName.replacingOccurrences(of: "-", with: " ").capitalized)

This project will print statements as defined in the tasks below.
Each task creates a simple script that outputs the specified message.

## Tasks

- [ ] Print "Hello World!"
- [ ] Print "Hello World!!"
- [ ] Print "Hello World!!!"
"""
    let specPath = (projectDir as NSString).appendingPathComponent("spec.md")
    try specContent.write(toFile: specPath, atomically: true, encoding: .utf8)
    print("  Created \(projectDir)/spec.md")
    
    // Create configuration.yml if assignee or non-default base branch
    var configLines: [String] = []
    if baseBranch != "main" {
        configLines.append("baseBranch: \(baseBranch)")
    }
    if !assignee.isEmpty {
        configLines.append("assignee: \(assignee)")
    }
    
    if !configLines.isEmpty {
        let configContent = configLines.joined(separator: "\n") + "\n"
        let configPath = (projectDir as NSString).appendingPathComponent("configuration.yml")
        try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        print("  Created \(projectDir)/configuration.yml")
    }
    
    // Always create pr-template.md
    let templateContent = """
## Task

{{TASK_DESCRIPTION}}

## Review Checklist

- [ ] Code follows project conventions
- [ ] Tests pass
- [ ] No unintended changes

---
*Auto-generated by ClaudeChain*
"""
    let templatePath = (projectDir as NSString).appendingPathComponent("pr-template.md")
    try templateContent.write(toFile: templatePath, atomically: true, encoding: .utf8)
    print("  Created \(projectDir)/pr-template.md")
    
    // Create pre-action.sh
    let preActionContent = """
#!/bin/bash
# Pre-action script - runs before Claude Code execution
# Add any setup steps here (e.g., install dependencies, generate code)

echo "Pre-action script completed successfully"
"""
    let preActionPath = (projectDir as NSString).appendingPathComponent("pre-action.sh")
    try preActionContent.write(toFile: preActionPath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: preActionPath)
    print("  Created \(projectDir)/pre-action.sh")
    
    // Create post-action.sh
    let postActionContent = """
#!/bin/bash
# Post-action script - runs after Claude Code execution
# Add any validation steps here (e.g., run tests, lint code)

echo "Post-action script completed successfully"
"""
    let postActionPath = (projectDir as NSString).appendingPathComponent("post-action.sh")
    try postActionContent.write(toFile: postActionPath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: postActionPath)
    print("  Created \(projectDir)/post-action.sh")
    
    print("")
    print("Project '\(sanitizedProjectName)' created successfully!")
    print("Edit \(projectDir)/spec.md to customize your tasks.")
    
    return (sanitizedProjectName, baseBranch)
}

/// Guide user through deploying ClaudeChain to GitHub
private func deployToGitHub(repoPath: String) async throws -> Int {
    print("\n" + String(repeating: "=", count: 50))
    print("Deploy Spec (Project)")
    print(String(repeating: "=", count: 50))
    
    // Check for workflow file
    if !hasClaudeChainWorkflow(repoPath: repoPath) {
        print("""

  Error: No ClaudeChain workflow file found.

  Please run 'Setup repository' first to create the workflow files.
""")
        return 1
    }
    
    // Find existing projects
    let projectsDir = (repoPath as NSString).appendingPathComponent("claude-chain")
    var projects: [String] = []
    
    if FileManager.default.fileExists(atPath: projectsDir) {
        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: projectsDir)
            for entry in entries {
                let entryPath = (projectsDir as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: entryPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    let specPath = (entryPath as NSString).appendingPathComponent("spec.md")
                    if FileManager.default.fileExists(atPath: specPath) {
                        projects.append(entry)
                    }
                }
            }
        } catch {
            // Handle error silently, projects will remain empty
        }
    }
    
    let projectName: String?
    let baseBranch: String
    
    if projects.isEmpty {
        print("""

  Warning: No projects found in claude-chain/ directory.

  You can still deploy the workflow files, but you'll need to add a
  project before ClaudeChain can create PRs.
""")
        projectName = nil
        baseBranch = "main"
    } else {
        print("\n  Found \(projects.count) project(s): \(projects.joined(separator: ", "))")
        
        // Ask which project to trigger
        if projects.count == 1 {
            projectName = projects[0]
            print("  Will trigger workflow for: \(projectName!)")
        } else {
            print("")
            let selectedProject = promptInput(
                question: "Which project to trigger first? (\(projects.joined(separator: ", ")))",
                defaultValue: projects[0]
            )
            if !projects.contains(selectedProject) {
                print("  Warning: '\(selectedProject)' not found in projects list")
            }
            projectName = selectedProject
        }
        
        // Get base branch from project config or prompt
        let configFile = (projectsDir as NSString).appendingPathComponent("\(projectName!)/configuration.yml")
        var configBaseBranch = "main"
        if FileManager.default.fileExists(atPath: configFile) {
            if let content = try? String(contentsOfFile: configFile, encoding: .utf8) {
                for line in content.components(separatedBy: "\n") {
                    if line.hasPrefix("baseBranch:") {
                        configBaseBranch = String(line.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
        }
        
        print("")
        baseBranch = promptInput(question: "Base branch for this project", defaultValue: configBaseBranch)
    }
    
    print("""

  IMPORTANT: Before ClaudeChain can run, the workflow files must be on your
  repository's default branch (usually 'main').

  Current status:
    - Workflow file: .github/workflows/claudechain.yml
    - Projects: \(projects.count) found
    - Target base branch: \(baseBranch)
""")
    
    let choice = promptMenu(
        title: "How would you like to deploy?",
        options: [
            ("Create a Pull Request", "Create a PR to merge project files to the base branch"),
            ("Push directly", "Push directly to the base branch (if you have permission)")
        ]
    )
    
    let workflowName = getWorkflowName(repoPath: repoPath)
    
    if choice == 0 {
        // PR flow
        print("""

  To deploy via Pull Request:

  1. Commit your changes (if not already committed):
     cd \(repoPath)
     git add .
     git commit -m "Add ClaudeChain configuration"

  2. Push to a feature branch:
     git push origin HEAD

  3. Create a Pull Request on GitHub against your base branch ('\(baseBranch)')
     Note: The base branch is where ClaudeChain will merge its generated PRs.

  4. Merge the Pull Request

  After merging, the workflow will be available to trigger.
""")
        if let projectName = projectName {
            print("""

  Once merged, you can trigger the workflow:
    - Go to GitHub -> Actions -> \(workflowName) -> Run workflow
    - Or run: gh workflow run "\(workflowName)" --ref \(baseBranch) -f project_name=\(projectName) -f base_branch=\(baseBranch)
""")
        }
    } else {
        // Direct push flow
        print("""

  To push directly:

  1. Commit your changes (if not already committed):
     cd \(repoPath)
     git add .
     git commit -m "Add ClaudeChain configuration"

  2. Push to the base branch ('\(baseBranch)'):
     git push origin \(baseBranch)

  Note: The base branch is where ClaudeChain will merge its generated PRs.
""")
        
        if let projectName = projectName {
            print("""

  Once pushed, you can trigger the first workflow run.
""")
            if promptYesNo(question: "  Would you like me to trigger the workflow now?", defaultValue: true) {
                try await runFirstWorkflow(repoPath: repoPath, workflowName: workflowName, projectName: projectName, baseBranch: baseBranch)
            } else {
                print("""

  You can trigger it later:
    - Go to GitHub -> Actions -> \(workflowName) -> Run workflow
    - Or run: gh workflow run "\(workflowName)" --ref \(baseBranch) -f project_name=\(projectName) -f base_branch=\(baseBranch)
""")
            }
        }
    }
    
    print("\n" + String(repeating: "=", count: 50))
    print("Deploy Complete!")
    print(String(repeating: "=", count: 50))
    print("""

After the first workflow run, ClaudeChain will automatically:
  - Create a PR for each task in your spec.md
  - Trigger the next task when you merge a PR
  - Mark tasks as complete in spec.md

Happy automating!
""")
    
    return 0
}

/// Trigger the first workflow run
private func runFirstWorkflow(repoPath: String, workflowName: String, projectName: String, baseBranch: String) async throws {
    let command = [
        "gh", "workflow", "run", workflowName,
        "--ref", baseBranch,
        "-f", "project_name=\(projectName)",
        "-f", "base_branch=\(baseBranch)"
    ]
    let commandStr = command.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    
    print("""

  I'll run this command:
    \(commandStr)
""")
    
    if promptYesNo(question: "  Proceed?", defaultValue: true) {
        print("\n  Running workflow...")
        do {
            let cliClient = CLIClient()
            let result = try await cliClient.execute(
                command: command[0],
                arguments: Array(command.dropFirst()),
                workingDirectory: ".",
                environment: nil,
                printCommand: false
            )
            if result.exitCode != 0 {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw CLIClientError.executionFailed(
                    command: command.joined(separator: " "),
                    exitCode: result.exitCode,
                    output: stderr.isEmpty ? result.stdout : stderr
                )
            }
            print("  Workflow triggered successfully!")
            print("\n  Check the Actions tab in GitHub to monitor progress.")
        } catch {
            if let nsError = error as NSError? {
                print("  Error triggering workflow: \(nsError.localizedDescription)")
            } else {
                print("  Error triggering workflow: \(error)")
            }
            print("\n  You can try running this manually:")
            print("    cd \(repoPath)")
            print("    \(commandStr)")
        }
    } else {
        print("  Skipped. You can run it later with:")
        print("    \(commandStr)")
    }
}

// MARK: - Workflow File Creation

/// Create the main ClaudeChain workflow file
private func createWorkflowFile(repoPath: String) throws {
    let workflowsDir = (repoPath as NSString).appendingPathComponent(".github/workflows")
    try FileManager.default.createDirectory(atPath: workflowsDir, withIntermediateDirectories: true, attributes: nil)
    
    let workflowContent = """
name: ClaudeChain

on:
  workflow_dispatch:
    inputs:
      project_name:
        description: 'Project name (folder under claude-chain/)'
        required: true
        type: string
      base_branch:
        description: 'Base branch for PR'
        required: true
        type: string
        default: 'main'
  pull_request:
    types: [closed]
    paths:
      - 'claude-chain/**'

permissions:
  contents: write
  pull-requests: write
  actions: read

jobs:
  run-claudechain:
    runs-on: ubuntu-latest
    steps:
      - uses: gestrich/claude-chain@main
        with:
          anthropic_api_key: ${{ secrets.CLAUDE_CHAIN_ANTHROPIC_API_KEY }}
          github_token: ${{ github.token }}
          project_name: ${{ github.event.inputs.project_name || '' }}
          default_base_branch: ${{ github.event.inputs.base_branch || 'main' }}
          claude_allowed_tools: 'Read,Write,Edit,Bash(git add:*),Bash(git commit:*)'
          # slack_webhook_url: ${{ secrets.CLAUDE_CHAIN_SLACK_WEBHOOK_URL }}
"""
    
    let workflowPath = (workflowsDir as NSString).appendingPathComponent("claudechain.yml")
    try workflowContent.write(toFile: workflowPath, atomically: true, encoding: .utf8)
}

/// Create the statistics workflow file
private func createStatisticsWorkflow(repoPath: String) throws {
    let workflowsDir = (repoPath as NSString).appendingPathComponent(".github/workflows")
    try FileManager.default.createDirectory(atPath: workflowsDir, withIntermediateDirectories: true, attributes: nil)
    
    let workflowContent = """
name: ClaudeChain Statistics

on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 9 AM UTC
  workflow_dispatch:

permissions:
  contents: read
  actions: read
  pull-requests: read

jobs:
  statistics:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: gestrich/claude-chain/statistics@main
        with:
          workflow_file: 'claudechain.yml'
          github_token: ${{ github.token }}
          days_back: 7
          slack_webhook_url: ${{ secrets.CLAUDE_CHAIN_SLACK_WEBHOOK_URL }}
"""
    
    let workflowPath = (workflowsDir as NSString).appendingPathComponent("claudechain-statistics.yml")
    try workflowContent.write(toFile: workflowPath, atomically: true, encoding: .utf8)
}