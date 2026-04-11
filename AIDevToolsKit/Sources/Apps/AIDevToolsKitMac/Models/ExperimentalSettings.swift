import DataPathsService
import Foundation
import Observation

@Observable
final class ExperimentalSettings {
    static let architecturePlannerKey = "experimental.architecturePlanner"

    var isAnthropicAPIEnabled: Bool {
        didSet { AppPreferences().setAnthropicAPIEnabled(isAnthropicAPIEnabled) }
    }

    var isArchitecturePlannerEnabled: Bool {
        didSet { UserDefaults.standard.set(isArchitecturePlannerEnabled, forKey: Self.architecturePlannerKey) }
    }

    var isCodexEnabled: Bool {
        didSet { AppPreferences().setCodexEnabled(isCodexEnabled) }
    }

    init() {
        let prefs = AppPreferences()
        self.isAnthropicAPIEnabled = prefs.isAnthropicAPIEnabled()
        self.isArchitecturePlannerEnabled = UserDefaults.standard.object(forKey: Self.architecturePlannerKey) as? Bool ?? false
        self.isCodexEnabled = prefs.isCodexEnabled()
    }
}
