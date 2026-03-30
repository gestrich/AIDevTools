import AIOutputSDK
import EvalSDK
import EvalService
import Foundation
import UseCaseSDK

public struct ReadCaseOutputUseCase: UseCase {

    public struct Options: Sendable {
        public let caseId: String
        public let formatter: any StreamFormatter
        public let provider: Provider
        public let outputDirectory: URL
        public let rubricFormatter: any StreamFormatter

        public init(
            caseId: String,
            formatter: any StreamFormatter,
            provider: Provider,
            outputDirectory: URL,
            rubricFormatter: any StreamFormatter
        ) {
            self.caseId = caseId
            self.formatter = formatter
            self.provider = provider
            self.outputDirectory = outputDirectory
            self.rubricFormatter = rubricFormatter
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
            outputDirectory: options.outputDirectory,
            formatter: options.formatter,
            rubricFormatter: options.rubricFormatter
        )
    }
}
