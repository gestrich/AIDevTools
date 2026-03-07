import Foundation
@preconcurrency import SwiftAnthropic

extension MessageResponse.Content.DynamicContent {
    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var arrayValue: [MessageResponse.Content.DynamicContent]? {
        switch self {
        case .array(let value):
            return value
        default:
            return nil
        }
    }

    public var dictionaryValue: [String: MessageResponse.Content.DynamicContent]? {
        switch self {
        case .dictionary(let value):
            return value
        default:
            return nil
        }
    }
}
