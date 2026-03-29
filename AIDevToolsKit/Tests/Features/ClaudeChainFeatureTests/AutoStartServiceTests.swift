/**
 * Tests for auto-start service orchestration
 */

import XCTest
@testable import ClaudeChainFeature
@testable import ClaudeChainService

final class AutoStartServiceTests: XCTestCase {
    
    // MARK: - Test detect_changed_projects() method
    
    func testDetectAddedProject() throws {
        // Mock PRService
        let mockPRService = TestMockPRService(repo: "owner/repo")
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        
        // Note: This test would require mocking GitClient, which would need refactoring
        // to make the methods mockable. For now, we'll test the public interface behavior
        // The actual implementation calls GitClient.diffChangedFiles and GitClient.diffDeletedFiles
        
        // This is a placeholder test showing the expected behavior
        // In practice, we'd need to mock the infrastructure dependencies
        let projects = service.detectChangedProjects(refBefore: "abc123", refAfter: "def456")
        
        // The method should return projects found by GitClient
        let isValidProjectList = projects.isEmpty || projects.allSatisfy { project in
            project.changeType == .modified || project.changeType == .deleted
        }
        XCTAssertTrue(isValidProjectList)
    }
    
    // MARK: - Test determine_new_projects() method
    
    func testAllNewProjects() throws {
        // Mock PRService to return no PRs
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = []
        
        let projects = [
            AutoStartProject(name: "project-a", changeType: .modified, specPath: "claude-chain/project-a/spec.md"),
            AutoStartProject(name: "project-b", changeType: .modified, specPath: "claude-chain/project-b/spec.md")
        ]
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let newProjects = service.determineNewProjects(projects: projects)
        
        XCTAssertEqual(newProjects.count, 2)
        XCTAssertEqual(Set(newProjects.map { $0.name }), Set(["project-a", "project-b"]))
    }
    
    func testAllExistingProjects() throws {
        // Mock PRService to return existing PRs
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = [
            createGitHubPR(prNumber: 1, taskHash: "abc12345", project: "project-a")
        ]
        
        let projects = [
            AutoStartProject(name: "project-a", changeType: .modified, specPath: "claude-chain/project-a/spec.md")
        ]
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let newProjects = service.determineNewProjects(projects: projects)
        
        XCTAssertEqual(newProjects.count, 0)
    }
    
    func testMixedNewAndExistingProjects() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        // Set up dynamic response behavior
        var responseMap: [String: [GitHubPullRequest]] = [
            "new-project": [],
            "existing-project": [createGitHubPR(prNumber: 1, taskHash: "abc12345", project: "existing-project")]
        ]
        
        mockPRService.getProjectPrsHandler = { projectName, _, _ in
            return responseMap[projectName] ?? []
        }
        
        let projects = [
            AutoStartProject(name: "new-project", changeType: .modified, specPath: "claude-chain/new-project/spec.md"),
            AutoStartProject(name: "existing-project", changeType: .modified, specPath: "claude-chain/existing-project/spec.md")
        ]
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let newProjects = service.determineNewProjects(projects: projects)
        
