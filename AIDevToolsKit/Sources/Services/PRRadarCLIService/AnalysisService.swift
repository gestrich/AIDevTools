import AIOutputSDK
import Foundation
import PRRadarConfigService
import PRRadarModelsService

public struct AnalysisService: Sendable {
    private let aiClient: any AIClient

    private static let defaultModel = "claude-sonnet-4-20250514"

    private static let evaluationPromptTemplate = """
    You are a code reviewer evaluating whether code violates a specific rule.

    ## Rule: {rule_name}

    {rule_description}

    ### Rule Details

    {rule_content}

    ## Focus Area: {focus_area_description}

    File: {file_path}
    Lines: {start_line}-{end_line}

    **Important:** Only evaluate the code within the focus area boundaries shown below.
    Ignore any surrounding code in the diff hunk.

    **Code to review:**

    ```diff
    {diff_content}
    ```

    ## Codebase Context

    The PR branch is checked out locally at: {repo_path}
    You have full access to the codebase for additional context.

    - For rules that evaluate isolated patterns (naming conventions, signature
      format), the focus area content above is typically sufficient.
    - For rules that evaluate broader concerns (architecture, client usage,
      integration patterns), explore the codebase as needed. For example,
      search for callers of a method, check how similar patterns are used
      elsewhere, or read surrounding code for context.

    Use your judgment: explore when it would improve the quality of your
    review, but don't explore unnecessarily for simple pattern checks.

    ## Instructions

    Analyze the code changes shown in the diff and determine if they violate the rule.

    Focus ONLY on the added/changed lines (lines starting with `+`). Context lines \
    (no prefix or starting with `-`) are provided for understanding but should not be \
    evaluated for violations.

    Consider:
    1. Does the new or modified code violate the rule?
    2. How severe is each violation (1-10 scale)?

    For the comment field: If the rule includes a "GitHub Comment" section, use that \
    exact text as your comment unless there is critical context-specific information \
    that must be added. Keep comments concise.

    Report ALL violations you find — each as a separate entry with its own score, \
    comment, file path, and line number.
    If the code does not violate the rule, return an empty violations array.
    """

