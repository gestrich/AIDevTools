/// Table formatting utilities for consistent Slack/terminal output
import Foundation

/// Calculate the visual display width of a string.
///
/// Handles double-width characters (emojis, CJK characters, box-drawing chars).
///
/// - Parameter text: String to measure
/// - Returns: Visual width in terminal columns
public func visualWidth(_ text: String) -> Int {
    var width = 0
    
    for scalar in text.unicodeScalars {
        let value = scalar.value
        
        // Check if it's an emoji or special character
        if value >= 0x1F300 {  // Emoji range starts here
            width += 2
        }
        // Wide (W) and Fullwidth (F) characters using Unicode categories
        // Exclude block characters (U+2580-U+259F) which should be width 1
        else if scalar.properties.isEmojiPresentation ||
                (scalar.properties.generalCategory == .otherSymbol && 
                 !(value >= 0x2580 && value <= 0x259F)) || // Exclude block characters
                (value >= 0x1100 && value <= 0x115F) || // Hangul Jamo
                (value >= 0x2E80 && value <= 0x9FFF) || // CJK
                (value >= 0xAC00 && value <= 0xD7AF) || // Hangul Syllables
                (value >= 0xF900 && value <= 0xFAFF) || // CJK Compatibility Ideographs
                (value >= 0xFE10 && value <= 0xFE19) || // Vertical forms
                (value >= 0xFE30 && value <= 0xFE6F) || // CJK Compatibility Forms
                (value >= 0xFF00 && value <= 0xFF60) || // Fullwidth Forms
                (value >= 0xFFE0 && value <= 0xFFE6) {  // Fullwidth Forms
            width += 2
        }
        // Neutral (N), Narrow (Na), Halfwidth (H), and block characters
        else {
            width += 1
        }
    }
    
    return width
}

/// Pad a string to a target visual width.
///
/// - Parameters:
///   - text: String to pad
///   - targetWidth: Desired visual width
///   - align: Alignment direction
/// - Returns: Padded string
public func padToVisualWidth(_ text: String, targetWidth: Int, align: ColumnAlignment = .left) -> String {
    let currentWidth = visualWidth(text)
    let paddingNeeded = targetWidth - currentWidth
    
    if paddingNeeded <= 0 {
        return text
    }
    
    let padding = String(repeating: " ", count: paddingNeeded)
    
    switch align {
    case .left:
        return text + padding
    case .right:
        return padding + text
    case .center:
        let leftPad = paddingNeeded / 2
        let rightPad = paddingNeeded - leftPad
        return String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
    }
}

/// Format data as a bordered table with box-drawing characters.
public class TableFormatter {
    public let headers: [String]
    public let align: [ColumnAlignment]
    public private(set) var rows: [[String]] = []
    
    /// Initialize table formatter.
    ///
    /// - Parameters:
    ///   - headers: Column headers
    ///   - align: List of alignment per column. Defaults to 'left' for all columns
    /// - Throws: ValueError if align list doesn't match number of headers
    public init(headers: [String], align: [ColumnAlignment]? = nil) throws {
        self.headers = headers
        self.align = align ?? Array(repeating: .left, count: headers.count)
        
        if self.align.count != headers.count {
            throw ConfigurationError("align list must match number of headers")
        }
    }
    
    /// Add a data row to the table.
    ///
    /// - Parameter row: List of cell values (must match number of headers)
    /// - Throws: ValueError if row doesn't match number of headers
    public func addRow(_ row: [String]) throws {
        if row.count != headers.count {
            throw ConfigurationError("Row has \(row.count) columns, expected \(headers.count)")
        }
        rows.append(row.map { String($0) })
    }
    
    /// Calculate the visual width needed for each column.
    ///
    /// - Returns: Array of column widths
    private func calculateColumnWidths() -> [Int] {
        var widths = headers.map(visualWidth)
        
        for row in rows {
            for (i, cell) in row.enumerated() {
                widths[i] = max(widths[i], visualWidth(cell))
            }
        }
        
        return widths
    }
    
    /// Format the table with box-drawing characters.
    ///
    /// - Returns: Formatted table as a string
    public func format() -> String {
        if rows.isEmpty {
            return ""
        }
        
        let colWidths = calculateColumnWidths()
        var lines: [String] = []
        
        // Top border
        let top = "┌" + colWidths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┬") + "┐"
        lines.append(top)
        
        // Header row
        let headerCells = zip(headers, zip(colWidths, align)).map { header, widthAlign in
            let (width, alignment) = widthAlign
            let padded = padToVisualWidth(header, targetWidth: width, align: alignment)
            return " \(padded) "
        }
        lines.append("│" + headerCells.joined(separator: "│") + "│")
        
        // Header separator
        let sep = "├" + colWidths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┼") + "┤"
        lines.append(sep)
        
        // Data rows
        for row in rows {
            let rowCells = zip(row, zip(colWidths, align)).map { cell, widthAlign in
                let (width, alignment) = widthAlign
                let padded = padToVisualWidth(cell, targetWidth: width, align: alignment)
                return " \(padded) "
            }
            lines.append("│" + rowCells.joined(separator: "│") + "│")
        }
        
        // Bottom border
        let bottom = "└" + colWidths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┴") + "┘"
        lines.append(bottom)
        
        return lines.joined(separator: "\n")
    }
}