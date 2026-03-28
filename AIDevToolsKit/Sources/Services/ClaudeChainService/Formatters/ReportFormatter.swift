/// Base protocol for report formatters.
///
/// Defines the interface that all report formatters must implement.
/// Each formatter knows how to render report elements into a specific
/// output format (Slack mrkdwn, GitHub markdown, etc.).
import Foundation

/// Abstract base protocol for report formatters.
///
/// Conforming types implement format methods for each element type,
/// producing strings in their target format (Slack, Markdown, etc.).
public protocol ReportFormatter {
    
    /// Format a header element.
    ///
    /// - Parameter header: Header to format
    /// - Returns: Formatted header string
    func formatHeader(_ header: Header) -> String
    
    /// Format a text block element.
    ///
    /// - Parameter textBlock: TextBlock to format
    /// - Returns: Formatted text string
    func formatTextBlock(_ textBlock: TextBlock) -> String
    
    /// Format a link element.
    ///
    /// - Parameter link: Link to format
    /// - Returns: Formatted link string
    func formatLink(_ link: Link) -> String
    
    /// Format a single list item.
    ///
    /// - Parameter item: ListItem to format
    /// - Returns: Formatted list item string
    func formatListItem(_ item: ListItem) -> String
    
    /// Format a table element.
    ///
    /// - Parameter table: Table to format
    /// - Returns: Formatted table string
    func formatTable(_ table: Table) -> String
    
    /// Format a progress bar element.
    ///
    /// - Parameter progressBar: ProgressBar to format
    /// - Returns: Formatted progress bar string
    func formatProgressBar(_ progressBar: ProgressBar) -> String
    
    /// Format a labeled value element (e.g., "Label: value").
    ///
    /// - Parameter labeledValue: LabeledValue to format
    /// - Returns: Formatted label-value string
    func formatLabeledValue(_ labeledValue: LabeledValue) -> String
    
    /// Format a horizontal divider element.
    ///
    /// - Parameter divider: Divider to format
    /// - Returns: Formatted divider string
    func formatDivider(_ divider: Divider) -> String
}

/// Default implementations for ReportFormatter protocol
extension ReportFormatter {
    
    /// Format any report element by dispatching to the appropriate method.
    ///
    /// - Parameter element: Any report element
    /// - Returns: Formatted string representation
    public func format(_ element: ReportElementProtocol) -> String {
        switch element {
        case let section as Section:
            return formatSection(section)
        case let header as Header:
            return formatHeader(header)
        case let textBlock as TextBlock:
            return formatTextBlock(textBlock)
        case let link as Link:
            return formatLink(link)
        case let listBlock as ListBlock:
            return formatListBlock(listBlock)
        case let table as Table:
            return formatTable(table)
        case let progressBar as ProgressBar:
            return formatProgressBar(progressBar)
        case let labeledValue as LabeledValue:
            return formatLabeledValue(labeledValue)
        case let divider as Divider:
            return formatDivider(divider)
        default:
            return "<!-- Unknown element type: \(type(of: element)) -->"
        }
    }
    
    /// Format a section containing multiple elements.
    ///
    /// - Parameter section: Section to format
    /// - Returns: Formatted string with all elements
    public func formatSection(_ section: Section) -> String {
        var lines: [String] = []
        
        // Add section header if present
        if let header = section.header {
            lines.append(formatHeader(header))
            lines.append("")
        }
        
        // Format each element
        for element in section.elements {
            let formatted = format(element)
            if !formatted.isEmpty {
                lines.append(formatted)
                lines.append("")
            }
        }
        
        // Remove trailing empty line
        while !lines.isEmpty && lines.last == "" {
            lines.removeLast()
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Format a list block containing multiple items.
    ///
    /// - Parameter listBlock: ListBlock to format
    /// - Returns: Formatted list string
    public func formatListBlock(_ listBlock: ListBlock) -> String {
        let lines = listBlock.items.map { formatListItem($0) }
        return lines.joined(separator: "\n")
    }
    
    /// Helper method to format list item content based on its type
    ///
    /// - Parameter content: List item content
    /// - Returns: Formatted content string
    public func formatListItemContent(_ content: ListItemContent) -> String {
        switch content {
        case .text(let text):
            return text
        case .link(let link):
            return formatLink(link)
        case .textBlock(let textBlock):
            return formatTextBlock(textBlock)
        }
    }
    
    /// Helper method to format labeled value content based on its type
    ///
    /// - Parameter content: Labeled value content
    /// - Returns: Formatted content string
    public func formatLabeledValueContent(_ content: LabeledValueContent) -> String {
        switch content {
        case .text(let text):
            return text
        case .link(let link):
            return formatLink(link)
        case .textBlock(let textBlock):
            return formatTextBlock(textBlock)
        }
    }
}