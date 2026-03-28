import ClaudeChainService
import Foundation

/// Filesystem operations
public struct FileSystemOperations {
    
    /// Read file contents as string
    ///
    /// - Parameter path: URL to file to read
    /// - Returns: File contents as string
    /// - Throws: FileNotFoundError if file doesn't exist, or other I/O errors
    public static func readFile(path: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw FileNotFoundError("File not found: \(path.path)")
        }
        
        do {
            return try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw error
        }
    }
    
    /// Write string content to file
    ///
    /// - Parameter path: URL to file to write
    /// - Parameter content: Content to write
    /// - Throws: I/O errors if file cannot be written
    public static func writeFile(path: URL, content: String) throws {
        do {
            try content.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            throw error
        }
    }
    
    /// Check if file exists
    ///
    /// - Parameter path: URL to check
    /// - Returns: True if file exists, False otherwise
    public static func fileExists(path: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
    
    /// Find a file by name starting from a directory
    ///
    /// - Parameter startDir: Directory URL to start searching from
    /// - Parameter filename: Name of file to find
    /// - Parameter maxDepth: Maximum directory depth to search (nil for unlimited)
    /// - Returns: URL to file if found, nil otherwise
    public static func findFile(startDir: URL, filename: String, maxDepth: Int? = nil) -> URL? {
        func search(directory: URL, currentDepth: Int = 0) -> URL? {
            if let maxDepth = maxDepth, currentDepth > maxDepth {
                return nil
            }
            
            // Check current directory
            let candidate = directory.appendingPathComponent(filename)
            if fileExists(path: candidate) {
                return candidate
            }
            
            // Search subdirectories
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                for subdir in contents {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDirectory),
                       isDirectory.boolValue,
                       !subdir.lastPathComponent.hasPrefix(".") {
                        if let result = search(directory: subdir, currentDepth: currentDepth + 1) {
                            return result
                        }
                    }
                }
            } catch {
                // Ignore permission errors and continue
            }
            
            return nil
        }
        
        return search(directory: startDir)
    }
}