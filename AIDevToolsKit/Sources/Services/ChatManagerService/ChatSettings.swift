import Foundation
import Observation

@Observable
public final class ChatSettings {
    public var enableStreaming: Bool {
        didSet { UserDefaults.standard.set(enableStreaming, forKey: "chat.enableStreaming") }
    }

    public var maxThinkingTokens: Int {
        didSet { UserDefaults.standard.set(maxThinkingTokens, forKey: "chat.maxThinkingTokens") }
    }

    public var resumeLastSession: Bool {
        didSet { UserDefaults.standard.set(resumeLastSession, forKey: "chat.resumeLastSession") }
    }

    public var verboseMode: Bool {
        didSet { UserDefaults.standard.set(verboseMode, forKey: "chat.verboseMode") }
    }

    public init() {
        self.enableStreaming = UserDefaults.standard.object(forKey: "chat.enableStreaming") as? Bool ?? true
        self.maxThinkingTokens = UserDefaults.standard.object(forKey: "chat.maxThinkingTokens") as? Int ?? 2048
        self.resumeLastSession = UserDefaults.standard.object(forKey: "chat.resumeLastSession") as? Bool ?? true
        self.verboseMode = UserDefaults.standard.object(forKey: "chat.verboseMode") as? Bool ?? false
    }
}
