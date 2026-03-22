import Testing
@testable import EvalService

@Suite("PromptBuilder")
struct PromptBuilderTests {

    let builder = PromptBuilder()

    @Test func usesPromptFieldDirectly() throws {
        let evalCase = EvalCase(id: "p1", prompt: "Do the thing.")
        let result = try builder.buildPrimaryPrompt(for: evalCase)
        #expect(result == "Do the thing.")
    }

    @Test func taskInputWithSkillShouldTrigger() throws {
        let evalCase = EvalCase(id: "p2", skills: [SkillAssertion(skill: "design-kit", shouldTrigger: true)], task: "Migrate DK1 colors.", input: "Color.dkColor(.gray1)")
        let prompt = try builder.buildPrimaryPrompt(for: evalCase)
        #expect(prompt.contains("Migrate DK1 colors."))
        #expect(prompt.contains("Color.dkColor(.gray1)"))
        #expect(prompt.contains("most relevant repository skill"))
    }

    @Test func taskInputNoSkills() throws {
        let evalCase = EvalCase(id: "p4", task: "Fix this.", input: "broken code")
        let prompt = try builder.buildPrimaryPrompt(for: evalCase)
        #expect(!prompt.contains("skill"))
        #expect(!prompt.contains("most relevant"))
    }

    @Test func editModeTask() throws {
        let evalCase = EvalCase(id: "e1", mode: .edit, task: "Add a feature flag.")
        let prompt = try builder.buildPrimaryPrompt(for: evalCase)
        #expect(prompt.contains("Make the requested changes directly by editing files"))
        #expect(prompt.contains("summary of what you changed"))
        #expect(!prompt.contains("Return only the transformed snippet"))
        #expect(!prompt.contains("Snippet:"))
    }

    @Test func editModeIgnoresInput() throws {
        let evalCase = EvalCase(id: "e2", mode: .edit, task: "Fix this.", input: "broken code")
        let prompt = try builder.buildPrimaryPrompt(for: evalCase)
        #expect(prompt.contains("Make the requested changes directly by editing files"))
        #expect(!prompt.contains("broken code"))
        #expect(!prompt.contains("Snippet:"))
    }

    @Test func structuredModeIsDefault() throws {
        let evalCase = EvalCase(id: "s1", task: "Do something.", input: "some code")
        let prompt = try builder.buildPrimaryPrompt(for: evalCase)
        #expect(prompt.contains("Return only the transformed snippet"))
        #expect(!prompt.contains("Make the requested changes directly"))
    }

    @Test func missingTaskAndInputThrows() throws {
        let evalCase = EvalCase(id: "bad_case")
        #expect(throws: PromptBuilderError.missingTaskAndInput) {
            try builder.buildPrimaryPrompt(for: evalCase)
        }
    }
}
