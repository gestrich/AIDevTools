import Foundation
import EvalService

public struct RubricEvaluator: Sendable {

    private let promptBuilder: PromptBuilder
    private let rubricGrader: RubricGrader

    public init(
        promptBuilder: PromptBuilder = PromptBuilder(),
        rubricGrader: RubricGrader = RubricGrader()
    ) {
        self.promptBuilder = promptBuilder
        self.rubricGrader = rubricGrader
    }

    public func evaluate(
        rubric: RubricConfig,
        evalCase: EvalCase,
        caseId: String,
        resultText: String,
        adapter: any ProviderAdapterProtocol,
        rubricSchemaPath: URL,
        artifactsDirectory: URL,
        provider: Provider,
        model: String?,
        repoRoot: URL
    ) async throws -> [String] {
        let rubricPrompt = promptBuilder.renderTemplate(
            rubric.prompt,
            case: evalCase,
            resultText: resultText,
            repoRoot: repoRoot
        )

        let schemaPath: URL
        if let customSchemaPath = rubric.schemaPath {
            schemaPath = repoRoot.appendingPathComponent(customSchemaPath)
        } else {
            schemaPath = rubricSchemaPath
        }

        let configuration = RunConfiguration(
            prompt: rubricPrompt,
            outputSchemaPath: schemaPath,
            artifactsDirectory: artifactsDirectory,
            provider: provider,
            caseId: "\(caseId).rubric",
            model: model,
            workingDirectory: repoRoot
        )

        let result = try await adapter.run(configuration: configuration)

        if let error = result.error {
            return ["rubric provider error: \(error.message)"]
        }

        guard let rubricOutput = result.structuredOutput else {
            return ["rubric returned no structured output"]
        }

        return rubricGrader.gradeFromJSON(case: evalCase, rubricPayload: rubricOutput)
    }
}
