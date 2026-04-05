import Foundation

public struct GeneratedPlan: Codable, Sendable {
    public let planContent: String
    public let filename: String

    public init(planContent: String, filename: String) {
        self.planContent = planContent
        self.filename = filename
    }
}
