import Foundation
import SkillScannerSDK

public struct DeterministicGrader: Sendable {

    private let diffUtil = DiffUtil()

    public init() {}

    public func grade(
        case evalCase: EvalCase,
        resultText: String,
        traceCommands: [String],
        toolEvents: [ToolEvent] = [],
        providerCapabilities: ProviderCapabilities,
        repoRoot: URL? = nil,
        skills: [SkillInfo] = []
    ) -> (errors: [String], skipped: [String]) {
        var errors: [String] = []
        var skips: [String] = []
        let normalizedResult = normalize(resultText)

        if let expected = evalCase.expected {
            let normalizedExpected = normalize(expected)
            if normalizedResult != normalizedExpected {
                errors.append("exact output mismatch")
                let diff = diffUtil.unifiedDiff(
                    expected: normalizedExpected,
                    actual: normalizedResult
                )
                if !diff.isEmpty {
                    errors.append(diff)
                }
            }
        }

        for needle in evalCase.mustInclude ?? [] {
            if !normalizedResult.contains(needle) {
                errors.append("missing required substring: \(quoted(needle))")
            }
        }

        for needle in evalCase.mustNotInclude ?? [] {
            if normalizedResult.contains(needle) {
                errors.append("found forbidden substring: \(quoted(needle))")
            }
        }

        let deterministic = evalCase.deterministic
        let traceContains = deterministic?.traceCommandContains ?? []
        let traceNotContains = deterministic?.traceCommandNotContains ?? []

        if (!traceContains.isEmpty || !traceNotContains.isEmpty)
            && !providerCapabilities.supportsToolEventAssertions {
            skips.append("tool-event assertions skipped: provider lacks support")
            return (errors, skips)
        }

        for needle in traceContains {
            if !traceCommands.contains(where: { $0.contains(needle) }) {
                errors.append("missing trace command substring: \(quoted(needle))")
            }
        }

        for needle in traceNotContains {
            if traceCommands.contains(where: { $0.contains(needle) }) {
                errors.append("found forbidden trace command substring: \(quoted(needle))")
            }
        }

        if let order = deterministic?.traceCommandOrder, !order.isEmpty {
            if !providerCapabilities.supportsToolEventAssertions {
                skips.append("trace command order check skipped: provider lacks support")
            } else {
                var searchFrom = 0
                for needle in order {
                    let found = traceCommands[searchFrom...].firstIndex(where: { $0.contains(needle) })
                    if let idx = found {
                        searchFrom = idx + 1
                    } else {
                        errors.append("trace command order violation: \(quoted(needle)) not found after previous ordered command")
                        break
                    }
                }
            }
        }

        if let maxCommands = deterministic?.maxCommands {
            if !providerCapabilities.supportsToolEventAssertions {
                skips.append("max commands check skipped: provider lacks support")
            } else if traceCommands.count > maxCommands {
                errors.append("exceeded max commands: \(traceCommands.count) > \(maxCommands)")
            }
        }

        if let maxRepeated = deterministic?.maxRepeatedCommands {
            if !providerCapabilities.supportsToolEventAssertions {
                skips.append("max repeated commands check skipped: provider lacks support")
            } else {
                var consecutiveCount = 1
                for i in 1..<traceCommands.count {
                    if traceCommands[i] == traceCommands[i - 1] {
                        consecutiveCount += 1
                        if consecutiveCount > maxRepeated {
                            errors.append("thrashing detected: command \(quoted(traceCommands[i])) repeated \(consecutiveCount) times consecutively (max: \(maxRepeated))")
                            break
                        }
                    } else {
                        consecutiveCount = 1
                    }
                }
            }
        }

        if let skillName = deterministic?.skillMustBeInvoked {
            if !providerCapabilities.supportsToolEventAssertions {
                skips.append("skill invocation check skipped: provider lacks support")
            } else {
                let found = skillWasInvoked(skillName, toolEvents: toolEvents, traceCommands: traceCommands, skills: skills, repoRoot: repoRoot)
                if !found {
                    errors.append("skill not invoked: \(quoted(skillName))")
                }
            }
        }

        for skillName in deterministic?.skillMustNotBeInvoked ?? [] {
            if !providerCapabilities.supportsToolEventAssertions {
                skips.append("skill must-not-invoke check skipped: provider lacks support")
                break
            }
            let found = skillWasInvoked(skillName, toolEvents: toolEvents, traceCommands: traceCommands, skills: skills, repoRoot: repoRoot)
            if found {
                errors.append("skill should not have been invoked: \(quoted(skillName))")
            }
        }

        for needle in deterministic?.referenceFileMustBeRead ?? [] {
            if !providerCapabilities.supportsToolEventAssertions {
                skips.append("reference file read check skipped: provider lacks support")
                break
            }
            let foundInToolEvents = toolEvents.contains(where: { ($0.filePath ?? "").contains(needle) })
            let foundInTrace = traceCommands.contains(where: { $0.contains(needle) })
            if !foundInToolEvents && !foundInTrace {
                errors.append("reference file not read: \(quoted(needle))")
            }
        }

        for needle in deterministic?.referenceFileMustNotBeRead ?? [] {
            if !providerCapabilities.supportsToolEventAssertions {
                skips.append("reference file must-not-read check skipped: provider lacks support")
                break
            }
            let foundInToolEvents = toolEvents.contains(where: { ($0.filePath ?? "").contains(needle) })
            let foundInTrace = traceCommands.contains(where: { $0.contains(needle) })
            if foundInToolEvents || foundInTrace {
                errors.append("reference file should not have been read: \(quoted(needle))")
            }
        }

        if let shouldTrigger = evalCase.shouldTrigger, evalCase.mode == .structured {
            if shouldTrigger && (evalCase.mustInclude ?? []).isEmpty {
                errors.append("invalid case: should_trigger=true must define must_include")
            }
            if !shouldTrigger && (evalCase.mustNotInclude ?? []).isEmpty {
                errors.append("invalid case: should_trigger=false must define must_not_include")
            }
        }

        return (errors, skips)
    }
}

