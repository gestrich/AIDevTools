/// Configuration file loading and validation
///
/// NOTE: This module currently contains I/O operations which violates domain layer principles.
/// The file loading logic should be refactored to infrastructure layer in a future phase.
/// For now, keeping as-is to complete Phase 2 migration.
import Foundation
import Yams

public struct Config {
    
    /// Load YAML configuration file and return parsed content
    ///
    /// - Parameter filePath: Path to YAML configuration file (.yml or .yaml)
    /// - Returns: Parsed configuration as dictionary
    /// - Throws: FileNotFoundError if file doesn't exist, ConfigurationError if file is invalid YAML or contains deprecated fields
    public static func loadConfig(filePath: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw FileNotFoundError("File not found: \(filePath)")
        }
        
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            return try loadConfigFromString(content: content, sourceName: filePath)
        } catch let error as ConfigurationError {
            throw error
        } catch let error as FileNotFoundError {
            throw error
        } catch {
            throw ConfigurationError("Invalid YAML in \(filePath): \(error.localizedDescription)")
        }
    }
    
    /// Load YAML configuration from string content
    ///
    /// - Parameters:
    ///   - content: YAML content as string
    ///   - sourceName: Name of the source (for error messages)
    /// - Returns: Parsed configuration as dictionary
    /// - Throws: ConfigurationError if content is invalid YAML or contains deprecated fields
    public static func loadConfigFromString(content: String, sourceName: String = "config") throws -> [String: Any] {
        do {
            guard let config = try Yams.load(yaml: content) as? [String: Any] else {
                throw ConfigurationError("Invalid YAML in \(sourceName): Root element must be an object")
            }
            
            // Validate configuration - reject deprecated fields
            if config["branchPrefix"] != nil {
                throw ConfigurationError(
                    "The 'branchPrefix' field is no longer supported. " +
                    "ClaudeChain now uses a standard branch format: claude-chain-{project}-{index}. " +
                    "Please remove 'branchPrefix' from \(sourceName)"
                )
            }
            
            return config
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError("Invalid YAML in \(sourceName): \(error.localizedDescription)")
        }
    }
    
    /// Substitute {{VARIABLE}} placeholders in template
    ///
    /// - Parameters:
    ///   - template: Template string with {{VAR}} placeholders
    ///   - variables: Dictionary of variables to substitute
    /// - Returns: Template with substitutions applied
    public static func substituteTemplate(_ template: String, variables: [String: Any]) -> String {
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: String(describing: value))
        }
        return result
    }
    
    /// Validate that spec.md contains checklist items in the correct format
    ///
    /// - Parameter specFile: Path to spec.md file
    /// - Returns: True if valid format (contains at least one checklist item)
    /// - Throws: FileNotFoundError if spec file doesn't exist, ConfigurationError if spec file has invalid format
    public static func validateSpecFormat(specFile: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: specFile) else {
            throw FileNotFoundError("Spec file not found: \(specFile)")
        }
        
        let content = try String(contentsOfFile: specFile, encoding: .utf8)
        return try validateSpecFormatFromString(content: content, sourceName: specFile)
    }
    
    /// Validate that spec content contains checklist items in the correct format
    ///
    /// - Parameters:
    ///   - content: Spec content as string
    ///   - sourceName: Name of the source (for error messages)
    /// - Returns: True if valid format (contains at least one checklist item)
    /// - Throws: ConfigurationError if spec has invalid format
    public static func validateSpecFormatFromString(content: String, sourceName: String = "spec.md") throws -> Bool {
        var hasChecklistItem = false
        
        for line in content.components(separatedBy: .newlines) {
            // Check for unchecked or checked task items
            let pattern = #"^\s*- \[[xX ]\]"#
            if line.range(of: pattern, options: .regularExpression) != nil {
                hasChecklistItem = true
                break
            }
        }
        
        if !hasChecklistItem {
            throw ConfigurationError(
                "Invalid spec.md format: No checklist items found. " +
                "The file must contain at least one '- [ ]' or '- [x]' item."
            )
        }
        
        return true
    }
}