    // Schema stored as nonisolated(unsafe) to avoid [String: Any] Sendable issues
    nonisolated(unsafe) private static let evaluationOutputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "violations": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "score": [
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 10,
                            "description": "Severity score: 1-4 minor, 5-7 moderate, 8-10 severe",
                        ],
                        "comment": [
                            "type": "string",
                            "description": "The GitHub comment to post. If the rule includes a 'GitHub Comment' section, use that exact format unless there is critical context-specific information to add. Keep it concise.",
                        ],
                        "file_path": [
                            "type": "string",
                            "description": "Path to the file containing the code",
                        ],
                        "line_number": [
                            "type": ["integer", "null"],
                            "description": "Specific line number of the violation",
                        ],
                    ] as [String: Any],
                    "required": ["score", "comment"],
                ] as [String: Any],
                "description": "List of violations found. Empty array if no violations.",
            ] as [String: Any],
        ] as [String: Any],
        "required": ["violations"],
    ]

    private static let evaluationOutputSchemaString: String = {
        guard let data = try? JSONSerialization.data(withJSONObject: evaluationOutputSchema),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }()

    public init(aiClient: any AIClient) {
        self.aiClient = aiClient
    }

    /// Analyze a single task using Claude via AIClient.
    public func analyzeTask(
        _ task: RuleRequest,
        repoPath: String,
        transcriptDir: String? = nil,
        onPrompt: ((String, RuleRequest) -> Void)? = nil,
        onStreamEvent: ((AIStreamEvent) -> Void)? = nil
    ) async throws -> RuleOutcome {
        let model = task.rule.model ?? Self.defaultModel
        let focusedContent = task.focusArea.getFocusedContent()

        let prompt = Self.evaluationPromptTemplate
            .replacingOccurrences(of: "{rule_name}", with: task.rule.name)
            .replacingOccurrences(of: "{rule_description}", with: task.rule.description)
            .replacingOccurrences(of: "{rule_content}", with: task.rule.content)
            .replacingOccurrences(of: "{focus_area_description}", with: task.focusArea.description)
            .replacingOccurrences(of: "{file_path}", with: task.focusArea.filePath)
            .replacingOccurrences(of: "{start_line}", with: String(task.focusArea.startLine))
            .replacingOccurrences(of: "{end_line}", with: String(task.focusArea.endLine))
            .replacingOccurrences(of: "{diff_content}", with: focusedContent)
            .replacingOccurrences(of: "{repo_path}", with: repoPath)

        onPrompt?(prompt, task)

        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            model: model,
            workingDirectory: repoPath
        )

        let startedAt = ISO8601DateFormatter().string(from: Date())
        let accumulator = EventAccumulator()

        let result = try await aiClient.runStructured(
            ViolationsResponse.self,
            prompt: prompt,
            jsonSchema: Self.evaluationOutputSchemaString,
            options: options,
            onOutput: { text in
                accumulator.append(OutputEntry(type: .text, content: text))
            },
            onStreamEvent: { event in
                onStreamEvent?(event)
                switch event {
                case .toolUse(let name, _):
                    accumulator.append(OutputEntry(type: .toolUse, label: name))
                case .metrics(let duration, let cost, _):
                    accumulator.setMetrics(
                        cost: cost ?? 0.0,
                        durationMs: duration.map { Int($0 * 1000) } ?? 0
                    )
                default:
                    break
                }
            }
        )

        if let transcriptDir {
            var entries = accumulator.entries
            entries.append(OutputEntry(type: .result, content: result.rawOutput))
            let output = EvaluationOutput(
                identifier: task.taskId,
                filePath: task.focusArea.filePath,
                rule: task.rule,
                source: .ai(model: model, prompt: prompt),
                startedAt: startedAt,
                durationMs: accumulator.durationMs,
                costUsd: accumulator.costUsd,
                entries: entries
            )
            try? EvaluationOutputWriter.write(output, to: transcriptDir)
        }

        let violations = result.value.violations.map { v in
            let aiFilePath = v.filePath
            let filePath = (aiFilePath?.isEmpty == false) ? aiFilePath! : task.focusArea.filePath
            let lineNumber = v.lineNumber ?? task.focusArea.startLine
            return Violation(
                score: v.score ?? 1,
                comment: v.comment ?? "Evaluation completed",
                filePath: filePath,
                lineNumber: lineNumber
            )
        }

        let ruleResult = RuleResult(
            taskId: task.taskId,
            ruleName: task.rule.name,
            filePath: task.focusArea.filePath,
            analysisMethod: .ai(model: model, costUsd: accumulator.costUsd),
            durationMs: accumulator.durationMs,
            violations: violations
        )

        return .success(ruleResult)
    }

    /// Run analysis for all tasks, writing results to the evaluations directory.
    ///
    /// Tasks are grouped by type: regex first (instant), then scripts (fast, local),
    /// then AI tasks (expensive, sequential via Claude agent).
    public func runBatchAnalysis(
        tasks: [RuleRequest],
        evalsDir: String,
        repoPath: String,
        prDiff: PRDiff? = nil,
        onStart: ((Int, Int, RuleRequest) -> Void)? = nil,
        onResult: ((Int, Int, RuleOutcome) -> Void)? = nil,
        onPrompt: ((String, RuleRequest) -> Void)? = nil,
        onStreamEvent: ((AIStreamEvent) -> Void)? = nil
    ) async throws -> [RuleOutcome] {
        try FileManager.default.createDirectory(atPath: evalsDir, withIntermediateDirectories: true)

        let regexTasks = tasks.filter { $0.rule.analysisType == .regex }
        let scriptTasks = tasks.filter { $0.rule.analysisType == .script }
        let aiTasks = tasks.filter { $0.rule.analysisType == .ai }
        let orderedTasks = regexTasks + scriptTasks + aiTasks

        var results: [RuleOutcome] = []
        let total = orderedTasks.count
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let regexService = RegexAnalysisService()
        let allHunks = prDiff?.hunks ?? []

        for (i, task) in orderedTasks.enumerated() {
            let index = i + 1
            onStart?(index, total, task)

            var result: RuleOutcome

            switch task.rule.analysisType {
            case .regex:
                guard let pattern = task.rule.violationRegex else {
                    result = .error(RuleError(
                        taskId: task.taskId,
                        ruleName: task.rule.name,
                        filePath: task.focusArea.filePath,
                        errorMessage: "Regex rule missing violationRegex pattern",
                        analysisMethod: .regex(pattern: "")
                    ))
                    break
                }
                let focusedHunks = PRHunk.filterForFocusArea(allHunks, focusArea: task.focusArea)
                let (regexOutcome, regexOutput) = regexService.analyzeTask(task, pattern: pattern, hunks: focusedHunks)
                result = regexOutcome
                try EvaluationOutputWriter.write(regexOutput, to: evalsDir)

                let data = try encoder.encode(result)
                let resultPath = "\(evalsDir)/\(PRRadarPhasePaths.dataFilePrefix)\(task.taskId).json"
                try data.write(to: URL(fileURLWithPath: resultPath))

            case .script:
                guard let scriptPath = task.rule.violationScript else {
                    result = .error(RuleError(
                        taskId: task.taskId,
                        ruleName: task.rule.name,
                        filePath: task.focusArea.filePath,
                        errorMessage: "Script rule missing violationScript path",
                        analysisMethod: .script(path: "")
                    ))
                    break
                }
                let scriptService = ScriptAnalysisService()
                let focusedScriptHunks = PRHunk.filterForFocusArea(allHunks, focusArea: task.focusArea)
                let (scriptOutcome, scriptOutput) = scriptService.analyzeTask(task, scriptPath: scriptPath, repoPath: repoPath, hunks: focusedScriptHunks)
                result = scriptOutcome
                try EvaluationOutputWriter.write(scriptOutput, to: evalsDir)

                let scriptData = try encoder.encode(result)
                let scriptResultPath = "\(evalsDir)/\(PRRadarPhasePaths.dataFilePrefix)\(task.taskId).json"
                try scriptData.write(to: URL(fileURLWithPath: scriptResultPath))

            case .ai:
                do {
                    result = try await analyzeTask(
                        task,
                        repoPath: repoPath,
                        transcriptDir: evalsDir,
                        onPrompt: onPrompt,
                        onStreamEvent: onStreamEvent
                    )

                    let data = try encoder.encode(result)
                    let resultPath = "\(evalsDir)/\(PRRadarPhasePaths.dataFilePrefix)\(task.taskId).json"
                    try data.write(to: URL(fileURLWithPath: resultPath))
                } catch {
                    result = .error(RuleError(
                        taskId: task.taskId,
                        ruleName: task.rule.name,
                        filePath: task.focusArea.filePath,
                        errorMessage: error.localizedDescription,
                        analysisMethod: .ai(model: task.rule.model ?? Self.defaultModel, costUsd: 0)
                    ))
                }
            }

            results.append(result)
            onResult?(index, total, result)
        }

        return results
    }
}

// MARK: - Private Types

private struct ViolationsResponse: Decodable, Sendable {
    let violations: [ViolationItem]

    struct ViolationItem: Decodable, Sendable {
        let comment: String?
        let filePath: String?
        let lineNumber: Int?
        let score: Int?

        enum CodingKeys: String, CodingKey {
            case comment
            case filePath = "file_path"
            case lineNumber = "line_number"
            case score
        }
    }
}

final class EventAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _costUsd: Double = 0.0
    private var _durationMs: Int = 0
    private var _entries: [OutputEntry] = []

    func append(_ entry: OutputEntry) {
        lock.lock()
        defer { lock.unlock() }
        _entries.append(entry)
    }

    func setMetrics(cost: Double, durationMs: Int) {
        lock.lock()
        defer { lock.unlock() }
        _costUsd = cost
        _durationMs = durationMs
    }

    var costUsd: Double {
        lock.lock()
        defer { lock.unlock() }
        return _costUsd
    }

    var durationMs: Int {
        lock.lock()
        defer { lock.unlock() }
        return _durationMs
    }

    var entries: [OutputEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }
}
