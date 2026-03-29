import Darwin
import Foundation

public enum IPCError: Error, LocalizedError, Sendable {
    case appNotRunning
    case connectionFailed(String)
    case noResponse

    public var errorDescription: String? {
        switch self {
        case .appNotRunning:
            return "App is not running. Start the AIDevTools Mac app and try again."
        case .connectionFailed(let message):
            return "IPC connection failed: \(message)"
        case .noResponse:
            return "No response received from the app."
        }
    }
}

public struct AppIPCClient: Sendable {

    public init() {}

    public func getUIState() async throws -> IPCUIState {
        let path = socketFilePath()
        guard FileManager.default.fileExists(atPath: path) else {
            throw IPCError.appNotRunning
        }
        return try Self.performRequest(socketPath: path)
    }

    private static func performRequest(socketPath: String) throws -> IPCUIState {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCError.connectionFailed("Failed to create socket")
        }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathMaxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { src in
                _ = strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), src, sunPathMaxLen)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addrLen)
            }
        }
        guard connectResult == 0 else {
            throw IPCError.connectionFailed("Cannot connect to app socket. The app may not be running.")
        }

        let request = IPCRequest(query: "getUIState")
        var requestData = try JSONEncoder().encode(request)
        requestData.append(UInt8(ascii: "\n"))
        let bytesSent = requestData.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, $0.count, 0) }
        guard bytesSent >= 0 else {
            throw IPCError.connectionFailed("Failed to send IPC request")
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !responseData.contains(UInt8(ascii: "\n")) {
            let n = Darwin.recv(fd, &buffer, buffer.count, 0)
            if n <= 0 { break }
            responseData.append(contentsOf: buffer[..<Int(n)])
        }
        if responseData.last == UInt8(ascii: "\n") {
            responseData.removeLast()
        }
        guard !responseData.isEmpty else {
            throw IPCError.noResponse
        }

        return try JSONDecoder().decode(IPCUIState.self, from: responseData)
    }

    private func socketFilePath() -> String {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIDevTools/app.sock")
            .path
    }
}
