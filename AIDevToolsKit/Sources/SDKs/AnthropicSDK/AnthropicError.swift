import Foundation
import SwiftAnthropic

public enum AnthropicError: LocalizedError {
    case invalidAPIKey
    case rateLimitExceeded
    case serverOverloaded(code: Int)
    case serverError(code: Int)
    case networkError(String)
    case invalidResponse
    case toolExecutionFailed(String)
    case requestFailed(String)
    case responseUnsuccessful(String)
    case invalidData
    case jsonDecodingFailure(String)
    case missingData(String)
    case decodingFailed
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your Anthropic API key in Settings."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please wait a moment before trying again."
        case .serverOverloaded(let code):
            return "Anthropic API is currently overloaded (Error \(code)). This is a temporary issue on Anthropic's servers. Please try again in a few moments."
        case .serverError(let code):
            return "Anthropic server error (\(code)). This is a temporary issue. Please try again later."
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response data from API"
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .requestFailed(let description):
            return "Request failed: \(description)"
        case .responseUnsuccessful(let description):
            return "API error: \(description)"
        case .invalidData:
            return "Invalid response data from API"
        case .jsonDecodingFailure(let description):
            return "Failed to parse API response: \(description)"
        case .missingData(let description):
            return "Missing data: \(description)"
        case .decodingFailed:
            return "Failed to decode API response"
        case .timeout:
            return "Request timed out. Please check your internet connection and try again."
        }
    }

    public static func from(_ apiError: SwiftAnthropic.APIError) -> AnthropicError {
        switch apiError {
        case .requestFailed(let description):
            return .requestFailed(description)

        case .responseUnsuccessful(let description):
            if description.contains("529") {
                return .serverOverloaded(code: 529)
            } else if description.contains("401") {
                return .invalidAPIKey
            } else if description.contains("403") {
                return .invalidAPIKey
            } else if description.contains("404") {
                return .responseUnsuccessful("API endpoint not found. The app may need to be updated.")
            } else if description.contains("429") {
                return .rateLimitExceeded
            } else if description.contains("500") || description.contains("502") || description.contains("503") {
                let code = description.contains("500") ? 500 : (description.contains("502") ? 502 : 503)
                return .serverError(code: code)
            } else {
                return .responseUnsuccessful(description)
            }

        case .invalidData:
            return .invalidData

        case .jsonDecodingFailure(let description):
            return .jsonDecodingFailure(description)

        case .dataCouldNotBeReadMissingData(let description):
            return .missingData(description)

        case .bothDecodingStrategiesFailed:
            return .decodingFailed

        case .timeOutError:
            return .timeout
        }
    }
}
