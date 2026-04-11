import Foundation
import Observation

@Observable
final class ExperimentalSettings {
    static let architecturePlannerKey = "experimental.architecturePlanner"

    var isArchitecturePlannerEnabled: Bool {
        didSet { UserDefaults.standard.set(isArchitecturePlannerEnabled, forKey: Self.architecturePlannerKey) }
    }

    init() {
        self.isArchitecturePlannerEnabled = UserDefaults.standard.object(forKey: Self.architecturePlannerKey) as? Bool ?? false
    }
}
