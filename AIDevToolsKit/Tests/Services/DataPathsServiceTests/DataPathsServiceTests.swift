import Foundation
import Testing
@testable import DataPathsService

@Suite("DataPathsService")
struct DataPathsServiceTests {
    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Initialization

    @Test("init creates root directory") func initCreatesRootDirectory() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }

        _ = try DataPathsService(rootPath: root)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("init with temp directory works") func initWithTempDirectoryWorks() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }

        let service = try DataPathsService(rootPath: root, fileManager: .default)

        #expect(service.rootPath == root)
    }

    // MARK: - ServicePath Resolution

    @Test("architecturePlanner resolves to expected path") func architecturePlannerResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .architecturePlanner)

        #expect(path.path(percentEncoded: false).hasSuffix("services/architecture-planner"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    @Test("repositories resolves to expected path") func repositoriesResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .repositories)

        #expect(path.path(percentEncoded: false).hasSuffix("services/repositories"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    @Test("claudeChainWorktrees resolves to services/claude-chain/worktrees")
    func claudeChainWorktreesRelativePath() {
        #expect(ServicePath.claudeChainWorktrees.relativePath == "services/claude-chain/worktrees")
    }

    @Test("planWorktrees resolves to services/plan/worktrees")
    func planWorktreesRelativePath() {
        #expect(ServicePath.planWorktrees.relativePath == "services/plan/worktrees")
    }

    @Test("evalsOutput resolves to expected path") func evalsOutputResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .evalsOutput("my-repo"))

        #expect(path.path(percentEncoded: false).hasSuffix("services/evals/my-repo"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    // MARK: - Directory Auto-Creation

    @Test("path(for:) creates directory for ServicePath") func pathForServicePathCreatesDirectory() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .repositories)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("path(for:) creates directory for string") func pathForStringCreatesDirectory() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: "custom-service")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("path(for:subdirectory:) creates both directories") func pathForStringWithSubdirectoryCreatesBothDirectories() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: "service", subdirectory: "sub")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
        #expect(path.path(percentEncoded: false).hasSuffix("service/sub"))
    }

    // MARK: - Error Cases

    @Test("path(for:) throws for empty service name") func pathForEmptyServiceNameThrows() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        #expect(throws: DataPathsError.self) {
            _ = try service.path(for: "")
        }
    }

    @Test("path(for:subdirectory:) throws for empty subdirectory") func pathForEmptySubdirectoryThrows() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        #expect(throws: DataPathsError.self) {
            _ = try service.path(for: "service", subdirectory: "")
        }
    }
}
