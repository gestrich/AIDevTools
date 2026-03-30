import PRRadarModelsService

public struct SyncSnapshot: Sendable {
    public let prDiff: PRDiff?
    public let files: [String]
    public let commentCount: Int
    public let reviewCount: Int
    public let reviewCommentCount: Int
    public let commitHash: String?

    public init(
        prDiff: PRDiff? = nil,
        files: [String],
        commentCount: Int = 0,
        reviewCount: Int = 0,
        reviewCommentCount: Int = 0,
        commitHash: String? = nil
    ) {
        self.prDiff = prDiff
        self.files = files
        self.commentCount = commentCount
        self.reviewCount = reviewCount
        self.reviewCommentCount = reviewCommentCount
        self.commitHash = commitHash
    }
}
