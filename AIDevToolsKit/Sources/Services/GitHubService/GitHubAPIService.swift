import Foundation
import Logging
@preconcurrency import OctoKit
import OctokitSDK
import PRRadarModelsService

private let logger = Logger(label: "GitHubAPIService")

public struct GitHubAPIService: Sendable {
    private let octokitClient: OctokitClient
    private let owner: String
    private let repo: String

    public init(octokitClient: OctokitClient, owner: String, repo: String) {
        self.octokitClient = octokitClient
        self.owner = owner
        self.repo = repo
    }

    public var repoSlug: String { "\(owner)/\(repo)" }

    // MARK: - Pull Request Operations

    public func getPRDiff(number: Int) async throws -> String {
        try await octokitClient.getPullRequestDiff(owner: owner, repository: repo, number: number)
    }

    public func getPullRequest(number: Int) async throws -> GitHubPullRequest {
        let pr = try await octokitClient.pullRequest(owner: owner, repository: repo, number: number)
        let files = try await octokitClient.listPullRequestFiles(owner: owner, repository: repo, number: number)
        return pr.toGitHubPullRequest(files: files)
    }

    public func getPullRequestComments(number: Int) async throws -> GitHubPullRequestComments {
        let issueComments = try await octokitClient.issueComments(
            owner: owner, repository: repo, number: number
        )
        let comments = issueComments.map { comment in
            GitHubComment(
                id: String(comment.id),
                body: comment.body,
                author: comment.user.toGitHubAuthor(),
                createdAt: formatISO8601(comment.createdAt),
                url: comment.htmlURL.absoluteString
            )
        }

        let reviewList = try await octokitClient.listReviews(
            owner: owner, repository: repo, number: number
        )
        let reviews = reviewList.map { review in
            GitHubReview(
                id: String(review.id),
                body: review.body,
                state: review.state.toGitHubReviewState,
                author: GitHubAuthor(
                    login: review.authorLogin ?? "",
                    id: review.authorId.map(String.init),
                    name: review.authorName,
                    avatarURL: review.authorAvatarURL
                ),
                submittedAt: review.submittedAt.map { formatISO8601($0) }
            )
        }

        let reviewCommentList = try await octokitClient.listPullRequestReviewComments(
            owner: owner, repository: repo, number: number
        )
        let reviewComments = reviewCommentList.map { rc in
            GitHubReviewComment(
                id: String(rc.id),
                body: rc.body,
                path: rc.path,
                line: rc.line,
                startLine: rc.startLine,
                author: rc.userLogin.map { GitHubAuthor(login: $0, id: rc.userId.map(String.init)) },
                createdAt: rc.createdAt,
                url: rc.htmlUrl,
                inReplyToId: rc.inReplyToId.map(String.init),
                isOutdated: rc.position == nil
            )
        }

        return GitHubPullRequestComments(comments: comments, reviews: reviews, reviewComments: reviewComments)
    }

    public func listPullRequests(
        limit: Int,
        filter: PRFilter = PRFilter()
    ) async throws -> [GitHubPullRequest] {
        let dateFilter = filter.dateFilter

        let openness: Openness
        if let apiStateOverride = dateFilter?.requiresClosedAPIState, apiStateOverride {
            openness = .closed
        } else if let state = filter.state {
            switch state.apiStateValue {
            case "closed": openness = .closed
            default: openness = .open
            }
        } else {
            openness = .all
        }

        let sort: SortType = dateFilter?.sortsByCreated == true ? .created : .updated

        var allPRs: [GitHubPullRequest] = []
        var page = 1
        let perPage = 100
        let formatter = ISO8601DateFormatter()
        let baseBranch = filter.baseBranch?.isEmpty == false ? filter.baseBranch : nil

        while true {
            logger.trace("listPullRequests: fetching page \(page)", metadata: ["repo": "\(owner)/\(repo)"])
            let prs = try await octokitClient.listPullRequests(
                owner: owner,
                repository: repo,
                state: openness,
                sort: sort,
                direction: .desc,
                base: baseBranch,
                page: String(page),
                perPage: String(perPage)
            )

            if prs.isEmpty {
                logger.trace("listPullRequests: empty page, stopping", metadata: ["repo": "\(owner)/\(repo)", "page": "\(page)"])
                break
            }

            let mapped = prs.map { $0.toGitHubPullRequest() }

            if let dateFilter {
                let since = dateFilter.date
                var hitOldPRs = false

                for pr in mapped {
                    if let earlyStopStr = dateFilter.extractEarlyStopDate(pr),
                       let earlyStopDate = formatter.date(from: earlyStopStr),
                       earlyStopDate < since {
                        hitOldPRs = true
                        break
                    }

                    if let dateStr = dateFilter.extractDate(pr),
                       let prDate = formatter.date(from: dateStr),
                       prDate >= since {
                        allPRs.append(pr)
                    }
                }

                if hitOldPRs {
                    logger.trace("listPullRequests: early-stop on page \(page)", metadata: ["repo": "\(owner)/\(repo)", "collected": "\(allPRs.count)"])
                    break
                }
            } else {
                allPRs.append(contentsOf: mapped)
            }

            if allPRs.count >= limit {
                break
            }

            if prs.count < perPage {
                break
            }

            page += 1
        }

        var result = Array(allPRs.prefix(limit))
        logger.trace("listPullRequests: done", metadata: ["repo": "\(owner)/\(repo)", "pages": "\(page)", "total": "\(result.count)"])

        if let state = filter.state {
            result = result.filter {
                $0.enhancedState == state || (state == .open && $0.enhancedState == .draft)
            }
        }
        if let authorLogin = filter.authorLogin, !authorLogin.isEmpty {
            result = result.filter { $0.author?.login == authorLogin }
        }
        return result
    }

