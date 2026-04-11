import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@preconcurrency import OctoKit

public enum OctokitClientError: Error, Sendable, LocalizedError {
    case authenticationFailed
    case notFound(String)
    case rateLimitExceeded
    case requestFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "GitHub authentication failed. Check your token is valid."
        case .notFound(let detail):
            return "GitHub resource not found: \(detail)"
        case .rateLimitExceeded:
            return "GitHub API rate limit exceeded or access forbidden. Check your token permissions."
        case .requestFailed(let detail):
            return "GitHub API request failed: \(detail)"
        case .invalidResponse:
            return "Received an invalid response from GitHub API."
        }
    }
}

// GitHub omits `patch` for renamed files, binary files, and files too large for diff
// generation. OctoKit's `PullRequest.File.patch` is non-optional, causing decode failures.
// Custom struct decodes optional `patch`; `toOctokitFile()` converts via JSON round-tripping
// since `PullRequest.File` has no public initializer.
private struct PullRequestFile: Codable {
    let sha: String
    let filename: String
    let status: PullRequest.File.Status
    let additions: Int
    let deletions: Int
    let changes: Int
    let blobUrl: String
    let rawUrl: String
    let contentsUrl: String
    let patch: String?  // Optional to handle GitHub's actual API behavior
    
    enum CodingKeys: String, CodingKey {
        case sha, filename, status, additions, deletions, changes, patch
        case blobUrl = "blob_url"
        case rawUrl = "raw_url"
        case contentsUrl = "contents_url"
    }
    
    func toOctokitFile() throws -> PullRequest.File {
        let dict: [String: Any] = [
            "sha": sha,
            "filename": filename,
            "status": status.rawValue,
            "additions": additions,
            "deletions": deletions,
            "changes": changes,
            "blob_url": blobUrl,
            "raw_url": rawUrl,
            "contents_url": contentsUrl,
            "patch": patch ?? ""  // Empty string for renamed files without content changes
        ]

        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        return try decoder.decode(PullRequest.File.self, from: data)
    }
}

private struct ReviewCommentResponse: Codable {
    let id: Int
    let body: String
    let path: String
    let line: Int?
    let startLine: Int?
    let position: Int?
    let createdAt: String?
    let htmlUrl: String?
    let inReplyToId: Int?
    let user: ReviewCommentUser?

    struct ReviewCommentUser: Codable {
        let login: String
        let id: Int
    }

    enum CodingKeys: String, CodingKey {
        case id, body, path, line, position, user
        case startLine = "start_line"
        case createdAt = "created_at"
        case htmlUrl = "html_url"
        case inReplyToId = "in_reply_to_id"
    }
}

public struct CheckRun: Codable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
}

public struct CompareResult: Sendable {
    public let mergeBaseCommitSHA: String
}

private struct CompareResponse: Codable {
    let mergeBaseCommit: MergeBaseCommit

    struct MergeBaseCommit: Codable {
        let sha: String
    }

    enum CodingKeys: String, CodingKey {
        case mergeBaseCommit = "merge_base_commit"
    }
}

private struct ContentsMetadata: Codable {
    let sha: String
    let content: String?
    let encoding: String?
}

public struct BranchHead: Codable, Sendable {
    public let commitSHA: String
    public let treeSHA: String
}

public struct GitTreeEntry: Codable, Sendable {
    public let path: String
    public let sha: String
    public let type: String
}

private struct BranchResponse: Codable {
    let commit: CommitData

    struct CommitData: Codable {
        let sha: String
        let commit: CommitDetail

        struct CommitDetail: Codable {
            let tree: TreeRef

            struct TreeRef: Codable {
                let sha: String
            }
        }
    }
}

private struct GitTreeResponse: Codable {
    let tree: [GitTreeEntry]
}

public struct ReviewCommentData: Sendable {
    public let id: Int
    public let body: String
    public let path: String
    public let line: Int?
    public let startLine: Int?
    public let position: Int?
    public let createdAt: String?
    public let htmlUrl: String?
    public let inReplyToId: Int?
    public let userLogin: String?
    public let userId: Int?
}

public struct CreatedPullRequest: Codable, Sendable {
    public let number: Int
    public let htmlURL: String
}

