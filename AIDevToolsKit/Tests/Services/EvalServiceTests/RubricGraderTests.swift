import Testing
@testable import EvalService

@Suite("RubricGrader")
struct RubricGraderTests {

    let grader = RubricGrader()

    // MARK: - Overall Pass

    @Test func overallPassTrue() {
        let evalCase = EvalCase(id: "r1", rubric: RubricConfig(prompt: "grade", requireOverallPass: true))
        let payload = RubricPayload(overallPass: true, score: 90, checks: [])
        let errors = grader.grade(case: evalCase, rubricPayload: payload)
        #expect(errors.isEmpty)
    }

    @Test func overallPassFalseFails() {
        let evalCase = EvalCase(id: "r2", rubric: RubricConfig(prompt: "grade", requireOverallPass: true))
        let payload = RubricPayload(overallPass: false, score: 0, checks: [])
        let errors = grader.grade(case: evalCase, rubricPayload: payload)
        #expect(errors.contains(where: { $0.contains("overall_pass=false") }))
    }

    // MARK: - Min Score

    @Test func minScorePasses() {
        let evalCase = EvalCase(id: "r3", rubric: RubricConfig(prompt: "grade", minScore: 80))
        let payload = RubricPayload(overallPass: true, score: 85, checks: [])
        let errors = grader.grade(case: evalCase, rubricPayload: payload)
        #expect(errors.isEmpty)
    }

    @Test func minScoreFails() {
        let evalCase = EvalCase(id: "r4", rubric: RubricConfig(prompt: "grade", minScore: 80))
        let payload = RubricPayload(overallPass: true, score: 50, checks: [])
        let errors = grader.grade(case: evalCase, rubricPayload: payload)
        #expect(errors.contains(where: { $0.contains("score below threshold") }))
    }

    // MARK: - Required Check IDs

    @Test func requiredCheckIdsPass() {
        let evalCase = EvalCase(id: "r5", rubric: RubricConfig(prompt: "grade", requiredCheckIds: ["import", "gate"]))
        let payload = RubricPayload(overallPass: true, score: 100, checks: [
            RubricCheck(id: "import", pass: true, notes: "ok"),
            RubricCheck(id: "gate", pass: true, notes: "ok"),
        ])
        let errors = grader.grade(case: evalCase, rubricPayload: payload)
        #expect(errors.isEmpty)
    }

    @Test func requiredCheckIdMissing() {
        let evalCase = EvalCase(id: "r6", rubric: RubricConfig(prompt: "grade", requiredCheckIds: ["import", "gate"]))
        let payload = RubricPayload(overallPass: true, score: 100, checks: [
            RubricCheck(id: "import", pass: true, notes: "ok"),
        ])
        let errors = grader.grade(case: evalCase, rubricPayload: payload)
        #expect(errors.contains(where: { $0.contains("missing rubric check id: gate") }))
    }

    @Test func requiredCheckIdFails() {
        let evalCase = EvalCase(id: "r7", rubric: RubricConfig(prompt: "grade", requiredCheckIds: ["import"]))
        let payload = RubricPayload(overallPass: true, score: 100, checks: [
            RubricCheck(id: "import", pass: false, notes: "nope"),
        ])
        let errors = grader.grade(case: evalCase, rubricPayload: payload)
        #expect(errors.contains(where: { $0.contains("rubric check failed: import") }))
    }

    // MARK: - gradeFromJSON — checks not a list

    @Test func checksNotListFails() {
        let evalCase = EvalCase(id: "r8", rubric: RubricConfig(prompt: "grade"))
        let payload: [String: JSONValue] = [
            "overall_pass": .bool(true),
            "score": .int(100),
            "checks": .string("bad"),
        ]
        let errors = grader.gradeFromJSON(case: evalCase, rubricPayload: payload)
        #expect(errors.contains(where: { $0.contains("checks is not a list") }))
    }
}
