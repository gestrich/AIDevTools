import XCTest
@testable import ClaudeChainService
import Foundation

/// Tests for table formatting utilities
/// Swift port of test_table_formatter.py
final class TableFormatterTests: XCTestCase {
    
    // MARK: - Visual Width Tests
    
    func testVisualWidthASCIIText() {
        // ASCII characters are single width
        XCTAssertEqual(visualWidth("hello"), 5)
        XCTAssertEqual(visualWidth("test"), 4)
    }
    
    func testVisualWidthEmoji() {
        // Emojis are double width
        XCTAssertEqual(visualWidth("🥇"), 2)
        XCTAssertEqual(visualWidth("🥈"), 2)
        XCTAssertEqual(visualWidth("🥉"), 2)
    }
    
    func testVisualWidthEmojiWithText() {
        // Mixed emoji and text
        XCTAssertEqual(visualWidth("🥇 alice"), 8) // 2 + 1 + 5
    }
    
    func testVisualWidthUnicodeBlocks() {
        // Unicode block characters have width 1 (matching Python's unicodedata.east_asian_width)
        XCTAssertEqual(visualWidth("█"), 1)
        XCTAssertEqual(visualWidth("░"), 1)
        XCTAssertEqual(visualWidth("█████"), 5)
    }
    
    func testVisualWidthEmptyString() {
        // Empty string has zero width
        XCTAssertEqual(visualWidth(""), 0)
    }
    
    // MARK: - Pad to Visual Width Tests
    
    func testPadToVisualWidthLeftASCII() {
        // Pad ASCII text to the left
        let result = padToVisualWidth("hello", targetWidth: 10, align: .left)
        XCTAssertEqual(result, "hello     ")
        XCTAssertEqual(visualWidth(result), 10)
    }
    
    func testPadToVisualWidthRightASCII() {
        // Pad ASCII text to the right
        let result = padToVisualWidth("hello", targetWidth: 10, align: .right)
        XCTAssertEqual(result, "     hello")
        XCTAssertEqual(visualWidth(result), 10)
    }
    
    func testPadToVisualWidthCenterASCII() {
        // Pad ASCII text centered
        let result = padToVisualWidth("hello", targetWidth: 11, align: .center)
        XCTAssertEqual(result, "   hello   ")
        XCTAssertEqual(visualWidth(result), 11)
    }
    
    func testPadToVisualWidthEmoji() {
        // Pad text with emoji
        // "🥇" is 2 chars wide, pad to 6 total
        let result = padToVisualWidth("🥇", targetWidth: 6, align: .left)
        XCTAssertEqual(visualWidth(result), 6)
        XCTAssertEqual(result, "🥇    ")
    }
    
    func testPadToVisualWidthEmojiWithText() {
        // Pad emoji and text combination
        // "🥇 alice" is 2 + 1 + 5 = 8 visual width
        let result = padToVisualWidth("🥇 alice", targetWidth: 15, align: .left)
        XCTAssertEqual(visualWidth(result), 15)
    }
    
    func testPadToVisualWidthNoPaddingNeeded() {
        // No padding when already at target width
        let result = padToVisualWidth("hello", targetWidth: 5, align: .left)
        XCTAssertEqual(result, "hello")
    }
    
    func testPadToVisualWidthTextTooLong() {
        // Text longer than target width is not truncated
        let result = padToVisualWidth("hello world", targetWidth: 5, align: .left)
        XCTAssertEqual(result, "hello world")
    }
    
    // MARK: - Table Formatter Tests
    
    func testSimpleTable() throws {
        // Format a simple ASCII table
        let table = try TableFormatter(headers: ["Name", "Age"])
        try table.addRow(["Alice", "30"])
        try table.addRow(["Bob", "25"])
        
        let result = table.format()
        let lines = result.split(separator: "\n").map(String.init)
        
        XCTAssertEqual(lines.count, 6) // top, header, sep, 2 rows, bottom
        XCTAssertTrue(lines[0].hasPrefix("┌"))
        XCTAssertTrue(lines[0].hasSuffix("┐"))
        XCTAssertTrue(lines[1].contains("Name"))
        XCTAssertTrue(lines[1].contains("Age"))
        XCTAssertTrue(lines[3].contains("Alice"))
        XCTAssertTrue(lines[4].contains("Bob"))
    }
    
