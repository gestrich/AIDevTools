import AIOutputSDK
import SkillScannerSDK

/// Result of a skill invocation check during eval grading.
public enum SkillCheckResult: Sendable {
    case invoked(SkillInfo, method: InvocationMethod)
    case notInvoked(skillName: String)
    case skipped(skillName: String, reason: String)

    public var displayDescription: String {
        switch self {
        case .invoked(let skill, let method):
            var desc = "skill '\(skill.name)' invoked (\(method.rawValue))"
            if method == .inferred {
                desc += " — provider lacks dedicated skill tool; invocation inferred from file read"
            }
            return desc
        case .notInvoked(let name):
            return "skill '\(name)' not invoked"
        case .skipped(let name, let reason):
            return "skill '\(name)' check skipped: \(reason)"
        }
    }
}

extension SkillCheckResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case method, reason, skill, skillName, status
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .invoked(let skill, let method):
            try container.encode("invoked", forKey: .status)
            try container.encode(skill, forKey: .skill)
            try container.encode(method, forKey: .method)
        case .notInvoked(let name):
            try container.encode("notInvoked", forKey: .status)
            try container.encode(name, forKey: .skillName)
        case .skipped(let name, let reason):
            try container.encode("skipped", forKey: .status)
            try container.encode(name, forKey: .skillName)
            try container.encode(reason, forKey: .reason)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "invoked":
            let skill = try container.decode(SkillInfo.self, forKey: .skill)
            let method = try container.decode(InvocationMethod.self, forKey: .method)
            self = .invoked(skill, method: method)
        case "notInvoked":
            let name = try container.decode(String.self, forKey: .skillName)
            self = .notInvoked(skillName: name)
        case "skipped":
            let name = try container.decode(String.self, forKey: .skillName)
            let reason = try container.decode(String.self, forKey: .reason)
            self = .skipped(skillName: name, reason: reason)
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown status: \(status)")
        }
    }
}