    public func getPRUpdatedAt(number: Int) async throws -> String {
        try await octokitClient.pullRequestUpdatedAt(owner: owner, repository: repo, number: number)
    }

    public func getUser(login: String) async throws -> GitHubAuthor {
        let user = try await octokitClient.getUser(login: login)
        return GitHubAuthor(
            login: user.login ?? login,
            name: user.name,
            avatarURL: user.avatarURL
        )
    }

    public func getRepository() async throws -> GitHubRepository {
        let info = try await octokitClient.repositoryInfo(owner: owner, name: self.repo)
        return GitHubRepository(
            name: info.name,
            url: info.htmlURL,
            owner: GitHubOwner(login: info.ownerLogin, id: info.ownerId),
            defaultBranchRef: info.defaultBranch.isEmpty ? nil : GitHubDefaultBranchRef(name: info.defaultBranch)
        )
    }

    // MARK: - GraphQL Operations

    public func fetchBodyHTML(number: Int) async throws -> String {
        try await octokitClient.pullRequestBodyHTML(owner: owner, repository: repo, number: number)
    }

    /// Fetches the set of review comment IDs whose threads are resolved on GitHub.
    public func fetchResolvedReviewCommentIDs(number: Int) async throws -> Set<String> {
        try await octokitClient.fetchResolvedReviewCommentIDs(
            owner: owner, repository: repo, number: number
        )
    }

    // MARK: - Comment Operations

    public func getPRHeadSHA(number: Int) async throws -> String {
        let pr = try await octokitClient.pullRequest(owner: owner, repository: repo, number: number)
        guard let sha = pr.head?.sha else {
            throw OctokitClientError.requestFailed("Pull request \(number) has no head SHA")
        }
        return sha
    }

    public func postIssueComment(number: Int, body: String) async throws {
        _ = try await octokitClient.postIssueComment(owner: owner, repository: repo, number: number, body: body)
    }

    public func postReviewComment(
        number: Int,
        commitId: String,
        path: String,
        line: Int,
        body: String
    ) async throws {
        _ = try await octokitClient.postReviewComment(
            owner: owner,
            repository: repo,
            number: number,
            commitId: commitId,
            path: path,
            line: line,
            body: body
        )
    }

    public func editReviewComment(commentId: Int, body: String) async throws {
        _ = try await octokitClient.updateReviewComment(
            owner: owner,
            repository: repo,
            commentId: commentId,
            body: body
        )
    }

    public func editIssueComment(commentId: Int, body: String) async throws {
        _ = try await octokitClient.updateIssueComment(
            owner: owner,
            repository: repo,
            commentId: commentId,
            body: body
        )
    }

    // MARK: - Git History Operations

    public func fileContent(path: String, ref: String) async throws -> String {
        try await octokitClient.getFileContent(owner: owner, repository: repo, path: path, ref: ref)
    }

    public func getBranchHead(branch: String) async throws -> BranchHead {
        try await octokitClient.getBranchHead(owner: owner, repository: repo, branch: branch)
    }

    public func getFileContentWithSHA(path: String, ref: String) async throws -> (sha: String, content: String) {
        try await octokitClient.getFileContentWithSHA(owner: owner, repository: repo, path: path, ref: ref)
    }

    public func getGitTree(treeSHA: String) async throws -> [GitTreeEntry] {
        try await octokitClient.getGitTree(owner: owner, repository: repo, treeSHA: treeSHA)
    }

    public func listDirectoryNames(path: String, ref: String) async throws -> [String] {
        try await octokitClient.listDirectoryNames(owner: owner, repository: repo, path: path, ref: ref)
    }

    public func getFileContent(path: String, ref: String) async throws -> String {
        try await fileContent(path: path, ref: ref)
    }

    public func compareCommits(base: String, head: String) async throws -> CompareResult {
        try await octokitClient.compareCommits(owner: owner, repository: repo, base: base, head: head)
    }

    public func getFileSHA(path: String, ref: String) async throws -> String {
        try await octokitClient.getFileSHA(owner: owner, repository: repo, path: path, ref: ref)
    }

    // MARK: - Review and CI Operations

