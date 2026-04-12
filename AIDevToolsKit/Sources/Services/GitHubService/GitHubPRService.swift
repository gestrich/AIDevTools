import Foundation
import Logging
import OctokitSDK
import PRRadarModelsService

public struct GitHubPRService: GitHubPRServiceProtocol {
    private let cache: GitHubPRCacheService
    private let apiClient: any GitHubAPIServiceProtocol
    private let changeStream: AsyncStream<Int>
    private let logger = Logger(label: "GitHubPRService")

    public init(rootURL: URL, apiClient: any GitHubAPIServiceProtocol) {
        let prCache = GitHubPRCacheService(rootURL: rootURL)
        self.cache = prCache
        self.changeStream = prCache.stream
        self.apiClient = apiClient
    }

    public func pullRequest(number: Int, useCache: Bool) async throws -> GitHubPullRequest {
        if useCache, let cached = try await cache.readPR(number: number) {
            return cached
        }
        let pr = try await apiClient.getPullRequest(number: number)
        try await cache.writePR(pr, number: number)
        return pr
    }

    public func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments {
        if useCache, let cached = try await cache.readComments(number: number) {
            return cached
        }
        let fetched = try await apiClient.getPullRequestComments(number: number)
        try await cache.writeComments(fetched, number: number)
        return fetched
    }

    public func repository(useCache: Bool) async throws -> GitHubRepository {
        if useCache, let cached = try await cache.readRepository() {
            return cached
        }
        let repo = try await apiClient.getRepository()
        try await cache.writeRepository(repo)
        return repo
    }

    public func updatePR(number: Int) async throws {
        let pr = try await apiClient.getPullRequest(number: number)
        try await cache.writePR(pr, number: number)
    }

    public func updatePRs(numbers: [Int]) async throws {
        for number in numbers {
            try await updatePR(number: number)
        }
    }

