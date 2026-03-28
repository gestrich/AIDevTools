import ClaudeChainService
import Foundation

/// Script runner for pre/post action scripts.
///
/// This module provides functionality to run action scripts with proper
/// error handling, capturing stdout/stderr for logging.
public struct ScriptRunner {
    
    /// Run an action script if it exists.
    ///
    /// - Parameter projectPath: Path to the project directory (e.g., claude-chain/my-project)
    /// - Parameter scriptType: Type of script to run ("pre" or "post")
    /// - Parameter workingDirectory: Directory to run the script from
    /// - Returns: ActionResult with success status, stdout, stderr.
    ///           Returns success=true if script doesn't exist (scripts are optional).
    /// - Throws: ActionScriptError if script exists but fails (non-zero exit code)
    public static func runActionScript(
        projectPath: String,
        scriptType: String,  // "pre" or "post"
        workingDirectory: String
    ) throws -> ActionResult {
        let scriptName = "\(scriptType)-action.sh"
        let scriptPath = URL(fileURLWithPath: projectPath).appendingPathComponent(scriptName).path
        
        // Check if script exists
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("No \(scriptName) found at \(scriptPath), skipping")
            return ActionResult.scriptNotFound(scriptPath: scriptPath)
        }
        
        // Make script executable if needed
        try ensureExecutable(scriptPath: scriptPath)
        
        print("Running \(scriptName) from \(scriptPath)")
        
        // Run the script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: scriptPath)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        var stdout = ""
        var stderr = ""
        
        do {
            try process.run()
            
            // Set up a timeout
            let timeoutSeconds = 600.0  // 10 minute timeout
            let endTime = Date().addingTimeInterval(timeoutSeconds)
            
            // Wait for process with timeout
            while process.isRunning && Date() < endTime {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            if process.isRunning {
                // Process timed out
                process.terminate()
                process.waitUntilExit()
                
                throw ActionScriptError(
                    scriptPath: scriptPath,
                    exitCode: 124,  // Standard timeout exit code
                    stdout: "",
                    stderr: "Script timed out after 600 seconds"
                )
            }
            
            // Read output
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            
            stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            stderr = String(data: stderrData, encoding: .utf8) ?? ""
            
        } catch {
            throw ActionScriptError(
                scriptPath: scriptPath,
                exitCode: 1,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
        
        // Log output
        if !stdout.isEmpty {
            print("--- \(scriptName) stdout ---")
            print(stdout)
        }
        if !stderr.isEmpty {
            print("--- \(scriptName) stderr ---")
            print(stderr)
        }
        
        // Check for failure
        if process.terminationStatus != 0 {
            throw ActionScriptError(
                scriptPath: scriptPath,
                exitCode: Int(process.terminationStatus),
                stdout: stdout,
                stderr: stderr
            )
        }
        
        print("\(scriptName) completed successfully")
        return ActionResult.fromExecution(
            scriptPath: scriptPath,
            exitCode: Int(process.terminationStatus),
            stdout: stdout,
            stderr: stderr
        )
    }
    
    /// Ensure the script file has executable permissions.
    ///
    /// - Parameter scriptPath: Path to the script file
    /// - Throws: Error if permissions cannot be modified
    private static func ensureExecutable(scriptPath: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptPath)
        
        guard let currentPermissions = attributes[.posixPermissions] as? NSNumber else {
            throw NSError(domain: "ScriptRunner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not get file permissions for \(scriptPath)"
            ])
        }
        
        let permissions = currentPermissions.uint16Value
        let userExecuteBit: UInt16 = 0o100  // S_IXUSR
        
        if permissions & userExecuteBit == 0 {
            // Add user execute permission
            let newPermissions = permissions | userExecuteBit
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: newPermissions)], 
                                                   ofItemAtPath: scriptPath)
            print("Made \(scriptPath) executable")
        }
    }
}