/// Abstract report elements for format-agnostic report building.
///
/// These data structures represent the semantic structure of a report without
/// any formatting logic. Formatters (Slack, Markdown) know how to render
/// these elements into their respective output formats.
import Foundation

/// Text style options
public enum TextStyle: String, CaseIterable {
    case plain = "plain"
    case bold = "bold"
    case italic = "italic"
    case code = "code"
}

/// Table column alignment options
public enum ColumnAlignment: String, CaseIterable {
    case left = "left"
    case right = "right"
    case center = "center"
}

/// A header/title element.
public struct Header {
    /// The header text content
    public let text: String
    
    /// Header level (1=h1, 2=h2, etc.)
    public let level: Int
    
    public init(text: String, level: Int = 2) {
        self.text = text
        self.level = level
    }
}

/// A block of text with optional styling.
public struct TextBlock {
    /// The text content
    public let text: String
    
    /// Text style (plain, bold, italic, code)
    public let style: TextStyle
    
    public init(text: String, style: TextStyle = .plain) {
        self.text = text
        self.style = style
    }
}

/// A hyperlink element.
public struct Link {
    /// Display text for the link
    public let text: String
    
    /// Target URL
    public let url: String
    
    public init(text: String, url: String) {
        self.text = text
        self.url = url
    }
}

/// Content that can appear in a list item
public enum ListItemContent {
    case text(String)
    case link(Link)
    case textBlock(TextBlock)
}

/// A single item in a list.
public struct ListItem {
    /// The item content (can be text, link, or nested elements)
    public let content: ListItemContent
    
    /// Bullet character (e.g., "-", "*", "•", or number for ordered lists)
    public let bullet: String
    
    public init(content: ListItemContent, bullet: String = "-") {
        self.content = content
        self.bullet = bullet
    }
}

/// A list of items.
public struct ListBlock {
    /// List of ListItem elements
    public let items: [ListItem]
    
    public init(items: [ListItem]) {
        self.items = items
    }
}

/// Definition for a table column.
public struct TableColumn {
    /// Column header text
    public let header: String
    
    /// Column alignment
    public let align: ColumnAlignment
    
    public init(header: String, align: ColumnAlignment = .left) {
        self.header = header
        self.align = align
    }
}

/// A single row in a table.
public struct TableRow {
    /// Cell values (strings)
    public let cells: [String]
    
    public init(cells: [String]) {
        self.cells = cells
    }
}

/// A data table element.
public struct Table {
    /// Column definitions with headers and alignment
    public let columns: [TableColumn]
    
    /// Data rows
    public let rows: [TableRow]
    
    /// Whether to wrap the table in a code block (for Slack)
    public let inCodeBlock: Bool
    
    public init(columns: [TableColumn], rows: [TableRow], inCodeBlock: Bool = false) {
        self.columns = columns
        self.rows = rows
        self.inCodeBlock = inCodeBlock
    }
}

/// A visual progress indicator.
public struct ProgressBar {
    /// Completion percentage (0-100)
    public let percentage: Double
    
    /// Number of characters for the bar
    public let width: Int
    
    /// Optional label text to show after the bar
    public let label: String?
    
    public init(percentage: Double, width: Int = 10, label: String? = nil) {
        self.percentage = percentage
        self.width = width
        self.label = label
    }
}

/// Value that can appear in a labeled value pair
public enum LabeledValueContent {
    case text(String)
    case link(Link)
    case textBlock(TextBlock)
}

/// A label-value pair element (e.g., "PR: #123", "Cost: $0.50").
///
/// Commonly used for metadata display in notifications and summaries.
public struct LabeledValue {
    /// The label text (will be rendered bold)
    public let label: String
    
    /// The value (can be plain text, Link, or styled TextBlock)
    public let value: LabeledValueContent
    
    public init(label: String, value: LabeledValueContent) {
        self.label = label
        self.value = value
    }
}

/// A horizontal divider/separator element.
///
/// Renders as --- in markdown, similar in Slack.
public struct Divider {
    public init() {}
}

/// Protocol for any report element
public protocol ReportElementProtocol {}

extension Header: ReportElementProtocol {}
extension TextBlock: ReportElementProtocol {}
extension Link: ReportElementProtocol {}
extension ListBlock: ReportElementProtocol {}
extension Table: ReportElementProtocol {}
extension ProgressBar: ReportElementProtocol {}
extension LabeledValue: ReportElementProtocol {}
extension Divider: ReportElementProtocol {}

/// A container grouping multiple elements with an optional header.
///
/// This is mutable to allow building sections incrementally.
public class Section: ReportElementProtocol {
    /// List of elements in this section
    public var elements: [ReportElementProtocol]
    
    /// Optional section header
    public var header: Header?
    
    public init(elements: [ReportElementProtocol] = [], header: Header? = nil) {
        self.elements = elements
        self.header = header
    }
    
    /// Add an element to this section.
    ///
    /// - Parameter element: Element to add
    /// - Returns: Self for method chaining
    @discardableResult
    public func add(_ element: ReportElementProtocol) -> Section {
        elements.append(element)
        return self
    }
    
    /// Check if section has no elements.
    ///
    /// - Returns: True if section has no elements
    public func isEmpty() -> Bool {
        return elements.isEmpty
    }
}

/// Type alias for any report element
public typealias ReportElement = ReportElementProtocol