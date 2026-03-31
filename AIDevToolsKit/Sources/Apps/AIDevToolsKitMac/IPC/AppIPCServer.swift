import AppIPCSDK
import Darwin
import Foundation

@MainActor
final class AppIPCServer {

    private nonisolated var socketPath: String { AppIPCClient.socketFilePath }

    func start() async {
        try? FileManager.default.removeItem(atPath: socketPath)
        let dir = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let path = socketPath
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { src in
                _ = strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), src, maxLen)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, addrLen) }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            return
        }
        Darwin.listen(fd, 5)

        await withTaskCancellationHandler {
            await Self.acceptLoop(fd: fd)
        } onCancel: {
            Darwin.close(fd)
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private nonisolated static func acceptLoop(fd: Int32) async {
        while !Task.isCancelled {
            let clientFd = Darwin.accept(fd, nil, nil)
            guard clientFd >= 0 else { break }
            Task.detached { await handleConnection(clientFd: clientFd) }
        }
    }

    private nonisolated static func handleConnection(clientFd: Int32) async {
        defer { Darwin.close(clientFd) }

        var requestData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !requestData.contains(UInt8(ascii: "\n")) {
            let n = Darwin.recv(clientFd, &buffer, buffer.count, 0)
            if n <= 0 { return }
            requestData.append(contentsOf: buffer[..<Int(n)])
        }
        if requestData.last == UInt8(ascii: "\n") { requestData.removeLast() }

        guard let request = try? JSONDecoder().decode(IPCRequest.self, from: requestData),
              request.query == "getUIState" else { return }

        let uiState: IPCUIState = await MainActor.run {
            IPCUIState(
                currentTab: UserDefaults.standard.string(forKey: "selectedWorkspaceTab"),
                selectedChainName: UserDefaults.standard.string(forKey: "selectedChainProject"),
                selectedPlanName: UserDefaults.standard.string(forKey: "selectedPlanName")
            )
        }

        guard var responseData = try? JSONEncoder().encode(uiState) else { return }
        responseData.append(UInt8(ascii: "\n"))
        _ = responseData.withUnsafeBytes { Darwin.send(clientFd, $0.baseAddress!, $0.count, 0) }
    }
}
