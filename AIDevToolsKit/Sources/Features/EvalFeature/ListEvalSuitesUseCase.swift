import Foundation
import EvalService
import UseCaseSDK

public struct ListEvalSuitesUseCase: UseCase {

    public struct Options: Sendable {
        public let casesDirectory: URL
        public let skillName: String?

        public init(casesDirectory: URL, skillName: String? = nil) {
            self.casesDirectory = casesDirectory
            self.skillName = skillName
        }
    }

    private let caseLoader: CaseLoader

    public init(caseLoader: CaseLoader = CaseLoader()) {
        self.caseLoader = caseLoader
    }

    public func run(_ options: Options) throws -> [EvalSuite] {
        let casesDir = options.casesDirectory.appendingPathComponent("cases")
        let allCases = try caseLoader.loadCases(from: casesDir)

        let grouped = Dictionary(grouping: allCases, by: { $0.suite ?? "" })
        let allSuites = grouped.keys.sorted().map { name in
            EvalSuite(name: name, cases: grouped[name]!)
        }

        if let skillName = options.skillName {
            return allSuites.filter { $0.name == skillName }
        }
        return allSuites
    }
}
