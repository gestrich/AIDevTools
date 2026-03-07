import Foundation
import Testing
import SkillScannerSDK
@testable import EvalService

@Suite("DeterministicGrader")
struct DeterministicGraderTests {

    let grader = DeterministicGrader()

    func caps(toolEvents: Bool = true) -> ProviderCapabilities {
        ProviderCapabilities(supportsToolEventAssertions: toolEvents)
    }

    // MARK: - Exact Match

    @Test func exactMatchPasses() {
        let evalCase = EvalCase(id: "t1", expected: "Color.gray1")
        let (errors, skips) = grader.grade(case: evalCase, resultText: "Color.gray1", traceCommands: [], providerCapabilities: caps())
        #expect(errors.isEmpty)
        #expect(skips.isEmpty)
    }

    @Test func exactMatchTrailingNewlineNormalizes() {
        let evalCase = EvalCase(id: "t2", expected: "Color.gray1\n")
        let (errors, _) = grader.grade(case: evalCase, resultText: "Color.gray1\n", traceCommands: [], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func exactMismatchFails() {
        let evalCase = EvalCase(id: "t3", expected: "Color.gray1")
        let (errors, _) = grader.grade(case: evalCase, resultText: "Color.blue5", traceCommands: [], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("exact output mismatch") }))
    }

    // MARK: - Must Include

    @Test func mustIncludePasses() {
        let evalCase = EvalCase(id: "t4", mustInclude: ["Color.gray1", "Color.blue5"])
        let (errors, _) = grader.grade(case: evalCase, resultText: "let a = Color.gray1\nlet b = Color.blue5", traceCommands: [], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func mustIncludeFails() {
        let evalCase = EvalCase(id: "t5", mustInclude: ["Color.gray1"])
        let (errors, _) = grader.grade(case: evalCase, resultText: "Color.blue5", traceCommands: [], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("missing required substring") }))
    }

    // MARK: - Must Not Include

    @Test func mustNotIncludePasses() {
        let evalCase = EvalCase(id: "t6", mustNotInclude: ["dkColor"])
        let (errors, _) = grader.grade(case: evalCase, resultText: "Color.gray1", traceCommands: [], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func mustNotIncludeFails() {
        let evalCase = EvalCase(id: "t7", mustNotInclude: ["dkColor"])
        let (errors, _) = grader.grade(case: evalCase, resultText: "Color.dkColor(.gray1)", traceCommands: [], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("found forbidden substring") }))
    }

    // MARK: - Trace Command Contains

    @Test func traceCommandContainsPasses() {
        let evalCase = EvalCase(id: "t8", deterministic: DeterministicChecks(traceCommandContains: ["ls"]))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls -la", "cat file.txt"], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func traceCommandContainsFails() {
        let evalCase = EvalCase(id: "t9", deterministic: DeterministicChecks(traceCommandContains: ["grep"]))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls -la"], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("missing trace command") }))
    }

    // MARK: - Trace Command Not Contains

