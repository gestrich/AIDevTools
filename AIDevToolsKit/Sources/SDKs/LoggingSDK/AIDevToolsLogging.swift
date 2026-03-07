import Foundation
import Logging

public enum AIDevToolsLogging {
    public static let defaultLogFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AIDevTools/aidevtools.log")
    }()

    public static func bootstrap(logFileURL: URL = defaultLogFileURL) {
        LoggingSystem.bootstrap { label in
            FileLogHandler(label: label, fileURL: logFileURL)
        }
    }
}
