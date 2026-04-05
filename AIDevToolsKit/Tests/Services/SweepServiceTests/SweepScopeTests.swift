import Foundation
import Testing
@testable import SweepService

@Suite("SweepScope")
struct SweepScopeTests {

    private let paths = [
        "Sources/A/Bar.swift",
        "Sources/A/Foo.swift",
        "Sources/B/Baz.swift",
        "Sources/C/Qux.swift",
    ]

    @Test("apply: from-only filters by prefix")
    func fromOnlyPrefixFilter() {
        let scope = SweepScope(from: "Sources/A/")
        let result = scope.apply(to: paths)
        #expect(result == ["Sources/A/Bar.swift", "Sources/A/Foo.swift"])
    }

    @Test("apply: from+to filters lexicographic range")
    func fromToLexicographicRange() {
        let scope = SweepScope(from: "Sources/A/", to: "Sources/C/")
        let result = scope.apply(to: paths)
        #expect(result == ["Sources/A/Bar.swift", "Sources/A/Foo.swift", "Sources/B/Baz.swift"])
    }

    @Test("apply: upper bound is exclusive")
    func upperBoundIsExclusive() {
        let scope = SweepScope(from: "Sources/A/", to: "Sources/B/")
        let result = scope.apply(to: paths)
        #expect(result == ["Sources/A/Bar.swift", "Sources/A/Foo.swift"])
    }

    @Test("apply: from prefix with no matches returns empty")
    func fromNoMatches() {
        let scope = SweepScope(from: "Sources/Z/")
        let result = scope.apply(to: paths)
        #expect(result.isEmpty)
    }

    @Test("apply: from+to with same value returns empty")
    func fromEqualsToReturnsEmpty() {
        let scope = SweepScope(from: "Sources/A/", to: "Sources/A/")
        let result = scope.apply(to: paths)
        #expect(result.isEmpty)
    }
}