    @Test func traceCommandNotContainsPasses() {
        let evalCase = EvalCase(id: "t10", deterministic: DeterministicChecks(traceCommandNotContains: ["rm"]))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls -la"], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func traceCommandNotContainsFails() {
        let evalCase = EvalCase(id: "t11", deterministic: DeterministicChecks(traceCommandNotContains: ["rm"]))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["rm -rf /"], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("found forbidden trace command") }))
    }

    // MARK: - Tool Event Capability Gating

    @Test func toolEventChecksSkippedWhenUnsupported() {
        let evalCase = EvalCase(id: "t12", deterministic: DeterministicChecks(traceCommandContains: ["grep"]))
        let (errors, skips) = grader.grade(case: evalCase, resultText: "", traceCommands: [], providerCapabilities: caps(toolEvents: false))
        #expect(errors.isEmpty)
        #expect(!skips.isEmpty)
        #expect(skips[0].lowercased().contains("skipped"))
    }

    // MARK: - Trace Command Order

    @Test func traceCommandOrderPasses() {
        let evalCase = EvalCase(id: "order-1", deterministic: DeterministicChecks(traceCommandOrder: ["npm init", "npm install", "npm run build"]))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["npm init -y", "npm install express", "npm run build"], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func traceCommandOrderFailsWhenOutOfOrder() {
        let evalCase = EvalCase(id: "order-2", deterministic: DeterministicChecks(traceCommandOrder: ["npm init", "npm install"]))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["npm install express", "npm init -y"], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("trace command order violation") }))
    }

    @Test func traceCommandOrderFailsWhenMissing() {
        let evalCase = EvalCase(id: "order-3", deterministic: DeterministicChecks(traceCommandOrder: ["npm init", "npm test"]))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["npm init -y", "npm install"], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("trace command order violation") }))
    }

    @Test func traceCommandOrderSkippedWhenUnsupported() {
        let evalCase = EvalCase(id: "order-4", deterministic: DeterministicChecks(traceCommandOrder: ["npm init", "npm install"]))
        let (errors, skips) = grader.grade(case: evalCase, resultText: "", traceCommands: [], providerCapabilities: caps(toolEvents: false))
        #expect(errors.isEmpty)
        #expect(skips.contains(where: { $0.contains("order") }))
    }

    // MARK: - Max Commands

    @Test func maxCommandsPasses() {
        let evalCase = EvalCase(id: "max-1", deterministic: DeterministicChecks(maxCommands: 5))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls", "cat file.txt", "echo done"], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func maxCommandsFailsWhenExceeded() {
        let evalCase = EvalCase(id: "max-2", deterministic: DeterministicChecks(maxCommands: 2))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls", "cat file.txt", "echo done"], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("exceeded max commands: 3 > 2") }))
    }

    @Test func maxCommandsSkippedWhenUnsupported() {
        let evalCase = EvalCase(id: "max-3", deterministic: DeterministicChecks(maxCommands: 2))
        let (errors, skips) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls", "cat", "echo"], providerCapabilities: caps(toolEvents: false))
        #expect(errors.isEmpty)
        #expect(skips.contains(where: { $0.contains("max commands") }))
    }

    // MARK: - Max Repeated Commands (Thrashing Detection)

    @Test func maxRepeatedCommandsPasses() {
        let evalCase = EvalCase(id: "thrash-1", deterministic: DeterministicChecks(maxRepeatedCommands: 2))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls", "ls", "cat file.txt"], providerCapabilities: caps())
        #expect(errors.isEmpty)
    }

    @Test func maxRepeatedCommandsFailsWhenThrashing() {
        let evalCase = EvalCase(id: "thrash-2", deterministic: DeterministicChecks(maxRepeatedCommands: 2))
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls", "npm install", "npm install", "npm install"], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("thrashing detected") }))
    }

    @Test func maxRepeatedCommandsSkippedWhenUnsupported() {
        let evalCase = EvalCase(id: "thrash-3", deterministic: DeterministicChecks(maxRepeatedCommands: 1))
        let (errors, skips) = grader.grade(case: evalCase, resultText: "", traceCommands: ["ls", "ls"], providerCapabilities: caps(toolEvents: false))
        #expect(errors.isEmpty)
        #expect(skips.contains(where: { $0.contains("max repeated") }))
    }

    // MARK: - Skill Must Be Invoked

    @Test func skillMustBeInvokedPassesWithMatchingToolEvent() {
        // Arrange
        let evalCase = EvalCase(id: "skill-1", deterministic: DeterministicChecks(skillMustBeInvoked: "map-layer"))
        let events = [ToolEvent(name: "Skill", skillName: "map-layer")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func skillMustBeInvokedFailsWhenNoMatchingEvent() {
        // Arrange
        let evalCase = EvalCase(id: "skill-2", deterministic: DeterministicChecks(skillMustBeInvoked: "map-layer"))
        let events = [ToolEvent(name: "Read", filePath: "/some/file.swift")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.contains(where: { $0.contains("skill not invoked") }))
    }

    @Test func skillMustBeInvokedPassesViaTraceCommand() {
        // Arrange
        let evalCase = EvalCase(id: "skill-3", deterministic: DeterministicChecks(skillMustBeInvoked: "map-layer"))
        let traces = ["sed -n '1,220p' .claude/skills/map-layer/SKILL.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps())

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func skillMustBeInvokedPassesViaAgentsTraceCommand() {
        // Arrange
        let evalCase = EvalCase(id: "skill-3b", deterministic: DeterministicChecks(skillMustBeInvoked: "map-layer"))
        let traces = ["cat .agents/skills/map-layer/SKILL.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps())

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func skillMustBeInvokedSkippedWhenUnsupported() {
        // Arrange
        let evalCase = EvalCase(id: "skill-4", deterministic: DeterministicChecks(skillMustBeInvoked: "map-layer"))

        // Act
        let (errors, skips) = grader.grade(case: evalCase, resultText: "", traceCommands: [], providerCapabilities: caps(toolEvents: false))

        // Assert
        #expect(errors.isEmpty)
        #expect(skips.contains(where: { $0.contains("skill invocation") }))
    }

    // MARK: - Skill Must Not Be Invoked

    @Test func skillMustNotBeInvokedPassesWhenAbsent() {
        // Arrange
        let evalCase = EvalCase(id: "skill-5", deterministic: DeterministicChecks(skillMustNotBeInvoked: ["design-kit"]))
        let events = [ToolEvent(name: "Read", filePath: "/some/file.swift")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func skillMustNotBeInvokedFailsWhenPresent() {
        // Arrange
        let evalCase = EvalCase(id: "skill-6", deterministic: DeterministicChecks(skillMustNotBeInvoked: ["design-kit"]))
        let events = [ToolEvent(name: "Skill", skillName: "design-kit")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.contains(where: { $0.contains("skill should not have been invoked") }))
    }

    @Test func skillMustNotBeInvokedFailsViaTraceCommand() {
        // Arrange
        let evalCase = EvalCase(id: "skill-7", deterministic: DeterministicChecks(skillMustNotBeInvoked: ["design-kit"]))
        let traces = ["cat .claude/skills/design-kit/SKILL.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps())

        // Assert
        #expect(errors.contains(where: { $0.contains("skill should not have been invoked") }))
    }

    @Test func skillMustNotBeInvokedFailsViaAgentsTraceCommand() {
        // Arrange
        let evalCase = EvalCase(id: "skill-7b", deterministic: DeterministicChecks(skillMustNotBeInvoked: ["design-kit"]))
        let traces = ["cat .agents/skills/design-kit/SKILL.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps())

        // Assert
        #expect(errors.contains(where: { $0.contains("skill should not have been invoked") }))
    }

    @Test func skillMustBeInvokedPassesWithNestedSkillPath() {
        // Arrange
        let repoRoot = URL(fileURLWithPath: "/Users/test/repo")
        let skills = [
            SkillInfo(name: "merge-insurance-policy", path: URL(fileURLWithPath: "/Users/test/repo/.claude/skills/ios-26/merge-insurance-policy.md"))
        ]
        let evalCase = EvalCase(id: "skill-nested-1", deterministic: DeterministicChecks(skillMustBeInvoked: "merge-insurance-policy"))
        let traces = ["sed -n '1,100p' .claude/skills/ios-26/merge-insurance-policy.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps(), repoRoot: repoRoot, skills: skills)

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func skillMustBeInvokedPassesViaFilePathWithSkillInfo() {
        // Arrange
        let repoRoot = URL(fileURLWithPath: "/Users/test/repo")
        let skills = [
            SkillInfo(name: "merge-insurance-policy", path: URL(fileURLWithPath: "/Users/test/repo/.claude/skills/ios-26/merge-insurance-policy.md"))
        ]
        let evalCase = EvalCase(id: "skill-filePath-1", deterministic: DeterministicChecks(skillMustBeInvoked: "merge-insurance-policy"))
        let events = [
            ToolEvent(name: "Skill", skillName: "ios-26"),
            ToolEvent(name: "Read", filePath: "/Users/test/repo/.claude/skills/ios-26/merge-insurance-policy.md")
        ]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps(), repoRoot: repoRoot, skills: skills)

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func skillMustBeInvokedPassesViaFilePathWithoutSkillInfo() {
        // Arrange — no SkillInfo for the nested skill, only the parent directory is scanned
        let skills = [
            SkillInfo(name: "ios-26", path: URL(fileURLWithPath: "/Users/test/repo/.claude/skills/ios-26"))
        ]
        let evalCase = EvalCase(id: "skill-filePath-2", deterministic: DeterministicChecks(skillMustBeInvoked: "merge-insurance-policy"))
        let events = [
            ToolEvent(name: "Skill", skillName: "ios-26"),
            ToolEvent(name: "Read", filePath: "/Users/test/repo/.claude/skills/ios-26/merge-insurance-policy.md")
        ]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps(), skills: skills)

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func skillMustNotBeInvokedFailsWithNestedSkillPath() {
        // Arrange
        let repoRoot = URL(fileURLWithPath: "/Users/test/repo")
        let skills = [
            SkillInfo(name: "merge-insurance-policy", path: URL(fileURLWithPath: "/Users/test/repo/.claude/skills/ios-26/merge-insurance-policy.md"))
        ]
        let evalCase = EvalCase(id: "skill-nested-3", deterministic: DeterministicChecks(skillMustNotBeInvoked: ["merge-insurance-policy"]))
        let traces = ["sed -n '1,100p' .claude/skills/ios-26/merge-insurance-policy.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps(), repoRoot: repoRoot, skills: skills)

        // Assert
        #expect(errors.contains(where: { $0.contains("skill should not have been invoked") }))
    }

    // MARK: - Reference File Must Be Read

    @Test func referenceFileMustBeReadPassesWithMatchingToolEvent() {
        // Arrange
        let evalCase = EvalCase(id: "ref-1", deterministic: DeterministicChecks(referenceFileMustBeRead: ["feature-layers.md"]))
        let events = [ToolEvent(name: "Read", filePath: "/Users/bill/.claude/skills/map-layer/feature-layers.md")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func referenceFileMustBeReadFailsWhenNotRead() {
        // Arrange
        let evalCase = EvalCase(id: "ref-2", deterministic: DeterministicChecks(referenceFileMustBeRead: ["feature-layers.md"]))
        let events = [ToolEvent(name: "Read", filePath: "/some/other/file.swift")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.contains(where: { $0.contains("reference file not read") }))
    }

    @Test func referenceFileMustBeReadPassesViaTraceCommand() {
        // Arrange
        let evalCase = EvalCase(id: "ref-3", deterministic: DeterministicChecks(referenceFileMustBeRead: ["feature-layers.md"]))
        let traces = ["sed -n '1,260p' .claude/skills/map-layer/feature-layers.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps())

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func referenceFileMustBeReadSkippedWhenUnsupported() {
        // Arrange
        let evalCase = EvalCase(id: "ref-4", deterministic: DeterministicChecks(referenceFileMustBeRead: ["feature-layers.md"]))

        // Act
        let (errors, skips) = grader.grade(case: evalCase, resultText: "", traceCommands: [], providerCapabilities: caps(toolEvents: false))

        // Assert
        #expect(errors.isEmpty)
        #expect(skips.contains(where: { $0.contains("reference file") }))
    }

    // MARK: - Reference File Must Not Be Read

    @Test func referenceFileMustNotBeReadPassesWhenAbsent() {
        // Arrange
        let evalCase = EvalCase(id: "ref-5", deterministic: DeterministicChecks(referenceFileMustNotBeRead: ["master-set-layers.md"]))
        let events = [ToolEvent(name: "Read", filePath: "/Users/bill/.claude/skills/map-layer/feature-layers.md")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func referenceFileMustNotBeReadFailsWhenPresent() {
        // Arrange
        let evalCase = EvalCase(id: "ref-6", deterministic: DeterministicChecks(referenceFileMustNotBeRead: ["master-set-layers.md"]))
        let events = [ToolEvent(name: "Read", filePath: "/Users/bill/.claude/skills/map-layer/master-set-layers.md")]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: [], toolEvents: events, providerCapabilities: caps())

        // Assert
        #expect(errors.contains(where: { $0.contains("reference file should not have been read") }))
    }

    @Test func referenceFileMustNotBeReadFailsViaTraceCommand() {
        // Arrange
        let evalCase = EvalCase(id: "ref-7", deterministic: DeterministicChecks(referenceFileMustNotBeRead: ["master-set-layers.md"]))
        let traces = ["cat .claude/skills/map-layer/master-set-layers.md"]

        // Act
        let (errors, _) = grader.grade(case: evalCase, resultText: "", traceCommands: traces, providerCapabilities: caps())

        // Assert
        #expect(errors.contains(where: { $0.contains("reference file should not have been read") }))
    }

    // MARK: - Should Trigger

    @Test func shouldTriggerTrueRequiresMustInclude() {
        let evalCase = EvalCase(id: "t13", shouldTrigger: true)
        let (errors, _) = grader.grade(case: evalCase, resultText: "anything", traceCommands: [], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("should_trigger=true must define must_include") }))
    }

    @Test func shouldTriggerFalseRequiresMustNotInclude() {
        let evalCase = EvalCase(id: "t14", shouldTrigger: false)
        let (errors, _) = grader.grade(case: evalCase, resultText: "anything", traceCommands: [], providerCapabilities: caps())
        #expect(errors.contains(where: { $0.contains("should_trigger=false must define must_not_include") }))
    }

    @Test func shouldTriggerEditModeSkipsMustIncludeValidation() {
        let evalCase = EvalCase(id: "t15", mode: .edit, shouldTrigger: true)
        let (errors, _) = grader.grade(case: evalCase, resultText: "anything", traceCommands: [], providerCapabilities: caps())
        #expect(!errors.contains(where: { $0.contains("should_trigger=true must define must_include") }))
    }

    // MARK: - Expected Diff

    private let dummyRepoRoot = URL(fileURLWithPath: "/tmp/test-repo")

    @Test func expectedDiffNoDiffPassesWithEmptyDiff() {
        // Arrange
        let evalCase = EvalCase(id: "ed-1", deterministic: DeterministicChecks(expectedDiff: ExpectedDiff(noDiff: true)))

        // Act
        let errors = grader.gradeFileChanges(case: evalCase, diff: "", repoRoot: dummyRepoRoot)

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func expectedDiffNoDiffFailsWithNonEmptyDiff() {
        // Arrange
        let evalCase = EvalCase(id: "ed-2", deterministic: DeterministicChecks(expectedDiff: ExpectedDiff(noDiff: true)))

        // Act
        let errors = grader.gradeFileChanges(case: evalCase, diff: "+added line", repoRoot: dummyRepoRoot)

        // Assert
        #expect(errors.contains(where: { $0.contains("expected no diff but changes were found") }))
    }

    @Test func expectedDiffContainsPassesWithMatchingDiff() {
        // Arrange
        let evalCase = EvalCase(id: "ed-3", deterministic: DeterministicChecks(expectedDiff: ExpectedDiff(contains: ["iOS26DesignEnabled"])))

        // Act
        let errors = grader.gradeFileChanges(case: evalCase, diff: "+iOS26DesignEnabled = true", repoRoot: dummyRepoRoot)

        // Assert
        #expect(errors.isEmpty)
    }

    @Test func expectedDiffContainsFailsWithEmptyDiff() {
        // Arrange
        let evalCase = EvalCase(id: "ed-4", deterministic: DeterministicChecks(expectedDiff: ExpectedDiff(contains: ["iOS26DesignEnabled"])))

        // Act
        let errors = grader.gradeFileChanges(case: evalCase, diff: "", repoRoot: dummyRepoRoot)

        // Assert
        #expect(errors.contains(where: { $0.contains("expected diff but none found") }))
    }

    @Test func expectedDiffNotContainsFailsWhenForbiddenStringPresent() {
        // Arrange
        let evalCase = EvalCase(id: "ed-5", deterministic: DeterministicChecks(expectedDiff: ExpectedDiff(notContains: ["navigationItem.title"])))

        // Act
        let errors = grader.gradeFileChanges(case: evalCase, diff: "+self.navigationItem.title = @\"Settings\"", repoRoot: dummyRepoRoot)

        // Assert
        #expect(errors.contains(where: { $0.contains("found in diff") }))
    }

    @Test func expectedDiffNotContainsPassesWhenAbsent() {
        // Arrange
        let evalCase = EvalCase(id: "ed-6", deterministic: DeterministicChecks(expectedDiff: ExpectedDiff(notContains: ["navigationItem.title"])))

        // Act
        let errors = grader.gradeFileChanges(case: evalCase, diff: "+self.view.backgroundColor = UIColor.white", repoRoot: dummyRepoRoot)

        // Assert
        #expect(errors.isEmpty)
    }
}
