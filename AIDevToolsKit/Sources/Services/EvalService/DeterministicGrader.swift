import Foundation

public struct DeterministicGradeResult: Sendable {
    public var errors: [String]
    public var skipped: [String]
    public var skillChecks: [SkillCheckResult]

    public init(errors: [String] = [], skipped: [String] = [], skillChecks: [SkillCheckResult] = []) {
        self.errors = errors
        self.skipped = skipped
        self.skillChecks = skillChecks
    }
}

public struct DeterministicGrader: Sendable {

    private let diffUtil = DiffUtil()

    public init() {}

    public func grade(
        case evalCase: EvalCase,
        resultText: String,
        traceCommands: [String],
        toolEvents: [ToolEvent] = [],
        providerCapabilities: ProviderCapabilities,
        skillChecks: [SkillCheckResult] = []
    ) -> DeterministicGradeResult {
        var errors: [String] = []
        var skipped: [String] = []
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
            skipped.append("tool-event assertions skipped: provider lacks support")
            return DeterministicGradeResult(errors: errors, skipped: skipped, skillChecks: skillChecks)
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
                skipped.append("trace command order check skipped: provider lacks support")
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
                skipped.append("max commands check skipped: provider lacks support")
            } else if traceCommands.count > maxCommands {
                errors.append("exceeded max commands: \(traceCommands.count) > \(maxCommands)")
            }
        }

        if let maxRepeated = deterministic?.maxRepeatedCommands {
            if !providerCapabilities.supportsToolEventAssertions {
                skipped.append("max repeated commands check skipped: provider lacks support")
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

        for assertion in evalCase.skills ?? [] {
            let skillName = assertion.skill
            let check = skillChecks.first { check in
                switch check {
                case .invoked(let skill, _): return skill.name == skillName
                case .notInvoked(let name): return name == skillName
                case .skipped(let name, _): return name == skillName
                }
            }
            if assertion.mustBeInvoked == true {
                if let check, case .notInvoked = check {
                    errors.append("skill not invoked: \(quoted(skillName))")
                }
            }
            if assertion.mustNotBeInvoked == true {
                if let check, case .invoked = check {
                    errors.append("skill should not have been invoked: \(quoted(skillName))")
                }
            }
        }

        for needle in deterministic?.referenceFileMustBeRead ?? [] {
            if !providerCapabilities.supportsToolEventAssertions {
                skipped.append("reference file read check skipped: provider lacks support")
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
                skipped.append("reference file must-not-read check skipped: provider lacks support")
                break
            }
            let foundInToolEvents = toolEvents.contains(where: { ($0.filePath ?? "").contains(needle) })
            let foundInTrace = traceCommands.contains(where: { $0.contains(needle) })
            if foundInToolEvents || foundInTrace {
                errors.append("reference file should not have been read: \(quoted(needle))")
            }
        }

        if evalCase.mode == .structured {
            for assertion in evalCase.skills ?? [] {
                if assertion.shouldTrigger == true && (evalCase.mustInclude ?? []).isEmpty {
                    errors.append("invalid case: should_trigger=true must define must_include")
                }
                if assertion.shouldTrigger == false && (evalCase.mustNotInclude ?? []).isEmpty {
                    errors.append("invalid case: should_trigger=false must define must_not_include")
                }
            }
        }

        return DeterministicGradeResult(errors: errors, skipped: skipped, skillChecks: skillChecks)
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