public struct WorkflowRun: Codable, Sendable {
    public let id: Int
    public let status: String
    public let conclusion: String?
    public let headBranch: String?
    public let htmlURL: String?
}

private enum GitHubPath {
    static func repository(_ owner: String, _ repository: String) -> String {
        "repos/\(owner)/\(repository)"
    }

    static func pullRequest(_ owner: String, _ repository: String, number: Int) -> String {
        "\(self.repository(owner, repository))/pulls/\(number)"
    }

    static func pullRequests(_ owner: String, _ repository: String) -> String {
        "\(self.repository(owner, repository))/pulls"
    }

    static func pullRequestFiles(_ owner: String, _ repository: String, number: Int) -> String {
        "\(pullRequest(owner, repository, number: number))/files"
    }

    static func pullRequestReviewComments(_ owner: String, _ repository: String, number: Int) -> String {
        "\(pullRequest(owner, repository, number: number))/comments"
    }

    static func pullRequestRequestedReviewers(_ owner: String, _ repository: String, number: Int) -> String {
        "\(pullRequest(owner, repository, number: number))/requested_reviewers"
    }

    static func pullRequestReviews(_ owner: String, _ repository: String, number: Int) -> String {
        "\(pullRequest(owner, repository, number: number))/reviews"
    }

    static func reviewComment(_ owner: String, _ repository: String, commentId: Int) -> String {
        "\(self.repository(owner, repository))/pulls/comments/\(commentId)"
    }

    static func issueComments(_ owner: String, _ repository: String, number: Int) -> String {
        "\(self.repository(owner, repository))/issues/\(number)/comments"
    }

    static func issueComment(_ owner: String, _ repository: String, commentId: Int) -> String {
        "\(self.repository(owner, repository))/issues/comments/\(commentId)"
    }

    static func contents(_ owner: String, _ repository: String, path: String) -> String {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "\(self.repository(owner, repository))/contents/\(encodedPath)"
    }

    static func branch(_ owner: String, _ repository: String, branch: String) -> String {
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        return "\(self.repository(owner, repository))/branches/\(encoded)"
    }

    static func compare(_ owner: String, _ repository: String, base: String, head: String) -> String {
        "\(self.repository(owner, repository))/compare/\(base)...\(head)"
    }

    static func gitTree(_ owner: String, _ repository: String, treeSHA: String) -> String {
        "\(self.repository(owner, repository))/git/trees/\(treeSHA)"
    }

    static func commitCheckRuns(_ owner: String, _ repository: String, commitSHA: String) -> String {
        "\(self.repository(owner, repository))/commits/\(commitSHA)/check-runs"
    }

    static func user(login: String) -> String {
        "users/\(login)"
    }

    static func branchRef(_ owner: String, _ repository: String, branch: String) -> String {
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        return "\(self.repository(owner, repository))/git/refs/heads/\(encoded)"
    }

    static func branches(_ owner: String, _ repository: String) -> String {
        "\(self.repository(owner, repository))/branches"
    }

    static func issueAssignees(_ owner: String, _ repository: String, number: Int) -> String {
        "\(self.repository(owner, repository))/issues/\(number)/assignees"
    }

    static func issueLabels(_ owner: String, _ repository: String, number: Int) -> String {
        "\(self.repository(owner, repository))/issues/\(number)/labels"
    }

    static func labels(_ owner: String, _ repository: String) -> String {
        "\(self.repository(owner, repository))/labels"
    }

    static func pullRequestMerge(_ owner: String, _ repository: String, number: Int) -> String {
        "\(pullRequest(owner, repository, number: number))/merge"
    }

    static func workflowDispatch(_ owner: String, _ repository: String, workflowId: String) -> String {
        "\(self.repository(owner, repository))/actions/workflows/\(workflowId)/dispatches"
    }

    static func workflowRuns(_ owner: String, _ repository: String) -> String {
        "\(self.repository(owner, repository))/actions/runs"
    }
}

public struct OctokitClient: Sendable {
    private let token: String
    private let apiEndpoint: String?

    public init(token: String) {
        self.token = token
        self.apiEndpoint = nil
    }

    public init(token: String, enterpriseURL: String) {
        self.token = token
        self.apiEndpoint = enterpriseURL
    }

