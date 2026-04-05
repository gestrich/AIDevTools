public struct PRConfiguration: Sendable {
    public let assignees: [String]
    public let labels: [String]
    public let maxOpenPRs: Int?
    public let reviewers: [String]

    public init(
        assignees: [String] = [],
        labels: [String] = [],
        maxOpenPRs: Int? = nil,
        reviewers: [String] = []
    ) {
        self.assignees = assignees
        self.labels = labels
        self.maxOpenPRs = maxOpenPRs
        self.reviewers = reviewers
    }
}
