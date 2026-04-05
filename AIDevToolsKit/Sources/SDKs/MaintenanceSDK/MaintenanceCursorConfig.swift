import Foundation

public struct MaintenanceCursorConfig: Sendable {
    public let scanLimit: Int
    public let changeLimit: Int
    public let filePattern: String
    public let scope: MaintenanceCursorScope?

    public init(scanLimit: Int = 1, changeLimit: Int = 1, filePattern: String, scope: MaintenanceCursorScope? = nil) {
        self.scanLimit = scanLimit
        self.changeLimit = changeLimit
        self.filePattern = filePattern
        self.scope = scope
    }
}
