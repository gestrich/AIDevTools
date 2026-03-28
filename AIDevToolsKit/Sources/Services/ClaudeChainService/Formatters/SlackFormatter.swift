/// Slack mrkdwn formatter for report elements.
///
/// Formats report elements using Slack's mrkdwn syntax:
/// - Bold: *text*
/// - Italic: _text_
/// - Links: <url|text>
/// - Code: `text`
import Foundation

/// Formatter that produces Slack mrkdwn output.
public struct SlackReportFormatter: ReportFormatter {
    
    public init() {}
    
    /// Format header as bold text (Slack doesn't have header syntax).
    ///
    /// - Parameter header: Header to format
    /// - Returns: Bold text for Slack
    public func formatHeader(_ header: Header) -> String {
        return "*\(header.text)*"
    }
    
    /// Format text block with appropriate Slack styling.
    ///
    /// - Parameter textBlock: TextBlock to format
    /// - Returns: Styled text for Slack
    public func formatTextBlock(_ textBlock: TextBlock) -> String {
        let text = textBlock.text
        switch textBlock.style {
        case .bold:
            return "*\(text)*"
        case .italic:
            return "_\(text)_"
        case .code:
            return "`\(text)`"
        case .plain:
            return text
        }
    }
    
    /// Format link using Slack syntax.
    ///
    /// - Parameter link: Link to format
    /// - Returns: Slack-formatted link
    public func formatLink(_ link: Link) -> String {
        return "<\(link.url)|\(link.text)>"
    }
    
    /// Format a single list item.
    ///
    /// - Parameter item: ListItem to format
    /// - Returns: Formatted list item
    public func formatListItem(_ item: ListItem) -> String {
        let content = formatListItemContent(item.content)
        return "\(item.bullet) \(content)"
    }
    
    /// Format table using TableFormatter with optional code block.
    ///
    /// - Parameter table: Table to format
    /// - Returns: Formatted table string
    public func formatTable(_ table: Table) -> String {
        // Build table using existing TableFormatter
        do {
            let formatter = try TableFormatter(
                headers: table.columns.map { $0.header },
                align: table.columns.map { $0.align }
            )
            
            for row in table.rows {
                try formatter.addRow(row.cells)
            }
            
            let tableStr = formatter.format()
            
            if table.inCodeBlock {
                return "```\n\(tableStr)\n```"
            }
            return tableStr
        } catch {
            return "Error formatting table: \(error.localizedDescription)"
        }
    }
    
    /// Format progress bar with filled/empty blocks.
    ///
    /// - Parameter progressBar: ProgressBar to format
    /// - Returns: Visual progress bar string
    public func formatProgressBar(_ progressBar: ProgressBar) -> String {
        let pct = progressBar.percentage
        let width = progressBar.width
        let filled = Int(round((pct / 100) * Double(width)))
        // Use lighter blocks for Slack
        let bar = String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
        
        if let label = progressBar.label {
            return "\(bar) \(label)"
        }
        return "\(bar) \(String(format: "%.0f", pct))%"
    }
    
    /// Format a labeled value as bold label with value.
    ///
    /// - Parameter labeledValue: LabeledValue to format
    /// - Returns: Formatted string like "*Label:* value"
    public func formatLabeledValue(_ labeledValue: LabeledValue) -> String {
        let value = formatLabeledValueContent(labeledValue.value)
        return "*\(labeledValue.label):* \(value)"
    }
    
    /// Format a horizontal divider.
    ///
    /// - Parameter divider: Divider to format
    /// - Returns: Divider string (dashes work in Slack)
    public func formatDivider(_ divider: Divider) -> String {
        return "---"
    }
}