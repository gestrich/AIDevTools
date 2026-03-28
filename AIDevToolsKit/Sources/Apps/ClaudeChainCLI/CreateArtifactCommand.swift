import ArgumentParser
import ClaudeChainService
import ClaudeChainSDK
import Foundation

/// TaskMetadata for artifact creation (matches Python domain model)
public struct ArtifactTaskMetadata {
    public let taskIndex: Int
    public let taskDescription: String
    public let project: String
    public let branchName: String
    public let assignee: String
    public let createdAt: Date
    public let workflowRunId: Int
    public let prNumber: Int
    public let prState: String
    public let aiTasks: [AITask]
    
    public init(
        taskIndex: Int,
        taskDescription: String,
        project: String,
        branchName: String,
        assignee: String,
        createdAt: Date,
        workflowRunId: Int,
        prNumber: Int,
        prState: String = "open",
        aiTasks: [AITask] = []
    ) {
        self.taskIndex = taskIndex
        self.taskDescription = taskDescription
        self.project = project
        self.branchName = branchName
        self.assignee = assignee
        self.createdAt = createdAt
        self.workflowRunId = workflowRunId
        self.prNumber = prNumber
        self.prState = prState
        self.aiTasks = aiTasks
    }
    
    /// Convert to dictionary for JSON serialization
    public func toDict() -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return [
            "task_index": taskIndex,
            "task_description": taskDescription,
            "project": project,
            "branch_name": branchName,
            "assignee": assignee,
            "created_at": dateFormatter.string(from: createdAt),
            "workflow_run_id": workflowRunId,
            "pr_number": prNumber,
            "pr_state": prState,
            "ai_tasks": aiTasks.map { $0.toDict() }
        ]
    }
    
    /// Get total cost from AI tasks
    public func getTotalCost() -> Double {
        return aiTasks.reduce(0) { $0 + $1.costUSD }
    }
}

