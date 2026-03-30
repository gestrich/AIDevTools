import Foundation
import LoggingSDK
import UseCaseSDK

public enum LogQuery: Sendable {
    case lastRun
    case dateRange(from: Date, to: Date)
    case all
}

public struct FetchLogsUseCase: UseCase {
    private let logReader: LogReaderService

    public init(logReader: LogReaderService = LogReaderService()) {
        self.logReader = logReader
    }

    public func execute(query: LogQuery) throws -> [LogEntry] {
        switch query {
        case .lastRun:
            return try logReader.readLastRun(marker: "Analysis started")
        case .dateRange(let from, let to):
            return try logReader.readByDateRange(from: from, to: to)
        case .all:
            return try logReader.readAll()
        }
    }
}