    public func listReviews(prNumber: Int) async throws -> [GitHubReview] {
        let reviewList = try await octokitClient.listReviews(
            owner: owner, repository: repo, number: prNumber
        )
        return reviewList.map { review in
            GitHubReview(
                id: String(review.id),
                body: review.body,
                state: review.state.toGitHubReviewState,
                author: GitHubAuthor(
                    login: review.authorLogin ?? "",
                    id: review.authorId.map(String.init),
                    name: review.authorName,
                    avatarURL: review.authorAvatarURL
                ),
                submittedAt: review.submittedAt.map { formatISO8601($0) }
            )
        }
    }

    public func requestedReviewers(prNumber: Int) async throws -> [String] {
        try await octokitClient.requestedReviewers(owner: owner, repository: repo, number: prNumber)
    }

    public func checkRuns(prNumber: Int, headSHA: String) async throws -> [GitHubCheckRun] {
        let octokitRuns = try await octokitClient.checkRuns(
            owner: owner,
            repository: repo,
            commitSHA: headSHA
        )
        return octokitRuns.map { run in
            GitHubCheckRun(
                name: run.name,
                status: GitHubCheckRunStatus(rawValue: run.status) ?? .queued,
                conclusion: run.conclusion.flatMap { GitHubCheckRunConclusion(rawValue: $0) }
            )
        }
    }

    public func isMergeable(prNumber: Int) async throws -> Bool? {
        try await octokitClient.isMergeable(owner: owner, repository: repo, number: prNumber)
    }

    // MARK: - Write Operations

    public func addAssignees(prNumber: Int, assignees: [String]) async throws {
        try await octokitClient.addAssignees(owner: owner, repository: repo, issueNumber: prNumber, assignees: assignees)
    }

    public func addLabels(prNumber: Int, labels: [String]) async throws {
        try await octokitClient.addLabels(owner: owner, repository: repo, issueNumber: prNumber, labels: labels)
    }

    public func closePullRequest(number: Int) async throws {
        try await octokitClient.updatePullRequestState(owner: owner, repository: repo, number: number, state: "closed")
    }

    public func createLabel(name: String, color: String, description: String) async throws {
        try await octokitClient.createLabel(owner: owner, repository: repo, name: name, color: color, description: description)
    }

    public func createPullRequest(
        title: String,
        body: String,
        head: String,
        base: String,
        draft: Bool
    ) async throws -> CreatedPullRequest {
        try await octokitClient.createPullRequest(
            owner: owner, repository: repo, title: title, body: body, head: head, base: base, draft: draft
        )
    }

    public func deleteBranch(branch: String) async throws {
        try await octokitClient.deleteBranchRef(owner: owner, repository: repo, branch: branch)
    }

    public func listBranches() async throws -> [String] {
        try await octokitClient.listBranches(owner: owner, repository: repo)
    }

    public func listWorkflowRuns(workflow: String, branch: String?, limit: Int) async throws -> [WorkflowRun] {
        try await octokitClient.listWorkflowRuns(
            owner: owner, repository: repo, workflow: workflow, branch: branch, limit: limit
        )
    }

    public func mergePullRequest(number: Int, mergeMethod: String) async throws {
        try await octokitClient.mergePullRequest(
            owner: owner, repository: repo, number: number, mergeMethod: mergeMethod
        )
    }

    public func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest? {
        try await octokitClient.pullRequestByHeadBranch(owner: owner, repository: repo, branch: branch)
    }

    public func requestReviewers(prNumber: Int, reviewers: [String]) async throws {
        try await octokitClient.requestReviewers(owner: owner, repository: repo, number: prNumber, reviewers: reviewers)
    }

    public func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String: String]) async throws {
        try await octokitClient.triggerWorkflowDispatch(
            owner: owner, repository: repo, workflowId: workflowId, ref: ref, inputs: inputs
        )
    }

    // MARK: - Factory

    /// Parse owner and repo name from a git remote URL.
    ///
    /// Supports formats:
    /// - `https://github.com/owner/repo.git`
    /// - `git@github.com:owner/repo.git`
    /// - URLs with or without `.git` suffix
    public static func parseOwnerRepo(from remoteURL: String) -> (owner: String, repo: String)? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // SSH format: git@github.com:owner/repo.git
        if trimmed.contains("@") && trimmed.contains(":") {
            let afterColon = trimmed.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            let parts = afterColon
                .replacingOccurrences(of: ".git", with: "")
                .split(separator: "/")
            guard parts.count >= 2 else { return nil }
            return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
        }

        // HTTPS format: https://github.com/owner/repo.git
        if let url = URL(string: trimmed) {
            let parts = url.pathComponents
                .filter { $0 != "/" }
                .map { $0.replacingOccurrences(of: ".git", with: "") }
            guard parts.count >= 2 else { return nil }
            return (parts[parts.count - 2], parts[parts.count - 1])
        }

        return nil
    }
}

extension GitHubAPIService: GitHubAPIServiceProtocol {}
