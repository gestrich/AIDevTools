import Foundation

struct RepositoryEvalConfig {
    let casesDirectory: URL
    let outputDirectory: URL
    let repoRoot: URL

    init(casesDirectory: URL, outputDirectory: URL, repoRoot: URL) {
        self.casesDirectory = casesDirectory
        self.outputDirectory = outputDirectory
        self.repoRoot = repoRoot
    }
}
