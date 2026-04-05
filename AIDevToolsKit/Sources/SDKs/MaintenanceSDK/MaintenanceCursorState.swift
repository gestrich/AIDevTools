import Foundation

public struct MaintenanceCursorState: Codable, Sendable {
    public var cursor: String?
    public var lastRunDate: Date?

    public init(cursor: String? = nil, lastRunDate: Date? = nil) {
        self.cursor = cursor
        self.lastRunDate = lastRunDate
    }

    public static func load(from url: URL) throws -> MaintenanceCursorState {
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return MaintenanceCursorState()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MaintenanceCursorState.self, from: data)
    }

    public func save(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
