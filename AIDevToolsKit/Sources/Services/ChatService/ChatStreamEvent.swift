import Foundation

public enum ChatStreamEvent: Sendable {
    case completed(fullText: String)
    case error(Error)
    case textDelta(String)
}
