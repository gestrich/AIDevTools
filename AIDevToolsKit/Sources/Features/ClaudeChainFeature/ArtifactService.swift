import ClaudeChainService
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public struct ProjectArtifact {
    public let artifactId: Int
    public let artifactName: String
    public let workflowRunId: Int
    public var metadata: TaskMetadata?

    public init(artifactId: Int, artifactName: String, workflowRunId: Int, metadata: TaskMetadata? = nil) {
        self.artifactId = artifactId
        self.artifactName = artifactName
        self.workflowRunId = workflowRunId
        self.metadata = metadata
    }

    public var taskIndex: Int? {
        ArtifactService.parseTaskIndexFromName(artifactName: artifactName)
    }
}

public struct ArtifactService {

    private static let logger = Logger(label: "ArtifactService")

    public static func findProjectArtifacts(
        repo: String,
        project: String,
        workflowFile: String,
        limit: Int = 50,
        downloadMetadata: Bool = false
    ) -> [ProjectArtifact] {
        var resultArtifacts: [ProjectArtifact] = []
        var seenArtifactIds = Set<Int>()

        let workflowFileEncoded = workflowFile.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? workflowFile

        let runs: [[String: Any]]
        do {
            let apiResponse = try githubAPIRequest(repo: repo, path: "/actions/workflows/\(workflowFileEncoded)/runs?status=completed&per_page=\(limit)")
            runs = apiResponse["workflow_runs"] as? [[String: Any]] ?? []
        } catch {
            logger.warning("Failed to get workflow runs for '\(workflowFile)': \(error)")
            runs = []
        }

        logger.debug("Checking \(runs.count) workflow run(s) from '\(workflowFile)' for artifacts")

        for run in runs {
            guard let conclusion = run["conclusion"] as? String,
                  conclusion == "success",
                  let runId = run["id"] as? Int else {
                continue
            }

            let artifacts = getArtifactsForRun(repo: repo, runId: runId)
            let projectArtifacts = filterProjectArtifacts(artifacts: artifacts, project: project)

            for artifact in projectArtifacts {
                guard let artifactId = artifact["id"] as? Int,
                      let artifactName = artifact["name"] as? String else {
                    continue
                }

                if seenArtifactIds.contains(artifactId) {
                    continue
                }
                seenArtifactIds.insert(artifactId)

                var projectArtifact = ProjectArtifact(
                    artifactId: artifactId,
                    artifactName: artifactName,
                    workflowRunId: runId,
                    metadata: nil
                )

                if downloadMetadata {
                    if let metadataDict = downloadArtifactJson(repo: repo, artifactId: artifactId) {
                        projectArtifact.metadata = TaskMetadata.fromDict(metadataDict)
                    }
                }

                resultArtifacts.append(projectArtifact)
            }
        }

        logger.debug("Found \(resultArtifacts.count) artifact(s) for project '\(project)'")
        return resultArtifacts
    }

    public static func getArtifactMetadata(repo: String, artifactId: Int) -> TaskMetadata? {
        if let metadataDict = downloadArtifactJson(repo: repo, artifactId: artifactId) {
            return TaskMetadata.fromDict(metadataDict)
        }
        return nil
    }

    public static func findInProgressTasks(repo: String, project: String, workflowFile: String) -> Set<Int> {
        let artifacts = findProjectArtifacts(
            repo: repo,
            project: project,
            workflowFile: workflowFile,
            downloadMetadata: false
        )
        return Set(artifacts.compactMap { $0.taskIndex })
    }

    public static func parseTaskIndexFromName(artifactName: String) -> Int? {
        // Pattern: task-metadata-{project}-{index}.json where project name can contain dashes
        let pattern = #"task-metadata-.+-(\d+)\.json"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: artifactName.utf16.count)

            if let match = regex.firstMatch(in: artifactName, options: [], range: range),
               let numberRange = Range(match.range(at: 1), in: artifactName) {
                return Int(String(artifactName[numberRange]))
            }
        } catch {
            logger.warning("Failed to parse artifact name '\(artifactName)': \(error)")
        }

        return nil
    }

    // MARK: - Private

    private static func getArtifactsForRun(repo: String, runId: Int) -> [[String: Any]] {
        do {
            let response = try githubAPIRequest(repo: repo, path: "/actions/runs/\(runId)/artifacts")
            return response["artifacts"] as? [[String: Any]] ?? []
        } catch {
            logger.warning("Failed to get artifacts for run \(runId): \(error)")
            return []
        }
    }

    private static func downloadArtifactJson(repo: String, artifactId: Int) -> [String: Any]? {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"] else {
            logger.warning("No GH_TOKEN or GITHUB_TOKEN set; cannot download artifact \(artifactId)")
            return nil
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/actions/artifacts/\(artifactId)/zip") else {
            return nil
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
            logger.warning("Failed to download artifact \(artifactId): \(responseError.localizedDescription)")
            return nil
        }
        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func githubAPIRequest(repo: String, path: String) throws -> [String: Any] {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"] else {
            throw GitHubAPIError("No GH_TOKEN or GITHUB_TOKEN environment variable set")
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)\(path)") else {
            throw GitHubAPIError("Invalid API path: \(path)")
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func filterProjectArtifacts(artifacts: [[String: Any]], project: String) -> [[String: Any]] {
        artifacts.filter { artifact in
            guard let name = artifact["name"] as? String else { return false }
            return name.hasPrefix("task-metadata-\(project)-")
        }
    }
}
