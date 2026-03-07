import Foundation

@MainActor @Observable
final class SettingsModel {

    var dataPath: URL {
        didSet {
            UserDefaults.standard.set(dataPath.path(), forKey: Self.dataPathKey)
        }
    }

    private static let dataPathKey = "AIDevTools.dataPath"
    private static let defaultDataPath = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.dataPathKey) {
            self.dataPath = URL(filePath: stored)
        } else {
            self.dataPath = Self.defaultDataPath
        }
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
    }
}