public struct CreateArtifactCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create-artifact",
        abstract: "Create task metadata artifact with cost data"
    )
    
    public init() {}
    
    public func run() throws {
        let gh = GitHubActions()
        
        // Read parameters from environment variables (matches Python behavior)
        let costBreakdownJson = ProcessInfo.processInfo.environment["COST_BREAKDOWN_JSON"] ?? ""
        let prNumber = ProcessInfo.processInfo.environment["PR_NUMBER"] ?? ""
        let task = ProcessInfo.processInfo.environment["TASK"] ?? ""
        let taskIndex = ProcessInfo.processInfo.environment["TASK_INDEX"] ?? ""
        let taskHash = ProcessInfo.processInfo.environment["TASK_HASH"] ?? ""
        let project = ProcessInfo.processInfo.environment["PROJECT"] ?? ""
        let branchName = ProcessInfo.processInfo.environment["BRANCH_NAME"] ?? ""
        let assignee = ProcessInfo.processInfo.environment["ASSIGNEE"] ?? ""
        let runId = ProcessInfo.processInfo.environment["RUN_ID"] ?? ""
        
        let exitCode = createArtifact(
            gh: gh,
            costBreakdownJson: costBreakdownJson,
            prNumber: prNumber,
            task: task,
            taskIndex: taskIndex,
            taskHash: taskHash,
            project: project,
            branchName: branchName,
            assignee: assignee,
            runId: runId
        )
        
        if exitCode != 0 {
            throw ExitCode.failure
        }
    }
    
    private func createArtifact(
        gh: GitHubActions,
        costBreakdownJson: String,
        prNumber: String,
        task: String,
        taskIndex: String,
        taskHash: String,
        project: String,
        branchName: String,
        assignee: String,
        runId: String
    ) -> Int {
        // Check if we have required metadata for artifact creation
        if taskHash.isEmpty || project.isEmpty || taskIndex.isEmpty || prNumber.isEmpty {
            gh.setNotice(message: "Missing metadata for artifact creation, skipping")
            gh.writeOutput(name: "artifact_path", value: "")
            gh.writeOutput(name: "artifact_name", value: "")
            return 0
        }
        
        if costBreakdownJson.isEmpty {
            gh.setNotice(message: "No cost breakdown provided, skipping artifact creation")
            gh.writeOutput(name: "artifact_path", value: "")
            gh.writeOutput(name: "artifact_name", value: "")
            return 0
        }
        
        do {
            // Parse cost breakdown from JSON
            let costBreakdown = try CostBreakdown.fromJSON(costBreakdownJson)
            let now = Date()
            
            // Create AITask entries from cost breakdown
            var aiTasks: [AITask] = []
            
            // Main task cost
            if costBreakdown.mainCost > 0 {
                // Get the primary model from main execution
                let mainModel = costBreakdown.mainModels.first?.model ?? "claude-sonnet-4"
                
                // Sum tokens from main execution models
                let mainInputTokens = costBreakdown.mainModels.reduce(0) { $0 + $1.inputTokens }
                let mainOutputTokens = costBreakdown.mainModels.reduce(0) { $0 + $1.outputTokens }
                
                aiTasks.append(AITask(
                    type: "PRCreation",
                    model: mainModel,
                    costUSD: costBreakdown.mainCost,
                    createdAt: now,
                    tokensInput: mainInputTokens,
                    tokensOutput: mainOutputTokens
                ))
            }
            
            // Summary task cost
            if costBreakdown.summaryCost > 0 {
                // Get the primary model from summary execution
                let summaryModel = costBreakdown.summaryModels.first?.model ?? "claude-sonnet-4"
                
                // Sum tokens from summary execution models
                let summaryInputTokens = costBreakdown.summaryModels.reduce(0) { $0 + $1.inputTokens }
                let summaryOutputTokens = costBreakdown.summaryModels.reduce(0) { $0 + $1.outputTokens }
                
                aiTasks.append(AITask(
                    type: "PRSummary",
                    model: summaryModel,
                    costUSD: costBreakdown.summaryCost,
                    createdAt: now,
                    tokensInput: summaryInputTokens,
                    tokensOutput: summaryOutputTokens
                ))
            }
            
            // Convert string parameters to appropriate types
            guard let taskIndexInt = Int(taskIndex),
                  let prNumberInt = Int(prNumber) else {
                gh.setWarning(message: "Invalid task_index or pr_number format")
                gh.writeOutput(name: "artifact_path", value: "")
                gh.writeOutput(name: "artifact_name", value: "")
                return 1
            }
            
            let workflowRunIdInt = Int(runId) ?? 0
            
            // Create TaskMetadata
            let metadata = ArtifactTaskMetadata(
                taskIndex: taskIndexInt,
                taskDescription: task,
                project: project,
                branchName: branchName,
                assignee: assignee,
                createdAt: now,
                workflowRunId: workflowRunIdInt,
                prNumber: prNumberInt,
                prState: "open",
                aiTasks: aiTasks
            )
            
            // Write to temp file
            let artifactName = "task-metadata-\(project)-\(taskHash)"
            let artifactFilename = "\(artifactName).json"
            let artifactPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(artifactFilename)
            
            let jsonData = try JSONSerialization.data(withJSONObject: metadata.toDict(), options: [.prettyPrinted])
            try jsonData.write(to: artifactPath)
            
            print("✅ Created task metadata artifact: \(artifactFilename)")
            print("   - Total cost: \(Formatting.formatUSD(metadata.getTotalCost()))")
            print("   - AI tasks: \(aiTasks.count)")
            
            gh.writeOutput(name: "artifact_path", value: artifactPath.path)
            gh.writeOutput(name: "artifact_name", value: artifactName)
            return 0
            
        } catch {
            gh.setWarning(message: "Failed to create task metadata artifact: \(error)")
            gh.writeOutput(name: "artifact_path", value: "")
            gh.writeOutput(name: "artifact_name", value: "")
            return 1
        }
    }
}