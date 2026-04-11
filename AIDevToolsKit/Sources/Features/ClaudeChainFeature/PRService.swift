import ClaudeChainService
import ClaudeChainSDK
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class PRService {
    private let repo: String

    public init(repo: String) {
        self.repo = repo
    }
    
    // MARK: - Public API methods
    
    public func getProjectPrs(projectName: String, state: String = "all", label: String = "claudechain") -> [GitHubPullRequest] {
        print("Fetching PRs for project '\(projectName)' with state='\(state)' and label='\(label)'")
        
        // Fetch PRs with the label using GitHub API
        do {
            let allPrs = try Self.fetchPullRequests(repo: repo, state: state, label: label, limit: 100)
            
            // Filter to only PRs whose branch names match the exact project name.
            // We parse each branch name to extract the project name precisely,
            // avoiding false matches when one project name is a prefix of another
            // (e.g., "auth" should not match "auth-api" branches).
            let projectPrs = allPrs.filter { pr in
                guard let headRefName = pr.headRefName,
                      let parsed = BranchInfo.fromBranchName(headRefName) else {
                    return false
                }
                return parsed.projectName == projectName
            }
            
            print("Found \(projectPrs.count) PR(s) for project '\(projectName)' (out of \(allPrs.count) total)")
            return projectPrs
        } catch {
            print("Warning: Failed to list PRs: \(error)")
            return []
        }
    }
    
    public func getOpenPrsForProject(project: String, label: String = "claudechain") -> [GitHubPullRequest] {
        return getProjectPrs(projectName: project, state: "open", label: label)
    }
    
    public func getMergedPrsForProject(project: String, label: String = "claudechain", daysBack: Int = Constants.defaultStatsDaysBack) -> [GitHubPullRequest] {
        let allMerged = getProjectPrs(projectName: project, state: "merged", label: label)
        
        // Filter by merge date
        let cutoff = Date().addingTimeInterval(-Double(daysBack * 24 * 60 * 60))
        let recentMerged = allMerged.filter { pr in
            guard let mergedAt = pr.mergedAt else { return false }
            return mergedAt >= cutoff
        }
        
        return recentMerged
    }
    
    public func getAllPrs(label: String = "claudechain", state: String = "all", limit: Int = 500) -> [GitHubPullRequest] {
        do {
            return try Self.fetchPullRequests(repo: repo, state: state, label: label, limit: limit)
        } catch {
            print("Warning: Failed to list all PRs: \(error)")
            return []
        }
    }
    
    public func getUniqueProjects(label: String = "claudechain") -> [String: String] {
        let allPrs = getAllPrs(label: label)
        
        // Sort by created_at descending so we process newest PRs first
        let allPrsSorted = allPrs.sorted { $0.createdAt > $1.createdAt }
        
        var projects: [String: String] = [:]
        for pr in allPrsSorted {
            guard let headRefName = pr.headRefName,
                  let baseRefName = pr.baseRefName,
                  let parsed = PRService.parseBranchName(branch: headRefName) else {
                continue
            }
            
            let projectName = parsed.projectName
            // Keep the newest PR's base branch for each project.
            // Old PRs may have targeted different branches before the project
            // was moved to its current base branch.
            if projects[projectName] == nil {
                projects[projectName] = baseRefName
            }
        }
        
        return projects
    }
    
    // MARK: - Static utility methods
    
    public static func formatBranchName(projectName: String, taskHash: String) -> String {
        return formatBranchNameWithHash(projectName: projectName, taskHash: taskHash)
    }
    
    public static func formatBranchNameWithHash(projectName: String, taskHash: String) -> String {
        return "claude-chain-\(projectName)-\(taskHash)"
    }
    
    public static func parseBranchName(branch: String) -> BranchInfo? {
        return BranchInfo.fromBranchName(branch)
    }

    // MARK: - Private

    /// Fetch pull requests from the GitHub REST API.
    ///
    /// Uses the token from GH_TOKEN or GITHUB_TOKEN environment variables.
    private static func fetchPullRequests(
        repo: String,
        state: String,
        label: String?,
        limit: Int
    ) throws -> [GitHubPullRequest] {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"] else {
            throw GitHubAPIError("No GH_TOKEN or GITHUB_TOKEN environment variable set")
        }
        guard repo.split(separator: "/").count == 2,
              let url = URL(string: "https://api.github.com/repos/\(repo)/pulls?state=\(state)&per_page=\(min(limit, 100))") else {
            throw GitHubAPIError("Invalid repository slug: \(repo)")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        var responseData: Data?
        var responseError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let responseError {
            throw GitHubAPIError("HTTP request failed: \(responseError.localizedDescription)")
        }
        guard let data = responseData,
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let prs = jsonArray.compactMap { prDict -> GitHubPullRequest? in
            // GitHub REST API uses snake_case; map to camelCase for fromDict
            var mapped: [String: Any] = [
                "number": prDict["number"] as? Int ?? 0,
                "title": prDict["title"] as? String ?? "",
                "state": (prDict["merged_at"] != nil ? "merged" : prDict["state"]) as Any,
                "url": prDict["html_url"] as? String ?? "",
                "createdAt": prDict["created_at"] as? String ?? "",
                "headRefName": (prDict["head"] as? [String: Any])?["ref"] as? String as Any,
                "baseRefName": (prDict["base"] as? [String: Any])?["ref"] as? String as Any,
            ]
            if let mergedAt = prDict["merged_at"] {
                mapped["mergedAt"] = mergedAt
            }
            let assigneeArray = (prDict["assignees"] as? [[String: Any]] ?? [])
                .compactMap { $0["login"] as? String }
                .map { ["login": $0] as [String: Any] }
            mapped["assignees"] = assigneeArray
            mapped["labels"] = (prDict["labels"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
                .map { ["name": $0] as [String: Any] }
            return GitHubPullRequest.fromDict(mapped)
        }

        // Apply label filter post-fetch (REST API label filter requires exact match)
        if let label {
            return prs.filter { $0.labels.contains(label) }
        }
        return prs
    }
}