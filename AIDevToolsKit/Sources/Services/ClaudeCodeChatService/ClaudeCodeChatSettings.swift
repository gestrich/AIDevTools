import Foundation

@Observable
public final class ClaudeCodeChatSettings {
    public var enableStreaming: Bool {
        didSet { UserDefaults.standard.set(enableStreaming, forKey: "claudeCode.enableStreaming") }
    }

    public var resumeLastSession: Bool {
        didSet { UserDefaults.standard.set(resumeLastSession, forKey: "claudeCode.resumeLastSession") }
    }

    public var verboseMode: Bool {
        didSet { UserDefaults.standard.set(verboseMode, forKey: "claudeCode.verboseMode") }
    }

    public var maxThinkingTokens: Int {
        didSet { UserDefaults.standard.set(maxThinkingTokens, forKey: "claudeCode.maxThinkingTokens") }
    }

    public init() {
        self.enableStreaming = UserDefaults.standard.object(forKey: "claudeCode.enableStreaming") as? Bool ?? true
        self.resumeLastSession = UserDefaults.standard.object(forKey: "claudeCode.resumeLastSession") as? Bool ?? true
        self.verboseMode = UserDefaults.standard.object(forKey: "claudeCode.verboseMode") as? Bool ?? false
        self.maxThinkingTokens = UserDefaults.standard.object(forKey: "claudeCode.maxThinkingTokens") as? Int ?? 2048
    }
}