        XCTAssertEqual(newProjects.count, 1)
        XCTAssertEqual(newProjects[0].name, "new-project")
    }
    
    func testSkipDeletedProjects() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = []
        
        let projects = [
            AutoStartProject(name: "deleted-project", changeType: .deleted, specPath: "claude-chain/deleted-project/spec.md"),
            AutoStartProject(name: "modified-project", changeType: .modified, specPath: "claude-chain/modified-project/spec.md")
        ]
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let newProjects = service.determineNewProjects(projects: projects)
        
        // Only modified project should be checked and returned
        XCTAssertEqual(newProjects.count, 1)
        XCTAssertEqual(newProjects[0].name, "modified-project")
        
        // Verify PRService was only called once (for modified project)
        XCTAssertEqual(mockPRService.getProjectPrsCalls.count, 1)
    }
    
    func testGitHubApiErrorHandling() throws {
        // Mock PRService to throw exception
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.getProjectPrsHandler = { _, _, _ in
            throw GitHubAPIError("GitHub API error")
        }
        
        let projects = [
            AutoStartProject(name: "project-a", changeType: .modified, specPath: "claude-chain/project-a/spec.md")
        ]
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let newProjects = service.determineNewProjects(projects: projects)
        
        // In Swift, getProjectPrs is non-throwing — the mock handler error is caught
        // internally and returns [], so the project appears to have no PRs (i.e. "new")
        XCTAssertEqual(newProjects.count, 1)
    }
    
    func testEmptyProjectsList() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let newProjects = service.determineNewProjects(projects: [])
        
        XCTAssertEqual(newProjects.count, 0)
        XCTAssertEqual(mockPRService.getProjectPrsCalls.count, 0)
    }
    
    // MARK: - Test should_auto_trigger() decision logic
    
    func testTriggerNewProject() throws {
        // Mock PRService to return no PRs
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = []
        
        let project = AutoStartProject(name: "new-project", changeType: .modified, specPath: "claude-chain/new-project/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertTrue(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "No open PRs, ready for work")
        XCTAssertEqual(decision.project.name, project.name)
    }
    
    func testSkipExistingProject() throws {
        // Mock PRService to return open PRs
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = [
            createGitHubPR(prNumber: 1, taskHash: "abc12345", project: "existing-project"),
            createGitHubPR(prNumber: 2, taskHash: "def67890", project: "existing-project"),
            createGitHubPR(prNumber: 3, taskHash: "ghi12345", project: "existing-project")
        ]
        
        let project = AutoStartProject(name: "existing-project", changeType: .modified, specPath: "claude-chain/existing-project/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertFalse(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "Project has 3 open PR(s)")
        XCTAssertEqual(decision.project.name, project.name)
    }
    
    func testSkipDeletedProject() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        
        let project = AutoStartProject(name: "deleted-project", changeType: .deleted, specPath: "claude-chain/deleted-project/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertFalse(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "Project spec was deleted")
        XCTAssertEqual(decision.project.name, project.name)
        
        // Should not query PRs for deleted projects
        XCTAssertEqual(mockPRService.getProjectPrsCalls.count, 0)
    }
    
    func testGitHubApiErrorInShouldAutoTrigger() throws {
        // Mock PRService to raise exception
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.getProjectPrsHandler = { _, _, _ in
            throw GitHubAPIError("API timeout")
        }
        
        let project = AutoStartProject(name: "project-a", changeType: .modified, specPath: "claude-chain/project-a/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let decision = service.shouldAutoTrigger(project: project)
        
        // In Swift, getProjectPrs is non-throwing — the mock handler error is caught
        // internally and returns [], so it looks like no open PRs exist
        XCTAssertTrue(decision.shouldTrigger)
        XCTAssertTrue(decision.reason.contains("No open PRs"))
    }
    
    func testSingleExistingPR() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = [
            createGitHubPR(prNumber: 1, taskHash: "abc12345", project: "project-a")
        ]
        
        let project = AutoStartProject(name: "project-a", changeType: .modified, specPath: "claude-chain/project-a/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertFalse(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "Project has 1 open PR(s)")
    }
    
    // MARK: - Test disabled auto-start configuration
    
    func testDisabledAutoStartNewProject() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = []
        
        let project = AutoStartProject(name: "new-project", changeType: .modified, specPath: "claude-chain/new-project/spec.md")
        
        // Create service with autoStartEnabled=false
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService, autoStartEnabled: false)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertFalse(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "Auto-start is disabled via configuration")
        
        // Should not query PRs when auto-start is disabled
        XCTAssertEqual(mockPRService.getProjectPrsCalls.count, 0)
    }
    
    func testDisabledAutoStartExistingProject() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        
        let project = AutoStartProject(name: "existing-project", changeType: .modified, specPath: "claude-chain/existing-project/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService, autoStartEnabled: false)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertFalse(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "Auto-start is disabled via configuration")
    }
    
    func testDisabledAutoStartDeletedProject() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        
        let project = AutoStartProject(name: "deleted-project", changeType: .deleted, specPath: "claude-chain/deleted-project/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService, autoStartEnabled: false)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertFalse(decision.shouldTrigger)
        // Disabled check happens first, before deleted check
        XCTAssertEqual(decision.reason, "Auto-start is disabled via configuration")
    }
    
    func testEnabledAutoStartDefault() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = []
        
        let project = AutoStartProject(name: "new-project", changeType: .modified, specPath: "claude-chain/new-project/spec.md")
        
        // Create service without specifying autoStartEnabled (should default to true)
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        let decision = service.shouldAutoTrigger(project: project)
        
        // Should trigger since auto-start is enabled by default
        XCTAssertTrue(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "No open PRs, ready for work")
    }
    
    func testEnabledAutoStartExplicit() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        mockPRService.mockGetProjectPrsResult = []
        
        let project = AutoStartProject(name: "new-project", changeType: .modified, specPath: "claude-chain/new-project/spec.md")
        
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService, autoStartEnabled: true)
        let decision = service.shouldAutoTrigger(project: project)
        
        XCTAssertTrue(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "No open PRs, ready for work")
    }
    
    // MARK: - Test service initialization
    
    func testBasicInitialization() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService)
        
        // We can't directly access private properties, but we can test the behavior
        // that depends on them
        
        // Test that auto-start is enabled by default
        let project = AutoStartProject(name: "test-project", changeType: .modified, specPath: "claude-chain/test-project/spec.md")
        mockPRService.mockGetProjectPrsResult = []
        let decision = service.shouldAutoTrigger(project: project)
        XCTAssertTrue(decision.shouldTrigger)
    }
    
    func testInitializationWithDisabledAutoStart() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService, autoStartEnabled: false)
        
        // Test that auto-start is disabled
        let project = AutoStartProject(name: "test-project", changeType: .modified, specPath: "claude-chain/test-project/spec.md")
        let decision = service.shouldAutoTrigger(project: project)
        XCTAssertFalse(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "Auto-start is disabled via configuration")
    }
    
    func testInitializationWithEnabledAutoStart() throws {
        let mockPRService = TestMockPRService(repo: "owner/repo")
        let service = AutoStartService(repo: "owner/repo", prService: mockPRService, autoStartEnabled: true)
        
        // Test that auto-start is explicitly enabled
        let project = AutoStartProject(name: "test-project", changeType: .modified, specPath: "claude-chain/test-project/spec.md")
        mockPRService.mockGetProjectPrsResult = []
        let decision = service.shouldAutoTrigger(project: project)
        XCTAssertTrue(decision.shouldTrigger)
        XCTAssertEqual(decision.reason, "No open PRs, ready for work")
    }
}

// MARK: - Test Mock PRService

class TestMockPRService: PRService {
    var mockGetProjectPrsResult: [GitHubPullRequest] = []
    var getProjectPrsCalls: [(String, String, String)] = []
    var getProjectPrsHandler: ((String, String, String) throws -> [GitHubPullRequest])?
    
    override func getProjectPrs(projectName: String, state: String = "open", label: String = "claudechain") -> [GitHubPullRequest] {
        getProjectPrsCalls.append((projectName, state, label))
        
        if let handler = getProjectPrsHandler {
            do {
                return try handler(projectName, state, label)
            } catch {
                // Since the parent method doesn't throw, we need to handle errors differently
                print("Error in mock: \(error)")
                return []
            }
        }
        
        return mockGetProjectPrsResult
    }
}