    public static func fromEnvironment() -> OctokitClient? {
        let token = ProcessInfo.processInfo.environment["GH_TOKEN"]
            ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
        guard let token else { return nil }
        return OctokitClient(token: token)
    }

    public func parseRepoSlug(_ slug: String) -> (owner: String, repository: String)? {
        let parts = slug.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (owner: String(parts[0]), repository: String(parts[1]))
    }

    private var baseURL: String {
        apiEndpoint ?? "https://api.github.com"
    }

    private func makeRequest(
        path: String,
        accept: String = "application/vnd.github+json",
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)/\(path)") else {
            preconditionFailure("Invalid URL: \(baseURL)/\(path)")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            preconditionFailure("Could not construct URL from components for path: \(path)")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func makeMutationRequest(
        path: String,
        method: String,
        accept: String = "application/vnd.github+json",
        payload: [String: Any]
    ) throws -> URLRequest {
        var request = makeRequest(path: path, accept: accept)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    // MARK: - Pull Request Operations

    public func pullRequest(owner: String, repository: String, number: Int) async throws -> PullRequest {
        try await getJSON(path: GitHubPath.pullRequest(owner, repository, number: number))
    }

    public func listPullRequests(
        owner: String,
        repository: String,
        state: Openness = .open,
        sort: SortType = .created,
        direction: SortDirection = .desc,
        base: String? = nil,
        page: String? = nil,
        perPage: String? = nil
    ) async throws -> [PullRequest] {
        var queryItems = [
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "direction", value: direction.rawValue),
        ]
        if let base { queryItems.append(URLQueryItem(name: "base", value: base)) }
        if let page { queryItems.append(URLQueryItem(name: "page", value: page)) }
        if let perPage { queryItems.append(URLQueryItem(name: "per_page", value: perPage)) }
        return try await getJSON(path: GitHubPath.pullRequests(owner, repository), queryItems: queryItems)
    }

