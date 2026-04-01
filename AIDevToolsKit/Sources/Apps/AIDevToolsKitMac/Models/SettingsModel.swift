import DataPathsService
import Foundation

@MainActor @Observable
final class SettingsModel {

    private(set) var dataPath: URL

    init() {
        let prefs = AppPreferences()
        let path = prefs.dataPath() ?? AppPreferences.defaultDataPath
        self.dataPath = path
        prefs.setDataPath(path)
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
        AppPreferences().setDataPath(newPath)
    }
}
