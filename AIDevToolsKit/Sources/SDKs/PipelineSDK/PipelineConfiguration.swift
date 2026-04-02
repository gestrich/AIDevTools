import AIOutputSDK

public struct PipelineConfiguration: Sendable {
    public let betweenTasks: (@Sendable () async throws -> Void)?
    public let environment: [String: String]?
    public let executionMode: ExecutionMode
    public let maxMinutes: Int?
    public let provider: any AIClient
    public let stagingOnly: Bool
    public let workingDirectory: String?

    public init(
        executionMode: ExecutionMode = .all,
        maxMinutes: Int? = nil,
        provider: any AIClient,
        stagingOnly: Bool = false,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        betweenTasks: (@Sendable () async throws -> Void)? = nil
    ) {
        self.betweenTasks = betweenTasks
        self.environment = environment
        self.executionMode = executionMode
        self.maxMinutes = maxMinutes
        self.provider = provider
        self.stagingOnly = stagingOnly
        self.workingDirectory = workingDirectory
    }

    public enum ExecutionMode: Sendable {
        case all
        case nextOnly
    }
}
