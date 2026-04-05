import Foundation
import Testing
@testable import SweepService

@Suite("SweepState")
struct SweepStateTests {

    @Test("load: returns empty state when file does not exist")
    func missingFileReturnsEmptyState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let state = try SweepState.load(from: url)
        #expect(state.cursor == nil)
        #expect(state.lastRunDate == nil)
    }

    @Test("roundTrip: preserves cursor and lastRunDate")
    func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("state.json")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SweepState(cursor: "Sources/Services/Foo.swift", lastRunDate: date)
        try original.save(to: url)

        let loaded = try SweepState.load(from: url)
        #expect(loaded.cursor == "Sources/Services/Foo.swift")
        let diff = abs(loaded.lastRunDate!.timeIntervalSince(date))
        #expect(diff < 1.0)
    }

    @Test("roundTrip: nil cursor preserved")
    func nilCursorPreserved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("state.json")
        let original = SweepState(cursor: nil)
        try original.save(to: url)

        let loaded = try SweepState.load(from: url)
        #expect(loaded.cursor == nil)
    }

    @Test("save: creates intermediate directories")
    func savesWithIntermediateDirectories() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }

        let url = base.appendingPathComponent("nested/deeply/state.json")
        try SweepState(cursor: "Sources/A.swift").save(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }
}
