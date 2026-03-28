/// Domain formatting utilities.
///
/// Provides consistent formatting functions for domain values like currency,
/// following project conventions for display across different outputs
/// (PR comments, Slack messages, statistics, etc.).
import Foundation

public struct Formatting {
    
    /// Format a USD amount for display.
    ///
    /// Formats to standard US currency convention with dollar sign prefix
    /// and exactly 2 decimal places (cents).
    ///
    /// - Parameter amount: Amount in USD (e.g., 0.123456)
    /// - Returns: Formatted string (e.g., "$0.12")
    ///
    /// Examples:
    /// ```swift
    /// Formatting.formatUSD(0.123456) // "$0.12"
    /// Formatting.formatUSD(1.5)      // "$1.50"
    /// Formatting.formatUSD(0.0)      // "$0.00"
    /// Formatting.formatUSD(123.456)  // "$123.46"
    /// ```
    public static func formatUSD(_ amount: Double) -> String {
        return String(format: "$%.2f", amount)
    }
}