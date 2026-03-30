import Foundation
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
        let url = prURL(number: number)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GitHubPullRequest.self, from: data)
    }

    func readComments(number: Int) throws -> GitHubPullRequestComments? {
        let url = commentsURL(number: number)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GitHubPullRequestComments.self, from: data)
    }

    func readRepository() throws -> GitHubRepository? {
        let url = repositoryURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GitHubRepository.self, from: data)
    }

    func writePR(_ pr: GitHubPullRequest, number: Int) throws {
        try FileManager.default.createDirectory(at: prDirectory(number: number), withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(pr)
        try data.write(to: prURL(number: number))
        continuation.yield(number)
    }

    func writeComments(_ comments: GitHubPullRequestComments, number: Int) throws {
        try FileManager.default.createDirectory(at: prDirectory(number: number), withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(comments)
        try data.write(to: commentsURL(number: number))
        continuation.yield(number)
    }

    func writeRepository(_ repository: GitHubRepository) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(repository)
        try data.write(to: repositoryURL())
    }

    private func prDirectory(number: Int) -> URL {
        rootURL.appendingPathComponent(String(number))
    }

    private func prURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-pr.json")
    }

    private func commentsURL(number: Int) -> URL {
        prDirectory(number: number).appendingPathComponent("gh-comments.json")
    }

    private func repositoryURL() -> URL {
        rootURL.appendingPathComponent("gh-repo.json")
    }
}

