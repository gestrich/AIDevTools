import Foundation

public struct ClearArtifactsUseCase: Sendable {

    public init() {}

    public func run(outputDirectory: URL) throws {
        let artifactsDir = outputDirectory.appendingPathComponent("artifacts")
        let fm = FileManager.default
        guard fm.fileExists(atPath: artifactsDir.path) else { return }
        try fm.removeItem(at: artifactsDir)
    }
}
