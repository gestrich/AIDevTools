/// Tests for Claude Code JSON schema definitions
import XCTest
import Foundation
@testable import ClaudeChainService

class ClaudeSchemasTests: XCTestCase {
    
    // MARK: - Main Task Schema Tests
    
    func testMainTaskSchemaIsValidJSONSchema() throws {
        // Main task schema has valid JSON Schema structure
        let schema = ClaudeSchemas.mainTaskSchema
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertNotNil(schema["properties"])
        XCTAssertNotNil(schema["required"])
    }
    
    func testMainTaskSchemaHasRequiredProperties() throws {
        // Main task schema has success and summary as required
        let schema = ClaudeSchemas.mainTaskSchema
        let required = schema["required"] as? [String] ?? []
        XCTAssertTrue(required.contains("success"))
        XCTAssertTrue(required.contains("summary"))
    }
    
    func testMainTaskSchemaHasSuccessProperty() throws {
        // Main task schema has success as boolean
        let schema = ClaudeSchemas.mainTaskSchema
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let successProp = properties["success"] as? [String: Any] ?? [:]
        
        XCTAssertEqual(successProp["type"] as? String, "boolean")
        XCTAssertNotNil(successProp["description"])
    }
    
    func testMainTaskSchemaHasErrorMessageProperty() throws {
        // Main task schema has error_message as optional string
        let schema = ClaudeSchemas.mainTaskSchema
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let errorProp = properties["error_message"] as? [String: Any] ?? [:]
        let required = schema["required"] as? [String] ?? []
        
        XCTAssertEqual(errorProp["type"] as? String, "string")
        XCTAssertFalse(required.contains("error_message"))
    }
    
    func testMainTaskSchemaHasSummaryProperty() throws {
        // Main task schema has summary as required string
        let schema = ClaudeSchemas.mainTaskSchema
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let summaryProp = properties["summary"] as? [String: Any] ?? [:]
        let required = schema["required"] as? [String] ?? []
        
        XCTAssertEqual(summaryProp["type"] as? String, "string")
        XCTAssertTrue(required.contains("summary"))
    }
    
    func testMainTaskSchemaDisallowsAdditionalProperties() throws {
        // Main task schema prevents extra properties
        let schema = ClaudeSchemas.mainTaskSchema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }
    
    // MARK: - Summary Task Schema Tests
    
    func testSummaryTaskSchemaIsValidJSONSchema() throws {
        // Summary task schema has valid JSON Schema structure
        let schema = ClaudeSchemas.summaryTaskSchema
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertNotNil(schema["properties"])
        XCTAssertNotNil(schema["required"])
    }
    
    func testSummaryTaskSchemaHasRequiredProperties() throws {
        // Summary task schema has success and summary_content as required
        let schema = ClaudeSchemas.summaryTaskSchema
        let required = schema["required"] as? [String] ?? []
        XCTAssertTrue(required.contains("success"))
        XCTAssertTrue(required.contains("summary_content"))
    }
    
    func testSummaryTaskSchemaHasSuccessProperty() throws {
        // Summary task schema has success as boolean
        let schema = ClaudeSchemas.summaryTaskSchema
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let successProp = properties["success"] as? [String: Any] ?? [:]
        
        XCTAssertEqual(successProp["type"] as? String, "boolean")
    }
    
    func testSummaryTaskSchemaHasErrorMessageProperty() throws {
        // Summary task schema has error_message as optional string
        let schema = ClaudeSchemas.summaryTaskSchema
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let errorProp = properties["error_message"] as? [String: Any] ?? [:]
        let required = schema["required"] as? [String] ?? []
        
        XCTAssertEqual(errorProp["type"] as? String, "string")
        XCTAssertFalse(required.contains("error_message"))
    }
    
    func testSummaryTaskSchemaHasSummaryContentProperty() throws {
        // Summary task schema has summary_content as required string
        let schema = ClaudeSchemas.summaryTaskSchema
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let contentProp = properties["summary_content"] as? [String: Any] ?? [:]
        let required = schema["required"] as? [String] ?? []
        
        XCTAssertEqual(contentProp["type"] as? String, "string")
        XCTAssertTrue(required.contains("summary_content"))
    }
    
    func testSummaryTaskSchemaDisallowsAdditionalProperties() throws {
        // Summary task schema prevents extra properties
        let schema = ClaudeSchemas.summaryTaskSchema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }
    
    // MARK: - Schema JSON Serialization Tests
    
    func testMainTaskSchemaJSONIsValidJSON() throws {
        // getMainTaskSchemaJSON returns valid JSON
        let jsonString = ClaudeSchemas.getMainTaskSchemaJSON()
        XCTAssertNotNil(jsonString)
        
        guard let jsonStr = jsonString else { return }
        let data = jsonStr.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertNotNil(parsed)
        // Compare with original schema (convert both to NSObject for comparison)
        let originalData = try JSONSerialization.data(withJSONObject: ClaudeSchemas.mainTaskSchema)
        let reparsedOriginal = try JSONSerialization.jsonObject(with: originalData) as? [String: Any]
        
        XCTAssertTrue(NSDictionary(dictionary: parsed!).isEqual(to: reparsedOriginal!))
    }
    
    func testSummaryTaskSchemaJSONIsValidJSON() throws {
        // getSummaryTaskSchemaJSON returns valid JSON
        let jsonString = ClaudeSchemas.getSummaryTaskSchemaJSON()
        XCTAssertNotNil(jsonString)
        
        guard let jsonStr = jsonString else { return }
        let data = jsonStr.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertNotNil(parsed)
        // Compare with original schema
        let originalData = try JSONSerialization.data(withJSONObject: ClaudeSchemas.summaryTaskSchema)
        let reparsedOriginal = try JSONSerialization.jsonObject(with: originalData) as? [String: Any]
        
        XCTAssertTrue(NSDictionary(dictionary: parsed!).isEqual(to: reparsedOriginal!))
    }
    
    func testMainTaskSchemaJSONIsCompact() throws {
        // getMainTaskSchemaJSON returns compact JSON without spaces
        let jsonString = ClaudeSchemas.getMainTaskSchemaJSON()
        XCTAssertNotNil(jsonString)
        
        guard let jsonStr = jsonString else { return }
        
        // Compact JSON has no spaces after colons or commas
        XCTAssertFalse(jsonStr.contains(": "))
        XCTAssertFalse(jsonStr.contains(", "))
    }
    
    func testSummaryTaskSchemaJSONIsCompact() throws {
        // getSummaryTaskSchemaJSON returns compact JSON without spaces
        let jsonString = ClaudeSchemas.getSummaryTaskSchemaJSON()
        XCTAssertNotNil(jsonString)
        
        guard let jsonStr = jsonString else { return }
        
        // Compact JSON has no spaces after colons or commas
        XCTAssertFalse(jsonStr.contains(": "))
        XCTAssertFalse(jsonStr.contains(", "))
    }
}