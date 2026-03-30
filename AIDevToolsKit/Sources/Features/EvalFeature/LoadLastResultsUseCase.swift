import EvalService
import Foundation
import UseCaseSDK

public struct LoadLastResultsUseCase: UseCase {

    public struct Options: Sendable {
        public let outputDirectory: URL
        public let providerNames: [String]

        public init(outputDirectory: URL, providerNames: [String]) {
            self.outputDirectory = outputDirectory
            self.providerNames = providerNames
        }
    }

    public init() {}

    public func run(_ options: Options) -> [EvalSummary] {
        let artifactsDir = options.outputDirectory.appendingPathComponent("artifacts")
        let fm = FileManager.default
        guard fm.fileExists(atPath: artifactsDir.path) else { return [] }

        let decoder = JSONDecoder()
        var summaries: [EvalSummary] = []

        for name in options.providerNames {
            let summaryFile = artifactsDir
                .appendingPathComponent(name)
                .appendingPathComponent("summary.json")
            guard let data = try? Data(contentsOf: summaryFile),
                  let summary = try? decoder.decode(EvalSummary.self, from: data) else {
                continue
            }
            summaries.append(summary)
        }

        return summaries
    }
}
