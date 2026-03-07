import Foundation
import EvalService
import EvalSDK

public struct ReadCaseOutputUseCase: Sendable {

    public struct Options: Sendable {
        public let caseId: String
        public let provider: Provider
        public let outputDirectory: URL

        public init(caseId: String, provider: Provider, outputDirectory: URL) {
            self.caseId = caseId
            self.provider = provider
            self.outputDirectory = outputDirectory
        }
    }

    private let outputService: OutputService

    public init(outputService: OutputService = OutputService()) {
        self.outputService = outputService
    }

    public func run(_ options: Options) throws -> FormattedOutput {
        try outputService.readFormattedOutput(
            caseId: options.caseId,
            provider: options.provider,
            outputDirectory: options.outputDirectory
        )
    }
}
