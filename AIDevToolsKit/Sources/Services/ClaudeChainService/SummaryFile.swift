/// Domain model for PR summary file content.
import Foundation

/// Domain model for PR summary file content.
///
/// This class handles parsing of AI-generated summary files.
/// Formatting is handled by PullRequestCreatedReport.
public struct SummaryFile {
    public let content: String?
    
    public init(content: String?) {
        self.content = content
    }
    
    /// Read and parse summary file.
    ///
    /// - Parameter filePath: Path to summary file
    /// - Returns: SummaryFile with content, or nil content if file missing/empty
    public static func fromFile(_ filePath: String) -> SummaryFile {
        guard !filePath.isEmpty && FileManager.default.fileExists(atPath: filePath) else {
            return SummaryFile(content: nil)
        }
        
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                return SummaryFile(content: nil)
            }
            return SummaryFile(content: content)
        } catch {
            return SummaryFile(content: nil)
        }
    }
    
    /// Check if summary has content.
    public var hasContent: Bool {
        return content != nil && !content!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}