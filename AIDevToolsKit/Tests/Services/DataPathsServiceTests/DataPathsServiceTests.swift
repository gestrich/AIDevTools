import Foundation
import Testing
@testable import DataPathsService

struct DataPathsServiceTests {
    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Initialization

    @Test func initCreatesRootDirectory() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }

        _ = try DataPathsService(rootPath: root)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test func initWithTempDirectoryWorks() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }

        let service = try DataPathsService(rootPath: root, fileManager: .default)

        #expect(service.rootPath == root)
    }

    // MARK: - ServicePath Resolution

    @Test func architecturePlannerResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .architecturePlanner)

        #expect(path.path(percentEncoded: false).hasSuffix("architecture-planner"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    @Test func evalSettingsResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .evalSettings)

        #expect(path.path(percentEncoded: false).hasSuffix("eval/settings"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    @Test func planSettingsResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .planSettings)

        #expect(path.path(percentEncoded: false).hasSuffix("plan/settings"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    @Test func repositoriesResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .repositories)

        #expect(path.path(percentEncoded: false).hasSuffix("repositories"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    @Test func repoOutputResolvesToExpectedPath() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .repoOutput("my-repo"))

        #expect(path.path(percentEncoded: false).hasSuffix("repos/my-repo"))
        #expect(path.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))
    }

    // MARK: - Directory Auto-Creation

    @Test func pathForServicePathCreatesDirectory() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: .evalSettings)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test func pathForStringCreatesDirectory() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        let path = try service.path(for: "custom-service")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test func pathForStringWithSubdirectoryCreatesBothDirectories() throws {
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

    @Test func pathForEmptyServiceNameThrows() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        #expect(throws: DataPathsError.self) {
            _ = try service.path(for: "")
        }
    }

    @Test func pathForEmptySubdirectoryThrows() throws {
        let root = makeTempRoot()
        defer { cleanup(root) }
        let service = try DataPathsService(rootPath: root)

        #expect(throws: DataPathsError.self) {
            _ = try service.path(for: "service", subdirectory: "")
        }
    }
}
