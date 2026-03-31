import Foundation

public struct IPCUIState: Codable, Sendable {
    public let currentTab: String?
    public let selectedChainName: String?
    public let selectedPlanName: String?

    public init(currentTab: String?, selectedChainName: String?, selectedPlanName: String?) {
        self.currentTab = currentTab
        self.selectedChainName = selectedChainName
        self.selectedPlanName = selectedPlanName
    }
}
