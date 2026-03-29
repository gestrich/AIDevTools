import Foundation

/// Describes a structured output the AI can produce — either a query (AI asks for data)
/// or an action (AI tells the app to do something).
public struct AIResponseDescriptor: Sendable {
    public let description: String
    public let jsonSchema: String
    public let kind: Kind
    public let name: String

    public enum Kind: Sendable {
        case action
        case query
    }

    public init(name: String, description: String, jsonSchema: String, kind: Kind) {
        self.description = description
        self.jsonSchema = jsonSchema
        self.kind = kind
        self.name = name
    }
}
