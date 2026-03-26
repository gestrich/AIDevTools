import Foundation
import Testing
@testable import AIOutputSDK

@Suite struct AIOutputStoreTests {

    private func makeTempStore() -> (AIOutputStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIOutputStoreTests-\(UUID().uuidString)")
        return (AIOutputStore(baseDirectory: dir), dir)
    }

    @Test func writeAndRead() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.write(output: "hello world", key: "test-key")
        let result = store.read(key: "test-key")
        #expect(result == "hello world")
    }

    @Test func readMissingKeyReturnsNil() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(store.read(key: "nonexistent") == nil)
    }

    @Test func nestedKeyCreatesDirectories() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.write(output: "nested content", key: "provider/suite.case-id")
        let result = store.read(key: "provider/suite.case-id")
        #expect(result == "nested content")

        let expectedFile = dir
            .appendingPathComponent("provider")
            .appendingPathComponent("suite.case-id.stdout")
        #expect(FileManager.default.fileExists(atPath: expectedFile.path))
    }

    @Test func deleteRemovesFile() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.write(output: "to delete", key: "doomed")
        #expect(store.read(key: "doomed") == "to delete")

        try store.delete(key: "doomed")
        #expect(store.read(key: "doomed") == nil)
    }

    @Test func deleteMissingKeyDoesNotThrow() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.delete(key: "never-existed")
    }

    @Test func overwriteExistingKey() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.write(output: "first", key: "overwrite-me")
        try store.write(output: "second", key: "overwrite-me")
        #expect(store.read(key: "overwrite-me") == "second")
    }
}
