import Testing
import EvalService

enum DesignKitMigrationEvals {
    static let cases: [EvalCase] = [
        EvalCase(
            id: "button-basic",
            suite: "designkit-migration",
            skills: [SkillAssertion(skill: "design-kit-migration", shouldTrigger: true, mustBeInvoked: true)],
            task: "Migrate this SwiftUI view from DesignKit 1.0 to DesignKit 2.0",
            input: """
            Button(action: { save() }) {
                Text("Save")
            }
            .dkType(.primary)
            """,
            mustInclude: ["Button"],
            mustNotInclude: ["dkType"]
        ),
        EvalCase(
            id: "color-replacement",
            suite: "designkit-migration",
            skills: [SkillAssertion(skill: "design-kit-migration", shouldTrigger: true, mustBeInvoked: true)],
            task: "Migrate this SwiftUI view from DesignKit 1.0 to DesignKit 2.0",
            input: """
            Text("Hello")
                .foregroundColor(.dkColor(.gray1))
            """,
            mustInclude: ["Color"],
            mustNotInclude: ["dkColor"]
        ),
    ]
}

@Suite("DesignKit Migration Evals", .tags(.integration), .enabled(if: IntegrationTest.isEnabled))
struct DesignKitMigrationEvalTests {

    @Test(arguments: DesignKitMigrationEvals.cases)
    func evalCase(_ eval: EvalCase) async throws {
        try await runEval(eval)
    }
}
