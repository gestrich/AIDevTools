/// GitHub-flavored Markdown formatter for report elements.
///
/// Formats report elements using standard markdown syntax:
/// - Bold: **text**
/// - Italic: _text_
/// - Links: [text](url)
/// - Code: `text`
/// - Headers: # ## ### etc.
import Foundation

/// Formatter that produces GitHub-flavored Markdown output.
public struct MarkdownReportFormatter: ReportFormatter {
    
    public init() {}
    
    /// Format header with appropriate number of # symbols.
    ///
    /// - Parameter header: Header to format
    /// - Returns: Markdown header string
    public func formatHeader(_ header: Header) -> String {
        let hashes = String(repeating: "#", count: header.level)
        return "\(hashes) \(header.text)"
    }
    
    /// Format text block with appropriate markdown styling.
    ///
    /// - Parameter textBlock: TextBlock to format
    /// - Returns: Styled text for markdown
    public func formatTextBlock(_ textBlock: TextBlock) -> String {
        let text = textBlock.text
        switch textBlock.style {
        case .bold:
            return "**\(text)**"
        case .italic:
            return "_\(text)_"
        case .code:
            return "`\(text)`"
        case .plain:
            return text
        }
    }
    
    /// Format link using markdown syntax.
    ///
    /// - Parameter link: Link to format
    /// - Returns: Markdown-formatted link
    public func formatLink(_ link: Link) -> String {
        return "[\(link.text)](\(link.url))"
    }
    
    /// Format a single list item.
    ///
    /// - Parameter item: ListItem to format
    /// - Returns: Formatted list item
    public func formatListItem(_ item: ListItem) -> String {
        let content = formatListItemContent(item.content)
        return "\(item.bullet) \(content)"
    }
    
    /// Format a table cell, handling different element types.
    ///
    /// - Parameter cell: Cell content string
    /// - Returns: Formatted string for the cell
    private func formatCell(_ cell: String) -> String {
        // In Swift, we already have strings in the cells array
        // If we had Links or other types, we'd handle them here
        return cell
    }
    
    /// Format table using GitHub-flavored markdown table syntax.
    ///
    /// Uses pipe-separated columns with proper alignment syntax.
    ///
    /// - Parameter table: Table to format
    /// - Returns: Markdown table string
    public func formatTable(_ table: Table) -> String {
        var lines: [String] = []
        
        // Header row
        let headerCells = table.columns.map { $0.header }
        lines.append("| " + headerCells.joined(separator: " | ") + " |")
        
        // Alignment row
        let alignCells = table.columns.map { col in
            switch col.align {
            case .right:
                return String(repeating: "-", count: 10) + ":"
            case .center:
                return ":" + String(repeating: "-", count: 9) + ":"
            case .left:
                return String(repeating: "-", count: 11)
            }
        }
        lines.append("|" + alignCells.joined(separator: "|") + "|")
        
        // Data rows
        for row in table.rows {
            let formattedCells = row.cells.map { formatCell($0) }
            lines.append("| " + formattedCells.joined(separator: " | ") + " |")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Format progress bar with filled/empty blocks.
    ///
    /// - Parameter progressBar: ProgressBar to format
    /// - Returns: Visual progress bar string
    public func formatProgressBar(_ progressBar: ProgressBar) -> String {
        let pct = progressBar.percentage
        let width = progressBar.width
        let filled = Int(round((pct / 100) * Double(width)))
        // Use full blocks for markdown
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
        
        if let label = progressBar.label {
            return "\(bar) \(label)"
        }
        return "\(bar) \(String(format: "%.0f", pct))%"
    }
    
    /// Format a labeled value as bold label with value.
    ///
    /// - Parameter labeledValue: LabeledValue to format
    /// - Returns: Formatted string like "**Label:** value"
    public func formatLabeledValue(_ labeledValue: LabeledValue) -> String {
        let value = formatLabeledValueContent(labeledValue.value)
        return "**\(labeledValue.label):** \(value)"
    }
    
    /// Format a horizontal divider.
    ///
    /// - Parameter divider: Divider to format (unused, dividers have no config)
    /// - Returns: Markdown horizontal rule
    public func formatDivider(_ divider: Divider) -> String {
        return "---"
    }
}