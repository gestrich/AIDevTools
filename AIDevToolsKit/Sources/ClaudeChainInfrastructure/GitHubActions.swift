import Foundation

/// GitHub Actions environment integration
public class GitHubActions {
    private let githubOutputFile: String?
    private let githubStepSummaryFile: String?
    
    /// Initialize with GitHub Actions environment
    public init() {
        self.githubOutputFile = ProcessInfo.processInfo.environment["GITHUB_OUTPUT"]
        self.githubStepSummaryFile = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"]
    }
    
    /// Initialize with explicit file paths (for testing)
    public init(outputFile: String?, summaryFile: String?) {
        self.githubOutputFile = outputFile
        self.githubStepSummaryFile = summaryFile
    }
    
    /// Write to $GITHUB_OUTPUT for subsequent steps
    ///
    /// - Parameter name: Output variable name
    /// - Parameter value: Output variable value
    public func writeOutput(name: String, value: String) {
        guard let githubOutputFile = githubOutputFile else {
            print("\(name)=\(value)")
            return
        }
        
        let fileURL = URL(fileURLWithPath: githubOutputFile)
        
        do {
            let content: String
            if value.contains("\n") {
                // Multi-line value - use heredoc format
                let delimiter = "EOF_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                content = "\(name)<<\(delimiter)\n\(value)\n\(delimiter)\n"
            } else {
                // Single-line value - use simple format
                content = "\(name)=\(value)\n"
            }
            
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let data = content.data(using: String.Encoding.utf8) {
                fileHandle.write(data)
            }
        } catch {
            // Fallback to creating/appending to file
            do {
                let content: String
                if value.contains("\n") {
                    let delimiter = "EOF_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                    content = "\(name)<<\(delimiter)\n\(value)\n\(delimiter)\n"
                } else {
                    content = "\(name)=\(value)\n"
                }
                
                let existingContent = (try? String(contentsOf: fileURL)) ?? ""
                let newContent = existingContent + content
                try newContent.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Error writing to GITHUB_OUTPUT: \(error)")
                print("\(name)=\(value)")
            }
        }
    }
    
    /// Write to $GITHUB_STEP_SUMMARY for workflow summary
    ///
    /// - Parameter text: Markdown text to append to summary
    public func writeStepSummary(text: String) {
        guard let githubStepSummaryFile = githubStepSummaryFile else {
            print("SUMMARY: \(text)")
            return
        }
        
        let fileURL = URL(fileURLWithPath: githubStepSummaryFile)
        let content = "\(text)\n"
        
        do {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let data = content.data(using: String.Encoding.utf8) {
                fileHandle.write(data)
            }
        } catch {
            // Fallback to creating/appending to file
            do {
                let existingContent = (try? String(contentsOf: fileURL)) ?? ""
                let newContent = existingContent + content
                try newContent.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Error writing to GITHUB_STEP_SUMMARY: \(error)")
                print("SUMMARY: \(text)")
            }
        }
    }
    
    /// Set error annotation in workflow
    ///
    /// - Parameter message: Error message to display
    public func setError(message: String) {
        print("::error::\(message)")
    }
    
    /// Set notice annotation in workflow
    ///
    /// - Parameter message: Notice message to display
    public func setNotice(message: String) {
        print("::notice::\(message)")
    }
    
    /// Set warning annotation in workflow
    ///
    /// - Parameter message: Warning message to display
    public func setWarning(message: String) {
        print("::warning::\(message)")
    }
}