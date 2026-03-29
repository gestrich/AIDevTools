import Foundation

@MainActor
struct DeepLinkRouter {
    func route(_ url: URL) {
        guard url.scheme == "aidevtools" else { return }
        switch url.host {
        case "tab":
            let tab = url.pathComponents.dropFirst().first ?? ""
            if !tab.isEmpty {
                UserDefaults.standard.setValue(tab, forKey: "selectedWorkspaceTab")
            }
        default:
            break
        }
    }
}