extension DeterministicGrader {
    public func gradeFileChanges(
        case evalCase: EvalCase,
        diff: String,
        repoRoot: URL
    ) -> [String] {
        var errors: [String] = []
        let deterministic = evalCase.deterministic

        for path in deterministic?.filesExist ?? [] {
            let resolved = resolvePath(path, relativeTo: repoRoot)
            if !FileManager.default.fileExists(atPath: resolved.path) {
                errors.append("missing expected file: \(path)")
            }
        }

        for path in deterministic?.filesNotExist ?? [] {
            let resolved = resolvePath(path, relativeTo: repoRoot)
            if FileManager.default.fileExists(atPath: resolved.path) {
                errors.append("file should not exist: \(path)")
            }
        }

        for (path, needles) in deterministic?.fileContains ?? [:] {
            let resolved = resolvePath(path, relativeTo: repoRoot)
            guard let contents = try? String(contentsOf: resolved, encoding: .utf8) else {
                errors.append("fileContains: could not read file: \(path)")
                continue
            }
            for needle in needles {
                if !contents.contains(needle) {
                    errors.append("fileContains: \(quoted(needle)) not found in \(path)")
                }
            }
        }

        for (path, needles) in deterministic?.fileNotContains ?? [:] {
            let resolved = resolvePath(path, relativeTo: repoRoot)
            guard let contents = try? String(contentsOf: resolved, encoding: .utf8) else {
                errors.append("fileNotContains: could not read file: \(path)")
                continue
            }
            for needle in needles {
                if contents.contains(needle) {
                    errors.append("fileNotContains: \(quoted(needle)) found in \(path)")
                }
            }
        }

        if let expectedDiff = deterministic?.expectedDiff {
            errors.append(contentsOf: gradeExpectedDiff(expectedDiff, diff: diff))
        }

        return errors
    }
}

private func gradeExpectedDiff(_ expectedDiff: ExpectedDiff, diff: String) -> [String] {
    var errors: [String] = []
    let diffIsEmpty = diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    if expectedDiff.noDiff == true && !diffIsEmpty {
        errors.append("expectedDiff: expected no diff but changes were found")
    }

    if let contains = expectedDiff.contains, !contains.isEmpty {
        if diffIsEmpty {
            errors.append("expectedDiff: expected diff but none found")
        } else {
            for needle in contains {
                if !diff.contains(needle) {
                    errors.append("expectedDiff.contains: \(quoted(needle)) not found in diff")
                }
            }
        }
    }

    for needle in expectedDiff.notContains ?? [] {
        if !diffIsEmpty && diff.contains(needle) {
            errors.append("expectedDiff.notContains: \(quoted(needle)) found in diff")
        }
    }

    return errors
}

private func skillWasInvoked(
    _ skillName: String,
    toolEvents: [ToolEvent],
    traceCommands: [String],
    skills: [SkillInfo],
    repoRoot: URL?
) -> Bool {
    // Only check for genuine skill invocation via the Skill tool.
    // ToolEvent(name: "Skill", skillName: "map-layer") is produced when the AI
    // proactively invokes a skill based on its front matter description.
    //
    // We intentionally do NOT check file reads or bash trace commands, because
    // the AI may encounter skill files accidentally during codebase exploration
    // (e.g. grepping for related terms, listing directories). That is NOT
    // genuine invocation — it's incidental discovery.
    return toolEvents.contains(where: { $0.skillName == skillName })
}

private func normalize(_ value: String) -> String {
    if value.hasSuffix("\n") {
        return String(value.dropLast())
    }
    return value
}

private func quoted(_ value: String) -> String {
    "'\(value)'"
}

private func resolvePath(_ maybRelative: String, relativeTo base: URL) -> URL {
    if maybRelative.hasPrefix("/") {
        return URL(fileURLWithPath: maybRelative)
    }
    return base.appendingPathComponent(maybRelative).standardized
}
