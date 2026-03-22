import Foundation

public struct TogglePhaseUseCase: Sendable {

    public init() {}

    /// Toggles a phase checkbox in a plan markdown file.
    /// - Parameters:
    ///   - planURL: Path to the plan markdown file
    ///   - phaseIndex: Zero-based index of the phase to toggle
    /// - Returns: The updated file content
    public func run(planURL: URL, phaseIndex: Int) throws -> String {
        let content = try String(contentsOf: planURL, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        var currentPhase = 0

        for (lineIndex, line) in lines.enumerated() {
            if line.hasPrefix("## - [x] ") || line.hasPrefix("## - [ ] ") {
                if currentPhase == phaseIndex {
                    if line.hasPrefix("## - [x] ") {
                        lines[lineIndex] = "## - [ ] " + String(line.dropFirst("## - [x] ".count))
                    } else {
                        lines[lineIndex] = "## - [x] " + String(line.dropFirst("## - [ ] ".count))
                    }
                    break
                }
                currentPhase += 1
            }
        }

        let updated = lines.joined(separator: "\n")
        try updated.write(to: planURL, atomically: true, encoding: .utf8)
        return updated
    }
}
