import Foundation
import XCTest

extension XCTestCase {
    func createTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }
        return tempDir
    }

    func XCTAssertEqualPaths(_ path1: URL, _ path2: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(path1.standardizedFileURL, path2.standardizedFileURL, file: file, line: line)
    }

    func XCTAssertFileExists(_ path: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path),
                     "File should exist at path: \(path.path)", file: file, line: line)
    }
}
