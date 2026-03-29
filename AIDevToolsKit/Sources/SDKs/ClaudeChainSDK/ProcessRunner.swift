import Foundation

/// Process runner utility for executing shell commands
public struct ProcessRunner {
    
    /// Run a shell command and return the result
    ///
    /// - Parameter cmd: Command and arguments as array
    /// - Parameter check: Whether to raise exception on non-zero exit
    /// - Parameter captureOutput: Whether to capture stdout/stderr
    /// - Returns: Process result
    /// - Throws: Error if command fails and check=true
    public static func runCommand(cmd: [String], check: Bool = true, captureOutput: Bool = true) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = cmd

        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        let brewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let missingPaths = brewPaths.filter { !currentPath.contains($0) }
        if !missingPaths.isEmpty {
            environment["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        process.environment = environment
        
        var stdout = ""
        var stderr = ""
        
        if captureOutput {
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            try process.run()
            process.waitUntilExit()
            
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            
            stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            stderr = String(data: stderrData, encoding: .utf8) ?? ""
        } else {
            try process.run()
            process.waitUntilExit()
        }
        
        if check && process.terminationStatus != 0 {
            throw NSError(domain: "CommandError", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Command failed: \(cmd.joined(separator: " "))\n\(stderr)"
            ])
        }
        
        return (status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}