    func testTableWithEmoji() throws {
        // Format table with emoji characters
        let table = try TableFormatter(headers: ["Rank", "Name"], align: [.left, .left])
        try table.addRow(["🥇", "Alice"])
        try table.addRow(["🥈", "Bob"])
        try table.addRow(["🥉", "Charlie"])
        
        let result = table.format()
        let lines = result.split(separator: "\n").map(String.init)
        
        // Each emoji line should align properly
        XCTAssertTrue(lines[3].contains("🥇"))
        XCTAssertTrue(lines[4].contains("🥈"))
        XCTAssertTrue(lines[5].contains("🥉"))
        
        // Verify the columns align by checking border characters
        for line in lines {
            if line.hasPrefix("│") {
                // Count the pipes - should be consistent
                XCTAssertEqual(line.filter { $0 == "│" }.count, 3) // start, middle, end
            }
        }
    }
    
    func testTableWithUnicodeBlocks() throws {
        // Format table with Unicode block characters
        let table = try TableFormatter(headers: ["Progress"], align: [.left])
        try table.addRow(["█████░░░░░ 50%"])
        try table.addRow(["███░░░░░░░ 30%"])
        
        let result = table.format()
        XCTAssertTrue(result.contains("█████░░░░░ 50%"))
        XCTAssertTrue(result.contains("███░░░░░░░ 30%"))
    }
    
    func testAlignmentRight() throws {
        // Test right alignment
        let table = try TableFormatter(headers: ["Name", "Score"], align: [.left, .right])
        try table.addRow(["Alice", "100"])
        try table.addRow(["Bob", "5"])
        
        let result = table.format()
        let lines = result.split(separator: "\n").map(String.init)
        
        // The score column should be right-aligned
        // Find the row with "100" and verify it's right-aligned
        let aliceLine = lines.first { $0.contains("Alice") }!
        XCTAssertTrue(aliceLine.contains("  100 │") || aliceLine.contains(" 100 │"))
    }
    
    func testVaryingColumnWidths() throws {
        // Table auto-sizes to widest content
        let table = try TableFormatter(headers: ["Short", "Long Column Name"])
        try table.addRow(["A", "B"])
        try table.addRow(["This is very long", "C"])
        
        let result = table.format()
        let lines = result.split(separator: "\n").map(String.init)
        
        // Verify the table contains all the expected content
        XCTAssertTrue(result.contains("This is very long"))
        XCTAssertTrue(result.contains("Short"))
        XCTAssertTrue(result.contains("Long Column Name"))
        
        // Verify we have the expected number of lines (borders, header, separator, rows)
        XCTAssertEqual(lines.count, 6) // top, header, sep, 2 rows, bottom
    }
    
    func testEmptyTable() throws {
        // Empty table returns empty string
        let table = try TableFormatter(headers: ["Col1", "Col2"])
        let result = table.format()
        XCTAssertEqual(result, "")
    }
    
    func testMismatchedColumns() throws {
        // Adding row with wrong number of columns raises error
        let table = try TableFormatter(headers: ["Col1", "Col2"])
        
        XCTAssertThrowsError(try table.addRow(["A", "B", "C"])) { error in
            // Check that the error is about column count mismatch
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("3 columns") && configError.message.contains("2"))
            } else {
                XCTFail("Expected ConfigurationError")
            }
        }
    }
    
    func testMismatchedAlign() {
        // Alignment list must match headers
        XCTAssertThrowsError(try TableFormatter(headers: ["Col1", "Col2"], align: [.left])) { error in
            // Check that the error is about alignment list mismatch
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("align") && configError.message.contains("headers"))
            } else {
                XCTFail("Expected ConfigurationError")
            }
        }
    }
    
    func testNumberFormatting() throws {
        // Numbers are converted to strings
        let table = try TableFormatter(headers: ["Name", "Count"], align: [.left, .right])
        try table.addRow(["Alice", "42"])
        try table.addRow(["Bob", "7"])
        
        let result = table.format()
        XCTAssertTrue(result.contains("42"))
        XCTAssertTrue(result.contains("7"))
    }
}