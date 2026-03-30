import Foundation
import UseCaseSDK

public struct DeletePlanUseCase: UseCase {

    public enum DeleteError: Error, LocalizedError {
        case notFound(String)

        public var errorDescription: String? {
            switch self {
            case .notFound(let path):
                return "Plan file not found: \(path)"
            }
        }
    }

    public init() {}

    public func run(planURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: planURL.path) else {
            throw DeleteError.notFound(planURL.path)
        }
        try fm.removeItem(at: planURL)
    }
}
