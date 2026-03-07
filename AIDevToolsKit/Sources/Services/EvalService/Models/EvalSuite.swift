import Foundation

public struct EvalSuite: Identifiable, Sendable {
    public let name: String
    public let cases: [EvalCase]

    public var id: String { name }

    public init(name: String, cases: [EvalCase]) {
        self.name = name
        self.cases = cases
    }
}
