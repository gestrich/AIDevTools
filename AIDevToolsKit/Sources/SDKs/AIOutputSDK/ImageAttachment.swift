import Foundation

public struct ImageAttachment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let base64Data: String
    public let mediaType: String

    public init(id: UUID = UUID(), base64Data: String, mediaType: String) {
        self.id = id
        self.base64Data = base64Data
        self.mediaType = mediaType
    }
}
