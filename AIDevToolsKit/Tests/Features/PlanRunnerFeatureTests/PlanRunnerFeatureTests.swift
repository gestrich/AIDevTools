import Testing
import Foundation
@testable import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK

@Suite("PlanRunnerFeature Models")
struct PlanRunnerFeatureModelTests {

    // MARK: - PhaseStatus

    @Test("PhaseStatus isCompleted returns true for completed status")
    func phaseStatusCompleted() {
        let status = PhaseStatus(description: "Do something", status: "completed")
        #expect(status.isCompleted)
    }

    @Test("PhaseStatus isCompleted returns false for pending status")
    func phaseStatusPending() {
        let status = PhaseStatus(description: "Do something", status: "pending")
        #expect(!status.isCompleted)
    }

    @Test("PhaseStatus isCompleted returns false for in_progress status")
    func phaseStatusInProgress() {
        let status = PhaseStatus(description: "Do something", status: "in_progress")
        #expect(!status.isCompleted)
    }

    @Test("PhaseStatusResponse decodes from JSON")
    func phaseStatusResponseDecoding() throws {
        let json = """
        {
            "phases": [
                {"description": "Phase 1", "status": "completed"},
                {"description": "Phase 2", "status": "pending"}
            ],
            "nextPhaseIndex": 1
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PhaseStatusResponse.self, from: data)
        #expect(response.phases.count == 2)
        #expect(response.phases[0].isCompleted)
        #expect(!response.phases[1].isCompleted)
        #expect(response.nextPhaseIndex == 1)
    }

    @Test("PhaseStatusResponse decodes with nextPhaseIndex -1 when all complete")
    func phaseStatusResponseAllComplete() throws {
        let json = """
        {
            "phases": [
                {"description": "Phase 1", "status": "completed"}
            ],
            "nextPhaseIndex": -1
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PhaseStatusResponse.self, from: data)
        #expect(response.nextPhaseIndex == -1)
    }

    // MARK: - RepoMatch

    @Test("RepoMatch decodes from JSON")
    func repoMatchDecoding() throws {
        let json = """
        {"repoId": "my-app", "interpretedRequest": "Add dark mode toggle"}
        """
        let data = Data(json.utf8)
        let match = try JSONDecoder().decode(RepoMatch.self, from: data)
        #expect(match.repoId == "my-app")
        #expect(match.interpretedRequest == "Add dark mode toggle")
    }

    @Test("RepoMatch round-trips through encoding")
    func repoMatchRoundTrip() throws {
        let original = RepoMatch(repoId: "test", interpretedRequest: "Fix the bug")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepoMatch.self, from: data)
        #expect(decoded.repoId == original.repoId)
        #expect(decoded.interpretedRequest == original.interpretedRequest)
    }

    // MARK: - GeneratedPlan

    @Test("GeneratedPlan decodes from JSON")
    func generatedPlanDecoding() throws {
        let json = """
        {"planContent": "## My Plan\\n\\nSome content", "filename": "add-dark-mode"}
        """
        let data = Data(json.utf8)
        let plan = try JSONDecoder().decode(GeneratedPlan.self, from: data)
        #expect(plan.planContent.contains("My Plan"))
        #expect(plan.filename == "add-dark-mode")
    }

    // MARK: - PhaseResult

    @Test("PhaseResult decodes success true")
    func phaseResultSuccess() throws {
        let json = """
        {"success": true}
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(PhaseResult.self, from: data)
        #expect(result.success)
    }

    @Test("PhaseResult decodes success false")
    func phaseResultFailure() throws {
        let json = """
        {"success": false}
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(PhaseResult.self, from: data)
        #expect(!result.success)
    }

    // MARK: - GeneratePlanUseCase

    @Test("GeneratePlanUseCase.Options stores all fields")
    func generatePlanOptions() {
        let repos: [RepositoryInfo] = []
        let options = GeneratePlanUseCase.Options(
            voiceText: "add a button",
            repositories: repos,
            resolveProposedDirectory: { repo in repo.path.appendingPathComponent(PlanRepoSettings.defaultProposedDirectory) }
        )
        #expect(options.voiceText == "add a button")
        #expect(options.repositories.isEmpty)
    }

    // MARK: - ExecutePlanUseCase

    @Test("ExecutePlanUseCase.Options has correct defaults")
    func executePlanOptionsDefaults() {
        let options = ExecutePlanUseCase.Options(
            planPath: URL(fileURLWithPath: "/tmp/plan.md")
        )
        #expect(options.maxMinutes == 90)
        #expect(options.repoPath == nil)
        #expect(options.repository == nil)
        #expect(options.completedDirectory == nil)
        #expect(!options.useWorktree)
    }

    @Test("ExecutePlanUseCase.ExecuteError describes phase failure")
    func executeErrorDescription() {
        let error = ExecutePlanUseCase.ExecuteError.phaseFailed(index: 2, description: "Build the widget", underlyingError: "build failed")
        #expect(error.localizedDescription.contains("Phase 3"))
        #expect(error.localizedDescription.contains("Build the widget"))
    }

    @Test("ExecutePlanUseCase.ExecuteError describes plan not found")
    func executeErrorPlanNotFound() {
        let error = ExecutePlanUseCase.ExecuteError.planNotFound("/tmp/missing.md")
        #expect(error.localizedDescription.contains("/tmp/missing.md"))
    }
}
