import AIOutputSDK
import CLISDK
import Foundation
import PipelineSDK

public struct ReviewStepHandler: StepHandler {
    private let client: any AIClient
    private let cliClient: CLIClient

    private static let reviewSchema = """
    {"type":"object","properties":{"fixes":{"type":"array","items":{"type":"object","properties":{"description":{"type":"string"},"prompt":{"type":"string"}},"required":["description","prompt"]}}},"required":["fixes"]}
    """

    public init(client: any AIClient, cliClient: CLIClient = CLIClient(printOutput: false)) {
        self.client = client
        self.cliClient = cliClient
    }

    public func execute(_ step: ReviewStep, context: PipelineContext) async throws -> [any PipelineStep] {
        let workDir = context.workingDirectory ?? context.repoPath?.path ?? "."
        let diff = await getGitDiff(scope: step.scope, workingDirectory: workDir)

        let prompt = buildReviewPrompt(step: step, diff: diff)
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: context.workingDirectory
        )

        let result = try await client.runStructured(
            ReviewResult.self,
            prompt: prompt,
            jsonSchema: Self.reviewSchema,
            options: options,
            onOutput: nil
        )

        return result.value.fixes.enumerated().map { index, fix in
            CodeChangeStep(
                id: "\(step.id)-fix-\(index)",
                description: fix.description,
                prompt: fix.prompt
            )
        }
    }

    private func buildReviewPrompt(step: ReviewStep, diff: String) -> String {
        """
        \(step.prompt)

        Changes to review:
        \(diff.isEmpty ? "(no changes detected)" : diff)

        Return a JSON list of fixes required. Each fix should have:
        - description: A brief description of what needs to be fixed
        - prompt: A detailed prompt for an AI agent to implement the fix

        Return an empty fixes array if no changes are needed.
        """
    }

    private func getGitDiff(scope: ReviewScope, workingDirectory: String) async -> String {
        let arguments: [String]
        switch scope {
        case .allSinceLastReview:
            arguments = ["diff", "HEAD"]
        case .lastN(let n):
            arguments = ["diff", "HEAD~\(n)...HEAD"]
        case .stepIDs:
            arguments = ["diff", "HEAD"]
        }
        let result = try? await cliClient.execute(
            command: "git",
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        return result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct ReviewResult: Decodable, Sendable {
    let fixes: [Fix]

    struct Fix: Decodable, Sendable {
        let description: String
        let prompt: String
    }
}
