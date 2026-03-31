import Foundation
import Logging

public enum AIDevToolsLogging {
    public static let defaultLogFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AIDevTools/aidevtools.log")
    }()

    public static func bootstrap(appName: String = "AIDevTools", logFileURL: URL? = nil, logLevel: Logger.Level = .info) {
        let url = logFileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(appName)/\(appName.lowercased()).log")
        LoggingSystem.bootstrap { label in
            var handler = FileLogHandler(label: label, fileURL: url)
            handler.logLevel = logLevel
            return handler
        }
    }
}
