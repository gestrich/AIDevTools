import Foundation
import OctokitSDK
import PRRadarModelsService

actor GitHubPRCacheService {
    private let rootURL: URL
    nonisolated let stream: AsyncStream<Int>
    private nonisolated let continuation: AsyncStream<Int>.Continuation

    init(rootURL: URL) {
        self.rootURL = rootURL
        (stream, continuation) = AsyncStream<Int>.makeStream()
    }

    func readPR(number: Int) throws -> GitHubPullRequest? {
        try readFile(at: prURL(number: number))
    }

    func readComments(number: Int) throws -> GitHubPullRequestComments? {
        try readFile(at: commentsURL(number: number))
    }

    func readRepository() throws -> GitHubRepository? {
        try readFile(at: repositoryURL())
    }

    func writePR(_ pr: GitHubPullRequest, number: Int) throws {
        try writePRFile(pr, to: prURL(number: number), prNumber: number)
    }

    func writeComments(_ comments: GitHubPullRequestComments, number: Int) throws {
        try writePRFile(comments, to: commentsURL(number: number), prNumber: number)
    }

    func writeRepository(_ repository: GitHubRepository) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(repository)
        try data.write(to: repositoryURL())
    }

    func readCheckRuns(number: Int) throws -> [GitHubCheckRun]? {
        try readFile(at: checkRunsURL(number: number))
    }

    func writeCheckRuns(_ checkRuns: [GitHubCheckRun], number: Int) throws {
        try writePRFile(checkRuns, to: checkRunsURL(number: number), prNumber: number)
    }

    func readReviews(number: Int) throws -> [GitHubReview]? {
        try readFile(at: reviewsURL(number: number))
    }

    func writeReviews(_ reviews: [GitHubReview], number: Int) throws {
        try writePRFile(reviews, to: reviewsURL(number: number), prNumber: number)
    }

    // MARK: - Index

    func readIndex(key: String) throws -> [Int]? {
        try readFile(at: indexURL(key: key))
    }

    func writeIndex(_ numbers: [Int], key: String) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(numbers)
        try data.write(to: indexURL(key: key))
    }

    // MARK: - Branch HEAD

    func readBranchHead(branch: String) throws -> BranchHead? {
        try readFile(at: branchHeadURL(branch: branch))
    }

    func writeBranchHead(_ head: BranchHead, branch: String) throws {
        try FileManager.default.createDirectory(at: branchesDirectory(), withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(head)
        try data.write(to: branchHeadURL(branch: branch))
    }

    // MARK: - Git Tree

    func readGitTree(treeSHA: String) throws -> [GitTreeEntry]? {
        try readFile(at: gitTreeURL(treeSHA: treeSHA))
    }

    func writeGitTree(_ entries: [GitTreeEntry], treeSHA: String) throws {
        try FileManager.default.createDirectory(at: treesDirectory(), withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(entries)
        try data.write(to: gitTreeURL(treeSHA: treeSHA))
    }

    // MARK: - File Blob

    func readBlob(blobSHA: String) throws -> String? {
        let url = blobURL(blobSHA: blobSHA)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func writeBlob(_ content: String, blobSHA: String) throws {
        try FileManager.default.createDirectory(at: blobsDirectory(), withIntermediateDirectories: true)
        try content.write(to: blobURL(blobSHA: blobSHA), atomically: true, encoding: .utf8)
    }

    // MARK: - Private helpers

    private func readFile<T: Decodable>(at url: URL, ttl: TimeInterval? = nil) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let ttl {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let modDate = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modDate) > ttl {
                return nil
            }
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func writePRFile<T: Encodable>(_ value: T, to url: URL, prNumber: Int) throws {
        try FileManager.default.createDirectory(at: prDirectory(number: prNumber), withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(value)
        try data.write(to: url)
        continuation.yield(prNumber)
    }

    // MARK: - URLs

    private func prDirectory(number: Int) -> URL {
        rootURL.appendingPathComponent(String(number))
    }

    private func prURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-pr.json")
    }

    private func checkRunsURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-checks.json")
    }

    private func commentsURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-comments.json")
    }

    private func indexURL(key: String) -> URL {
        rootURL.appendingPathComponent("index-\(key).json")
    }

    private func repositoryURL() -> URL {
        rootURL.appendingPathComponent("gh-repo.json")
    }

    private func reviewsURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-reviews.json")
    }

    private func branchesDirectory() -> URL {
        rootURL.appendingPathComponent("branches")
    }

    private func branchHeadURL(branch: String) -> URL {
        let sanitised = branch.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return branchesDirectory().appendingPathComponent("\(sanitised).json")
    }

    private func treesDirectory() -> URL {
        rootURL.appendingPathComponent("trees")
    }

    private func gitTreeURL(treeSHA: String) -> URL {
        treesDirectory().appendingPathComponent("\(treeSHA).json")
    }

    private func blobsDirectory() -> URL {
        rootURL.appendingPathComponent("blobs")
    }

    private func blobURL(blobSHA: String) -> URL {
        blobsDirectory().appendingPathComponent("\(blobSHA).txt")
    }
}

