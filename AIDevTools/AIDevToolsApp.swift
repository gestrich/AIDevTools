import AIDevToolsKitMac
import SwiftUI

@main
struct AIDevToolsApp: App {
    var body: some Scene {
        WindowGroup {
            AIDevToolsKitMacEntryView()
        }
        Settings {
            AIDevToolsSettingsView()
        }
    }
}
