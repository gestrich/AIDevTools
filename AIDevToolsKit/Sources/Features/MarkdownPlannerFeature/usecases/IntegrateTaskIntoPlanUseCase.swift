import AIOutputSDK
import Foundation
import UseCaseSDK

public struct IntegrateTaskIntoPlanUseCase: UseCase {

    public struct Options: Sendable {
        public let planPath: URL
        public let repoPath: URL?
        public let taskDescriptions: [String]

        public init(planPath: URL, repoPath: URL?, taskDescriptions: [String]) {
            self.planPath = planPath
            self.repoPath = repoPath
            self.taskDescriptions = taskDescriptions
        }
    }

    public enum IntegrateError: Error, LocalizedError {
        case planNotFound(String)
        case noTasks
        case integrationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .planNotFound(let path):
                return "Plan file not found: \(path)"
            case .noTasks:
                return "No task descriptions provided"
            case .integrationFailed(let detail):
                return "Failed to integrate task into plan: \(detail)"
            }
        }
    }

    private static let resultSchema = """
    {"type":"object","properties":{"success":{"type":"boolean","description":"Whether the tasks were successfully integrated into the plan"}},"required":["success"]}
    """

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(_ options: Options) async throws -> Bool {
        guard !options.taskDescriptions.isEmpty else {
            throw IntegrateError.noTasks
        }

        guard FileManager.default.fileExists(atPath: options.planPath.path) else {
            throw IntegrateError.planNotFound(options.planPath.path)
        }

        let planContent = try String(contentsOf: options.planPath, encoding: .utf8)

        let taskList = options.taskDescriptions.enumerated().map { index, desc in
            "- Task \(index + 1): \(desc)"
        }.joined(separator: "\n")

        let prompt = """
        You are modifying an existing phased implementation plan to integrate new task(s) requested by the user.

        Plan file: \(options.planPath.path)

        Current plan content:
        ---
        \(planContent)
        ---

        New task(s) to integrate:
        \(taskList)

        Integration rules:
        1. Read and understand the plan's structure, background, and existing phases
        2. Integrate the new task(s) into the appropriate place — this could be:
           - A new phase inserted at the right position
           - Merged into an existing uncompleted phase if closely related
           - Adjustments to the validation phase to cover the new task
        3. NEVER modify completed phases (those marked with `[x]`)
        4. Preserve the existing plan format:
           - Phase heading style: `## - [ ] Phase N: Short Description`
           - Include `**Skills to read**: ...` when relevant
           - Maintain the background section and skills table unchanged
        5. Renumber phases as needed so numbering is sequential with no gaps
        6. Keep total phases ≤ 10
        7. The final phase should remain a Validation phase
        8. Stay focused — only add what's needed for the new task(s), don't restructure existing phases

        Write the updated plan content back to \(options.planPath.path).

        Return success: true if the integration was completed successfully, false otherwise.
        """

        let aiOptions = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: options.repoPath?.path
        )

        let output = try await client.runStructured(
            PhaseResult.self,
            prompt: prompt,
            jsonSchema: Self.resultSchema,
            options: aiOptions,
            onOutput: nil
        )

        return output.value.success
    }
}
