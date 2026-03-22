import Foundation
import EvalService

public struct ListEvalCasesUseCase: Sendable {

    public struct Options: Sendable {
        public let casesDirectory: URL
        public let caseId: String?
        public let skill: String?
        public let suite: String?

        public init(casesDirectory: URL, caseId: String? = nil, skill: String? = nil, suite: String? = nil) {
            self.casesDirectory = casesDirectory
            self.caseId = caseId
            self.skill = skill
            self.suite = suite
        }
    }

    private let caseLoader: CaseLoader

    public init(caseLoader: CaseLoader = CaseLoader()) {
        self.caseLoader = caseLoader
    }

    public func run(_ options: Options) throws -> [EvalCase] {
        let casesDir = options.casesDirectory.appendingPathComponent("cases")
        let cases = try caseLoader.loadCases(from: casesDir)
        return caseLoader.filterCases(cases, caseId: options.caseId, skill: options.skill, suite: options.suite)
            .sorted { $0.id < $1.id }
    }
}