    /// Fetches the list of files changed in a pull request using a custom decoder to handle
    /// GitHub's optional `patch` field, which OctoKit's model incorrectly requires.
    public func listPullRequestFiles(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [PullRequest.File] {
        let request = makeRequest(
            path: GitHubPath.pullRequestFiles(owner, repository, number: number),
            accept: "application/vnd.github.v3+json"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Decode using our custom model that handles optional patch field
            let customFiles = try decoder.decode([PullRequestFile].self, from: data)
            
            // Convert to OctoKit's model (see PullRequestFile.toOctokitFile() for details)
            return try customFiles.map { try $0.toOctokitFile() }
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Pull request \(number) files not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func listPullRequestReviewComments(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [ReviewCommentData] {
        var allResults: [ReviewCommentData] = []
        var page = 1
        let perPage = 100

        while true {
            let request = makeRequest(
                path: GitHubPath.pullRequestReviewComments(owner, repository, number: number),
                accept: "application/vnd.github.v3+json",
                queryItems: [
                    URLQueryItem(name: "per_page", value: String(perPage)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OctokitClientError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                let responses = try decoder.decode([ReviewCommentResponse].self, from: data)
                let mapped = responses.map { r in
                    ReviewCommentData(
                        id: r.id,
                        body: r.body,
                        path: r.path,
                        line: r.line,
                        startLine: r.startLine,
                        position: r.position,
                        createdAt: r.createdAt,
                        htmlUrl: r.htmlUrl,
                        inReplyToId: r.inReplyToId,
                        userLogin: r.user?.login,
                        userId: r.user?.id
                    )
                }
                allResults.append(contentsOf: mapped)

                if responses.count < perPage {
                    return allResults
                }
                page += 1
            case 401:
                throw OctokitClientError.authenticationFailed
            case 404:
                throw OctokitClientError.notFound("Pull request \(number) review comments not found")
            case 403:
                throw OctokitClientError.rateLimitExceeded
            default:
                throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
            }
        }
    }

    public func getPullRequestDiff(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> String {
        let request = makeRequest(
            path: GitHubPath.pullRequest(owner, repository, number: number),
            accept: "application/vnd.github.v3.diff"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            guard let diff = String(data: data, encoding: .utf8) else {
                throw OctokitClientError.invalidResponse
            }
            return diff
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Pull request \(number) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - Git History Operations

    public func getFileContent(
        owner: String,
        repository: String,
        path: String,
        ref: String
    ) async throws -> String {
        let request = makeRequest(
            path: GitHubPath.contents(owner, repository, path: path),
            accept: "application/vnd.github.v3.raw",
            queryItems: [URLQueryItem(name: "ref", value: ref)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let content = String(data: data, encoding: .utf8) else {
                throw OctokitClientError.invalidResponse
            }
            return content
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("File \(path) at ref \(ref) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func listDirectoryNames(
        owner: String,
        repository: String,
        path: String,
        ref: String
    ) async throws -> [String] {
        let request = makeRequest(
            path: GitHubPath.contents(owner, repository, path: path),
            accept: "application/vnd.github.v3+json",
            queryItems: [URLQueryItem(name: "ref", value: ref)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            struct Entry: Decodable {
                let name: String
                let type: String
            }
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            return entries.filter { $0.type == "dir" }.map(\.name)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Directory \(path) at ref \(ref) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func compareCommits(
        owner: String,
        repository: String,
        base: String,
        head: String
    ) async throws -> CompareResult {
        let strippedBase = base.hasPrefix("origin/") ? String(base.dropFirst("origin/".count)) : base
        let strippedHead = head.hasPrefix("origin/") ? String(head.dropFirst("origin/".count)) : head
        let request = makeRequest(
            path: GitHubPath.compare(owner, repository, base: strippedBase, head: strippedHead),
            accept: "application/vnd.github.v3+json"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let compareResponse = try decoder.decode(CompareResponse.self, from: data)
            return CompareResult(mergeBaseCommitSHA: compareResponse.mergeBaseCommit.sha)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Compare \(strippedBase)...\(strippedHead) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func getBranchHead(owner: String, repository: String, branch: String) async throws -> BranchHead {
        let request = makeRequest(path: GitHubPath.branch(owner, repository, branch: branch))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            let branchResponse = try JSONDecoder().decode(BranchResponse.self, from: data)
            return BranchHead(
                commitSHA: branchResponse.commit.sha,
                treeSHA: branchResponse.commit.commit.tree.sha
            )
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Branch \(branch) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func getFileContentWithSHA(
        owner: String,
        repository: String,
        path: String,
        ref: String
    ) async throws -> (sha: String, content: String) {
        let request = makeRequest(
            path: GitHubPath.contents(owner, repository, path: path),
            accept: "application/vnd.github.v3+json",
            queryItems: [URLQueryItem(name: "ref", value: ref)]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            let metadata = try JSONDecoder().decode(ContentsMetadata.self, from: data)
            guard let encodedContent = metadata.content,
                  metadata.encoding == "base64" else {
                throw OctokitClientError.invalidResponse
            }
            let cleaned = encodedContent.components(separatedBy: .whitespacesAndNewlines).joined()
            guard let contentData = Data(base64Encoded: cleaned),
                  let content = String(data: contentData, encoding: .utf8) else {
                throw OctokitClientError.invalidResponse
            }
            return (sha: metadata.sha, content: content)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("File \(path) at ref \(ref) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func getFileSHA(
        owner: String,
        repository: String,
        path: String,
        ref: String
    ) async throws -> String {
        let request = makeRequest(
            path: GitHubPath.contents(owner, repository, path: path),
            accept: "application/vnd.github.v3+json",
            queryItems: [URLQueryItem(name: "ref", value: ref)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(ContentsMetadata.self, from: data)
            return metadata.sha
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("File \(path) at ref \(ref) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    public func getGitTree(owner: String, repository: String, treeSHA: String) async throws -> [GitTreeEntry] {
        let request = makeRequest(
            path: GitHubPath.gitTree(owner, repository, treeSHA: treeSHA),
            queryItems: [URLQueryItem(name: "recursive", value: "1")]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            let treeResponse = try JSONDecoder().decode(GitTreeResponse.self, from: data)
            return treeResponse.tree
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound("Git tree \(treeSHA) not found")
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - Comment Edit Operations

    @discardableResult
    public func updateReviewComment(
        owner: String,
        repository: String,
        commentId: Int,
        body: String
    ) async throws -> PullRequest.Comment {
        try await patchJSON(
            path: GitHubPath.reviewComment(owner, repository, commentId: commentId),
            payload: ["body": body]
        )
    }

    @discardableResult
    public func updateIssueComment(
        owner: String,
        repository: String,
        commentId: Int,
        body: String
    ) async throws -> Issue.Comment {
        try await patchJSON(
            path: GitHubPath.issueComment(owner, repository, commentId: commentId),
            payload: ["body": body]
        )
    }

    // MARK: - Repository Operations

    public struct RepositoryInfo: Sendable {
        public let name: String
        public let htmlURL: String?
        public let defaultBranch: String
        public let ownerLogin: String
        public let ownerId: String
    }

    public func repositoryInfo(owner: String, name: String) async throws -> RepositoryInfo {
        struct Payload: Decodable {
            let name: String?
            let htmlURL: String?
            let defaultBranch: String?
            let owner: OwnerPayload

            struct OwnerPayload: Decodable {
                let login: String?
                let id: Int
            }

            enum CodingKeys: String, CodingKey {
                case name
                case htmlURL = "html_url"
                case defaultBranch = "default_branch"
                case owner
            }
        }
        let payload: Payload = try await getJSON(path: GitHubPath.repository(owner, name))
        return RepositoryInfo(
            name: payload.name ?? "",
            htmlURL: payload.htmlURL,
            defaultBranch: payload.defaultBranch ?? "",
            ownerLogin: payload.owner.login ?? "",
            ownerId: String(payload.owner.id)
        )
    }

    // MARK: - Comment Operations

    public func postIssueComment(
        owner: String,
        repository: String,
        number: Int,
        body: String
    ) async throws -> Issue.Comment {
        try await postJSON(
            path: GitHubPath.issueComments(owner, repository, number: number),
            payload: ["body": body]
        )
    }

    @discardableResult
    public func postReviewComment(
        owner: String,
        repository: String,
        number: Int,
        commitId: String,
        path: String,
        line: Int,
        body: String
    ) async throws -> PullRequest.Comment {
        try await postJSON(
            path: GitHubPath.pullRequestReviewComments(owner, repository, number: number),
            accept: "application/vnd.github.comfort-fade-preview+json",
            payload: [
                "body": body,
                "commit_id": commitId,
                "path": path,
                "line": line,
                "side": "RIGHT"
            ]
        )
    }

    public func issueComments(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [Issue.Comment] {
        try await getJSON(path: GitHubPath.issueComments(owner, repository, number: number))
    }

    public func listReviews(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> [Review] {
        try await getJSON(path: GitHubPath.pullRequestReviews(owner, repository, number: number))
    }

    public func requestedReviewers(owner: String, repository: String, number: Int) async throws -> [String] {
        struct RequestedReviewersResponse: Decodable {
            struct User: Decodable {
                let login: String
            }
            let users: [User]
        }
        let response: RequestedReviewersResponse = try await getJSON(
            path: GitHubPath.pullRequestRequestedReviewers(owner, repository, number: number)
        )
        return response.users.map { $0.login }
    }

    public func isMergeable(owner: String, repository: String, number: Int) async throws -> Bool? {
        struct MergeableResponse: Decodable {
            let mergeable: Bool?
        }
        let response: MergeableResponse = try await getJSON(
            path: GitHubPath.pullRequest(owner, repository, number: number)
        )
        return response.mergeable
    }

    public func checkRuns(
        owner: String,
        repository: String,
        commitSHA: String
    ) async throws -> [CheckRun] {
        struct CheckRunsResponse: Decodable {
            let check_runs: [CheckRun]
        }
        let response: CheckRunsResponse = try await getJSON(
            path: GitHubPath.commitCheckRuns(owner, repository, commitSHA: commitSHA)
        )
        return response.check_runs
    }

    // MARK: - GraphQL Operations

    public func pullRequestBodyHTML(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> String {
        let query = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              bodyHTML
            }
          }
        }
        """
        let request = try makeMutationRequest(
            path: "graphql",
            method: "POST",
            payload: [
                "query": query,
                "variables": [
                    "owner": owner,
                    "name": repository,
                    "number": number
                ] as [String: Any]
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let errors = json?["errors"] as? [[String: Any]],
               let message = errors.first?["message"] as? String {
                throw OctokitClientError.requestFailed("GraphQL error: \(message)")
            }
            guard let dataObj = json?["data"] as? [String: Any],
                  let repo = dataObj["repository"] as? [String: Any],
                  let pr = repo["pullRequest"] as? [String: Any],
                  let bodyHTML = pr["bodyHTML"] as? String else {
                throw OctokitClientError.invalidResponse
            }
            return bodyHTML
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Fetches only the `updatedAt` timestamp for a pull request via GraphQL.
    /// This is a lightweight call for staleness checking without fetching full PR data.
    public func pullRequestUpdatedAt(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> String {
        let query = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              updatedAt
            }
          }
        }
        """
        let request = try makeMutationRequest(
            path: "graphql",
            method: "POST",
            payload: [
                "query": query,
                "variables": [
                    "owner": owner,
                    "name": repository,
                    "number": number
                ] as [String: Any]
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let errors = json?["errors"] as? [[String: Any]],
               let message = errors.first?["message"] as? String {
                throw OctokitClientError.requestFailed("GraphQL error: \(message)")
            }
            guard let dataObj = json?["data"] as? [String: Any],
                  let repo = dataObj["repository"] as? [String: Any],
                  let pr = repo["pullRequest"] as? [String: Any],
                  let updatedAt = pr["updatedAt"] as? String else {
                throw OctokitClientError.invalidResponse
            }
            return updatedAt
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Fetches review thread resolution status for a pull request via GraphQL.
    ///
    /// Returns a set of review comment IDs (database IDs as strings) whose threads are resolved.
    /// Each thread is identified by its first comment's `databaseId`.
    public func fetchResolvedReviewCommentIDs(
        owner: String,
        repository: String,
        number: Int
    ) async throws -> Set<String> {
        var resolvedIDs = Set<String>()
        var cursor: String? = nil

        while true {
            let afterClause = cursor.map { ", after: \"\($0)\"" } ?? ""
            let query = """
            query($owner: String!, $name: String!, $number: Int!) {
              repository(owner: $owner, name: $name) {
                pullRequest(number: $number) {
                  reviewThreads(first: 100\(afterClause)) {
                    pageInfo {
                      hasNextPage
                      endCursor
                    }
                    nodes {
                      isResolved
                      comments(first: 1) {
                        nodes {
                          databaseId
                        }
                      }
                    }
                  }
                }
              }
            }
            """
            let request = try makeMutationRequest(
                path: "graphql",
                method: "POST",
                payload: [
                    "query": query,
                    "variables": [
                        "owner": owner,
                        "name": repository,
                        "number": number
                    ] as [String: Any]
                ]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OctokitClientError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let errors = json?["errors"] as? [[String: Any]],
                   let message = errors.first?["message"] as? String {
                    throw OctokitClientError.requestFailed("GraphQL error: \(message)")
                }
                guard let dataObj = json?["data"] as? [String: Any],
                      let repo = dataObj["repository"] as? [String: Any],
                      let pr = repo["pullRequest"] as? [String: Any],
                      let threads = pr["reviewThreads"] as? [String: Any],
                      let nodes = threads["nodes"] as? [[String: Any]] else {
                    throw OctokitClientError.invalidResponse
                }

                for node in nodes {
                    guard let isResolved = node["isResolved"] as? Bool, isResolved,
                          let commentsObj = node["comments"] as? [String: Any],
                          let commentNodes = commentsObj["nodes"] as? [[String: Any]],
                          let firstComment = commentNodes.first,
                          let databaseId = firstComment["databaseId"] as? Int else {
                        continue
                    }
                    resolvedIDs.insert(String(databaseId))
                }

                let pageInfo = threads["pageInfo"] as? [String: Any]
                let hasNextPage = pageInfo?["hasNextPage"] as? Bool ?? false
                if hasNextPage, let endCursor = pageInfo?["endCursor"] as? String {
                    cursor = endCursor
                } else {
                    return resolvedIDs
                }
            case 401:
                throw OctokitClientError.authenticationFailed
            case 403:
                throw OctokitClientError.rateLimitExceeded
            default:
                throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
            }
        }
    }

    // MARK: - User Operations

    public func getUser(login: String) async throws -> OctoKit.User {
        try await getJSON(path: GitHubPath.user(login: login))
    }

    // MARK: - Write / Mutation Operations

    public func createPullRequest(
        owner: String,
        repository: String,
        title: String,
        body: String,
        head: String,
        base: String,
        draft: Bool
    ) async throws -> CreatedPullRequest {
        let request = try makeMutationRequest(
            path: GitHubPath.pullRequests(owner, repository),
            method: "POST",
            payload: [
                "title": title,
                "body": body,
                "head": head,
                "base": base,
                "draft": draft
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 201:
            struct Response: Decodable {
                let number: Int
                let htmlUrl: String
                enum CodingKeys: String, CodingKey {
                    case number
                    case htmlUrl = "html_url"
                }
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return CreatedPullRequest(number: decoded.number, htmlURL: decoded.htmlUrl)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OctokitClientError.requestFailed("HTTP 403: \(body)")
        case 422:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OctokitClientError.requestFailed("HTTP 422: \(body)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func updatePullRequestState(
        owner: String,
        repository: String,
        number: Int,
        state: String
    ) async throws {
        let request = try makeMutationRequest(
            path: GitHubPath.pullRequest(owner, repository, number: number),
            method: "PATCH",
            payload: ["state": state]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Pull request \(number)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func mergePullRequest(
        owner: String,
        repository: String,
        number: Int,
        mergeMethod: String
    ) async throws {
        let request = try makeMutationRequest(
            path: GitHubPath.pullRequestMerge(owner, repository, number: number),
            method: "PUT",
            payload: ["merge_method": mergeMethod]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Pull request \(number)")
        case 405:
            throw OctokitClientError.requestFailed("Pull request \(number) is not mergeable")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func addAssignees(
        owner: String,
        repository: String,
        issueNumber: Int,
        assignees: [String]
    ) async throws {
        let request = try makeMutationRequest(
            path: GitHubPath.issueAssignees(owner, repository, number: issueNumber),
            method: "POST",
            payload: ["assignees": assignees]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 201:
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Issue \(issueNumber)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func addLabels(
        owner: String,
        repository: String,
        issueNumber: Int,
        labels: [String]
    ) async throws {
        let request = try makeMutationRequest(
            path: GitHubPath.issueLabels(owner, repository, number: issueNumber),
            method: "POST",
            payload: ["labels": labels]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Issue \(issueNumber)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func createLabel(
        owner: String,
        repository: String,
        name: String,
        color: String,
        description: String
    ) async throws {
        let request = try makeMutationRequest(
            path: GitHubPath.labels(owner, repository),
            method: "POST",
            payload: [
                "name": name,
                "color": color,
                "description": description
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 201, 422:
            // 422 means label already exists — treat as success
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Repository \(owner)/\(repository)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func requestReviewers(
        owner: String,
        repository: String,
        number: Int,
        reviewers: [String]
    ) async throws {
        let request = try makeMutationRequest(
            path: GitHubPath.pullRequestRequestedReviewers(owner, repository, number: number),
            method: "POST",
            payload: ["reviewers": reviewers]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 201:
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Pull request \(number)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func deleteBranchRef(owner: String, repository: String, branch: String) async throws {
        try await deleteResource(path: GitHubPath.branchRef(owner, repository, branch: branch))
    }

    public func listBranches(owner: String, repository: String) async throws -> [String] {
        let request = makeRequest(
            path: GitHubPath.branches(owner, repository),
            queryItems: [URLQueryItem(name: "per_page", value: "100")]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            struct BranchEntry: Decodable {
                let name: String
            }
            let entries = try JSONDecoder().decode([BranchEntry].self, from: data)
            return entries.map(\.name)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Repository \(owner)/\(repository)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func triggerWorkflowDispatch(
        owner: String,
        repository: String,
        workflowId: String,
        ref: String,
        inputs: [String: String]
    ) async throws {
        var payload: [String: Any] = ["ref": ref]
        if !inputs.isEmpty {
            payload["inputs"] = inputs
        }
        let request = try makeMutationRequest(
            path: GitHubPath.workflowDispatch(owner, repository, workflowId: workflowId),
            method: "POST",
            payload: payload
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 204:
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Workflow \(workflowId)")
        case 422:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("Unprocessable: \(errorBody)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func listWorkflowRuns(
        owner: String,
        repository: String,
        workflow: String?,
        branch: String?,
        limit: Int
    ) async throws -> [WorkflowRun] {
        var queryItems = [URLQueryItem(name: "per_page", value: String(min(limit, 100)))]
        if let branch { queryItems.append(URLQueryItem(name: "branch", value: branch)) }

        let request = makeRequest(
            path: GitHubPath.workflowRuns(owner, repository),
            queryItems: queryItems
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            struct RunsResponse: Decodable {
                let workflowRuns: [RunEntry]

                struct RunEntry: Decodable {
                    let id: Int
                    let status: String
                    let conclusion: String?
                    let headBranch: String?
                    let htmlUrl: String?

                    enum CodingKeys: String, CodingKey {
                        case id, status, conclusion
                        case headBranch = "head_branch"
                        case htmlUrl = "html_url"
                    }
                }

                enum CodingKeys: String, CodingKey {
                    case workflowRuns = "workflow_runs"
                }
            }
            let decoded = try JSONDecoder().decode(RunsResponse.self, from: data)
            let runs = decoded.workflowRuns.map {
                WorkflowRun(
                    id: $0.id,
                    status: $0.status,
                    conclusion: $0.conclusion,
                    headBranch: $0.headBranch,
                    htmlURL: $0.htmlUrl
                )
            }
            guard let workflow else { return runs }
            return runs.filter { $0.headBranch == workflow || $0.status == workflow }
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Repository \(owner)/\(repository)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    public func pullRequestByHeadBranch(
        owner: String,
        repository: String,
        branch: String,
        state: String = "open"
    ) async throws -> CreatedPullRequest? {
        let queryItems = [
            URLQueryItem(name: "head", value: "\(owner):\(branch)"),
            URLQueryItem(name: "state", value: state)
        ]
        let request = makeRequest(
            path: GitHubPath.pullRequests(owner, repository),
            queryItems: queryItems
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            struct PREntry: Decodable {
                let number: Int
                let htmlUrl: String
                enum CodingKeys: String, CodingKey {
                    case number
                    case htmlUrl = "html_url"
                }
            }
            let prs = try JSONDecoder().decode([PREntry].self, from: data)
            guard let first = prs.first else { return nil }
            return CreatedPullRequest(number: first.number, htmlURL: first.htmlUrl)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        case 404:
            throw OctokitClientError.notFound("Repository \(owner)/\(repository)")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    // MARK: - Private

    private func deleteResource(path: String) async throws {
        var request = makeRequest(path: path)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 204, 404:
            return
        case 401:
            throw OctokitClientError.authenticationFailed
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    /// All API calls use Bearer auth via direct URLSession requests. OctoKit's router
    /// sends `Authorization: Basic <token>` which GitHub Actions' GITHUB_TOKEN rejects
    /// on private repos (returns 404). Bearer auth works with both PATs and installation tokens.
    private func getJSON<T: Decodable>(
        path: String,
        accept: String = "application/vnd.github+json",
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let request = makeRequest(path: path, accept: accept, queryItems: queryItems)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(Time.rfc3339DateFormatter)
            return try decoder.decode(T.self, from: data)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound(path)
        case 403:
            throw OctokitClientError.rateLimitExceeded
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    private func postJSON<T: Decodable>(
        path: String,
        accept: String = "application/vnd.github+json",
        payload: [String: Any]
    ) async throws -> T {
        let request = try makeMutationRequest(path: path, method: "POST", accept: accept, payload: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(Time.rfc3339DateFormatter)
            return try decoder.decode(T.self, from: data)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound(path)
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

    private func patchJSON<T: Decodable>(
        path: String,
        accept: String = "application/vnd.github+json",
        payload: [String: Any]
    ) async throws -> T {
        let request = try makeMutationRequest(path: path, method: "PATCH", accept: accept, payload: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OctokitClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(Time.rfc3339DateFormatter)
            return try decoder.decode(T.self, from: data)
        case 401:
            throw OctokitClientError.authenticationFailed
        case 404:
            throw OctokitClientError.notFound(path)
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OctokitClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }
    }

}
