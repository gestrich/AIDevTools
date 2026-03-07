import Foundation

public struct DiffUtil: Sendable {

    public init() {}

    public func unifiedDiff(
        expected: String,
        actual: String,
        fromFile: String = "expected",
        toFile: String = "actual"
    ) -> String {
        let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let actualLines = actual.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let lcs = longestCommonSubsequence(expectedLines, actualLines)

        var result: [String] = []
        result.append("--- \(fromFile)")
        result.append("+++ \(toFile)")

        var ei = 0
        var ai = 0
        var li = 0

        while ei < expectedLines.count || ai < actualLines.count {
            if li < lcs.count, ei < expectedLines.count, ai < actualLines.count,
               expectedLines[ei] == lcs[li], actualLines[ai] == lcs[li] {
                result.append(" \(lcs[li])")
                ei += 1
                ai += 1
                li += 1
            } else if ei < expectedLines.count && (li >= lcs.count || expectedLines[ei] != lcs[li]) {
                result.append("-\(expectedLines[ei])")
                ei += 1
            } else if ai < actualLines.count {
                result.append("+\(actualLines[ai])")
                ai += 1
            }
        }

        return result.joined(separator: "\n")
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }
}