    public func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest] {
        let prs = try await apiClient.listPullRequests(limit: limit, filter: filter)
        for pr in prs {
            try await cache.writePR(pr, number: pr.number)
        }
        return prs
    }

    public func updatePRs(filter: PRFilter) async throws -> [GitHubPullRequest] {
        try await listPullRequests(limit: 300, filter: filter)
    }

    public func updateRepository() async throws {
        let repo = try await apiClient.getRepository()
        try await cache.writeRepository(repo)
    }

    public func writePR(_ pr: GitHubPullRequest, number: Int) async throws {
        try await cache.writePR(pr, number: number)
    }

    public func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws {
        try await cache.writeComments(comments, number: number)
    }

    public func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview] {
        if useCache, let cached = try await cache.readReviews(number: number) {
            return cached
        }
        let fetched = try await apiClient.listReviews(prNumber: number)
        try await cache.writeReviews(fetched, number: number)
        return fetched
    }

    public func checkRuns(number: Int, useCache: Bool) async throws -> [GitHubCheckRun] {
        if useCache, let cached = try await cache.readCheckRuns(number: number) {
            return cached
        }
        let pr = try await pullRequest(number: number, useCache: true)
        guard let headSHA = pr.headRefOid else {
            throw GitHubPRServiceError.missingHeadRefOid(prNumber: number)
        }
        let fetched = try await apiClient.checkRuns(prNumber: number, headSHA: headSHA)
        try await cache.writeCheckRuns(fetched, number: number)
        return fetched
    }

    public func isMergeable(number: Int) async throws -> Bool? {
        try await apiClient.isMergeable(prNumber: number)
    }

    public func readCachedIndex(key: String) async throws -> [Int]? {
        try await cache.readIndex(key: key)
    }

    public func writeCachedIndex(_ numbers: [Int], key: String) async throws {
        try await cache.writeIndex(numbers, key: key)
    }

    public func changes() -> AsyncStream<Int> {
        changeStream
    }

    public func readAllCachedPRs() async -> [GitHubPullRequest] {
        await cache.readAllCachedPRs()
    }

    // MARK: - Write Operations

    public func closePullRequest(number: Int) async throws {
        try await apiClient.closePullRequest(number: number)
        _ = try await updatePRs(filter: PRFilter())
    }

    public func createLabel(name: String, color: String, description: String) async throws {
        try await apiClient.createLabel(name: name, color: color, description: description)
    }

    public func createPullRequest(
        title: String,
        body: String,
        head: String,
        base: String,
        draft: Bool,
        labels: [String],
        assignees: [String],
        reviewers: [String]
    ) async throws -> CreatedPullRequest {
        let created = try await apiClient.createPullRequest(
            title: title, body: body, head: head, base: base, draft: draft
        )
        if !labels.isEmpty {
            do {
                try await apiClient.addLabels(prNumber: created.number, labels: labels)
            } catch {
                logger.warning("createPullRequest: addLabels failed (non-fatal): \(error)")
            }
        }
        if !assignees.isEmpty {
            do {
                try await apiClient.addAssignees(prNumber: created.number, assignees: assignees)
            } catch {
                logger.warning("createPullRequest: addAssignees failed (non-fatal): \(error)")
            }
        }
        if !reviewers.isEmpty {
            do {
                try await apiClient.requestReviewers(prNumber: created.number, reviewers: reviewers)
            } catch {
                logger.warning("createPullRequest: requestReviewers failed (non-fatal): \(error)")
            }
        }
        _ = try? await updatePRs(filter: PRFilter())
        return created
    }

    public func deleteBranch(branch: String) async throws {
        try await apiClient.deleteBranch(branch: branch)
    }

    public func mergePullRequest(number: Int, mergeMethod: String) async throws {
        try await apiClient.mergePullRequest(number: number, mergeMethod: mergeMethod)
        _ = try await updatePRs(filter: PRFilter())
    }

    public func postIssueComment(prNumber: Int, body: String) async throws {
        try await apiClient.postIssueComment(number: prNumber, body: body)
    }

    public func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest? {
        try await apiClient.pullRequestByHeadBranch(branch: branch)
    }

    public func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String: String]) async throws {
        try await apiClient.triggerWorkflowDispatch(workflowId: workflowId, ref: ref, inputs: inputs)
    }

    // MARK: - Cached Reads

    public func listBranches(ttl: TimeInterval) async throws -> [String] {
        if let cached = try await cache.readBranchList(ttl: ttl) {
            logger.debug("listBranches cache hit")
            return cached
        }
        logger.debug("listBranches cache miss, fetching from API")
        let branches = try await apiClient.listBranches()
        try await cache.writeBranchList(branches)
        return branches
    }

    public func listWorkflowRuns(workflow: String, branch: String?, limit: Int, ttl: TimeInterval) async throws -> [WorkflowRun] {
        if let cached = try await cache.readWorkflowRuns(workflow: workflow, branch: branch, limit: limit, ttl: ttl) {
            logger.debug("listWorkflowRuns cache hit", metadata: ["workflow": .string(workflow)])
            return cached
        }
        logger.debug("listWorkflowRuns cache miss, fetching from API", metadata: ["workflow": .string(workflow)])
        let runs = try await apiClient.listWorkflowRuns(workflow: workflow, branch: branch, limit: limit)
        try await cache.writeWorkflowRuns(runs, workflow: workflow, branch: branch, limit: limit)
        return runs
    }

    // MARK: - Branch HEAD

    public func branchHead(branch: String, ttl: TimeInterval) async throws -> BranchHead {
        if let cached = try await cache.readBranchHead(branch: branch, ttl: ttl) {
            logger.debug("branchHead cache hit", metadata: ["branch": .string(branch)])
            return cached
        }
        logger.debug("branchHead cache miss, fetching from API", metadata: ["branch": .string(branch)])
        let head = try await apiClient.getBranchHead(branch: branch)
        try await cache.writeBranchHead(head, branch: branch)
        return head
    }

    public func fileBlob(blobSHA: String, path: String, ref: String) async throws -> String {
        if let cached = try await cache.readBlob(blobSHA: blobSHA) {
            logger.debug("fileBlob cache hit", metadata: ["sha": .string(blobSHA), "path": .string(path)])
            return cached
        }
        logger.debug("fileBlob cache miss, fetching from API", metadata: ["sha": .string(blobSHA), "path": .string(path)])
        let (_, content) = try await apiClient.getFileContentWithSHA(path: path, ref: ref)
        try await cache.writeBlob(content, blobSHA: blobSHA)
        return content
    }

    public func fileContent(path: String, ref: String) async throws -> String {
        try await apiClient.fileContent(path: path, ref: ref)
    }

    public func gitTree(treeSHA: String) async throws -> [GitTreeEntry] {
        if let cached = try await cache.readGitTree(treeSHA: treeSHA) {
            logger.debug("gitTree cache hit", metadata: ["treeSHA": .string(treeSHA)])
            return cached
        }
        logger.debug("gitTree cache miss, fetching from API", metadata: ["treeSHA": .string(treeSHA)])
        let entries = try await apiClient.getGitTree(treeSHA: treeSHA)
        try await cache.writeGitTree(entries, treeSHA: treeSHA)
        return entries
    }

    // MARK: - Author Cache

    private static let authorCacheTTL: TimeInterval = 7 * 24 * 60 * 60

    public func lookupAuthor(login: String) async throws -> AuthorCacheEntry? {
        let authorCache = (try await cache.readAuthors()) ?? AuthorCache()
        return authorCache.entries[login]?.valueIfFresh(ttl: Self.authorCacheTTL)
    }

    public func updateAuthor(login: String, name: String, avatarURL: String? = nil) async throws {
        var authorCache = (try await cache.readAuthors()) ?? AuthorCache()
        let entry = AuthorCacheEntry(login: login, name: name, avatarURL: avatarURL)
        authorCache.entries[login] = CacheRecord(value: entry)
        try await cache.writeAuthors(authorCache)
    }

    public func loadAllAuthors() async throws -> [AuthorCacheEntry] {
        let authorCache = (try await cache.readAuthors()) ?? AuthorCache()
        return authorCache.entries.values.map { $0.value }
    }

    public func listDirectoryNames(path: String, ref: String) async throws -> [String] {
        let ttl: TimeInterval = 300
        if let cached = try await cache.readDirectoryNames(path: path, ref: ref, ttl: ttl) {
            return cached
        }
        let names = try await apiClient.listDirectoryNames(path: path, ref: ref)
        try await cache.writeDirectoryNames(names, path: path, ref: ref)
        return names
    }
}
