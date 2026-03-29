import Foundation

public struct IPCUIState: Codable, Sendable {
    public let selectedPlanName: String?
    public let currentTab: String?

    public init(selectedPlanName: String?, currentTab: String?) {
        self.selectedPlanName = selectedPlanName
        self.currentTab = currentTab
    }
}
