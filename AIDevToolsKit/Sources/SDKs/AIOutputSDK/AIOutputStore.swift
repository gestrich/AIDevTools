import Foundation

public struct AIOutputStore: Sendable {

    private let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public func write(output: String, key: String) throws {
        let fileURL = url(for: key)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try output.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func read(key: String) -> String? {
        let fileURL = url(for: key)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    public func delete(key: String) throws {
        let fileURL = url(for: key)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }

    private func url(for key: String) -> URL {
        baseDirectory.appendingPathComponent("\(key).stdout")
    }
}
