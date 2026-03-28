import ArgumentParser
import ClaudeChainInfrastructure
import Foundation

/// Parse Claude Code execution result.
///
/// Reads the JSON execution file from claude-code-action and extracts
/// the structured output to determine success/failure and error messages.
public struct ParseClaudeResultCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "parse-claude-result",
        abstract: "Parse Claude Code execution result for success/failure"
    )
    
    @Argument(help: "Path to the Claude Code execution JSON file")
    public var executionFile: String
    
    @Option(name: .long, help: "Type of result being parsed (main or summary)")
    public var resultType: String = "main"
    
    public init() {}
    
    public func run() throws {
        let gh = GitHubActions()
        let exitCode = cmdParseClaudeResult(
            gh: gh,
            executionFile: executionFile,
            resultType: resultType
        )
        
        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }
}

/// Parse Claude Code execution result from JSON file.
///
/// Reads the execution file and extracts structured_output to determine
/// if the task completed successfully.
///
/// - Parameters:
///   - gh: GitHub Actions helper instance
///   - executionFile: Path to the Claude Code execution JSON file
///   - resultType: Type of result being parsed ("main" or "summary")
/// - Returns: Exit code (0 for success, 1 for failure)
private func cmdParseClaudeResult(
    gh: GitHubActions,
    executionFile: String,
    resultType: String
) -> Int {
    if executionFile.isEmpty {
        print("No execution file provided for \(resultType) task")
        gh.writeOutput(name: "success", value: "false")
        gh.writeOutput(name: "error_message", value: "No execution file provided")
        return 0  // Not an error in the parsing itself
    }
    
    if !FileManager.default.fileExists(atPath: executionFile) {
        print("Execution file not found: \(executionFile)")
        gh.writeOutput(name: "success", value: "false")
        gh.writeOutput(name: "error_message", value: "Execution file not found: \(executionFile)")
        return 0  // Not an error in the parsing itself
    }
    
    let executionData: Any
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: executionFile))
        executionData = try JSONSerialization.jsonObject(with: data, options: [])
    } catch {
        print("Failed to parse execution file as JSON: \(error)")
        gh.writeOutput(name: "success", value: "false")
        gh.writeOutput(name: "error_message", value: "Invalid JSON in execution file: \(error)")
        return 0
    }
    
    // Extract structured output from the execution data
    let structuredOutput = extractStructuredOutput(executionData: executionData)
    
    if structuredOutput == nil {
        // No structured output found - this might happen if Claude didn't
        // produce the expected JSON format
        print("No structured output found in execution file")
        // Default to success if Claude ran but didn't produce structured output
        // This maintains backward compatibility
        gh.writeOutput(name: "success", value: "true")
        gh.writeOutput(name: "error_message", value: "")
        gh.writeOutput(name: "summary", value: "")
        return 0
    }
    
    let structuredDict = structuredOutput!
    
    // Extract fields from structured output
    let success = structuredDict["success"] as? Bool ?? true
    let errorMessage = structuredDict["error_message"] as? String ?? ""
    
    // Main task has "summary", summary task has "summary_content"
    let summaryFromDict = structuredDict["summary"] as? String ?? ""
    let summaryContentFromDict = structuredDict["summary_content"] as? String ?? ""
    let summary = !summaryFromDict.isEmpty ? summaryFromDict : summaryContentFromDict
    
    // Write outputs
    gh.writeOutput(name: "success", value: success ? "true" : "false")
    gh.writeOutput(name: "error_message", value: errorMessage)
    gh.writeOutput(name: "summary", value: summary)
    
    if success {
        print("✅ Claude Code \(resultType) task completed successfully")
        if !summary.isEmpty {
            let truncatedSummary = summary.count > 100 ? "\(String(summary.prefix(100)))..." : summary
            print("   Summary: \(truncatedSummary)")
        }
        return 0
    } else {
        print("❌ Claude Code \(resultType) task failed")
        if !errorMessage.isEmpty {
            print("   Error: \(errorMessage)")
        }
        return 1
    }
}

/// Extract structured_output from Claude Code execution data.
///
/// The execution file format when using --verbose contains a list of events.
/// The structured output is in the last element's result.structured_output field.
///
/// When not using --verbose, the execution_data may be the direct result object.
///
/// - Parameter executionData: Parsed JSON from execution file
/// - Returns: The structured output dict, or nil if not found
private func extractStructuredOutput(executionData: Any) -> [String: Any]? {
    // Handle case where execution_data is an array (verbose mode)
    if let executionArray = executionData as? [Any], !executionArray.isEmpty {
        // Look for the last element with structured_output
        for item in executionArray.reversed() {
            if let itemDict = item as? [String: Any] {
                // Check for result.structured_output pattern
                if let result = itemDict["result"] as? [String: Any],
                   let structuredOutput = result["structured_output"] as? [String: Any] {
                    return structuredOutput
                }
                // Check for direct structured_output
                if let structuredOutput = itemDict["structured_output"] as? [String: Any] {
                    return structuredOutput
                }
            }
        }
    }
    
    // Handle case where execution_data is a dictionary
    if let executionDict = executionData as? [String: Any] {
        // Direct structured_output
        if let structuredOutput = executionDict["structured_output"] as? [String: Any] {
            return structuredOutput
        }
        // Nested in result
        if let result = executionDict["result"] as? [String: Any],
           let structuredOutput = result["structured_output"] as? [String: Any] {
            return structuredOutput
        }
    }
    
    return nil
}