import Foundation

/// Parses structured AI responses embedded as XML tags in message text.
///
/// The AI embeds responses using the convention:
/// `<app-response name="actionName">{"key": "value"}</app-response>`
public struct StructuredOutputParser: Sendable {
    public struct ParsedResponse: Sendable {
        public let json: Data
        public let name: String
    }

    public init() {}

    /// Extracts all `<app-response>` blocks from the given text.
    public func parse(_ text: String) -> [ParsedResponse] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<app-response name="([^"]+)">([\s\S]*?)</app-response>"#
        ) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match in
            guard match.numberOfRanges == 3,
                  match.range(at: 1).location != NSNotFound,
                  match.range(at: 2).location != NSNotFound else { return nil }

            let name = nsText.substring(with: match.range(at: 1))
            let body = nsText.substring(with: match.range(at: 2))

            guard let jsonData = body.data(using: .utf8) else { return nil }
            return ParsedResponse(json: jsonData, name: name)
        }
    }

    /// Returns the message text with all `<app-response>` blocks removed.
    public func stripResponses(from text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<app-response name="[^"]+">\s*[\s\S]*?\s*</app-response>"#
        ) else { return text }

        let nsText = text as NSString
        let stripped = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length),
            withTemplate: ""
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
