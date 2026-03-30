import Foundation

extension DataPathsService {

    /// Root directory for AIDevTools runtime files in Application Support.
    public static var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIDevTools")
    }

    /// File watched by the Mac app for deep-link navigation URLs.
    public static var deepLinkFileURL: URL {
        appSupportDirectory.appendingPathComponent("deeplink.txt")
    }

    /// MCP server configuration file passed to Claude CLI via `--mcp-config`.
    public static var mcpConfigFileURL: URL {
        appSupportDirectory.appendingPathComponent("mcp-config.json")
    }
}
