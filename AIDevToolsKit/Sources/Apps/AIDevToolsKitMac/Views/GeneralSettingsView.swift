import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsModel.self) private var settingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Data Directory") {
                    HStack {
                        Text(settingsModel.dataPath.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.directoryURL = settingsModel.dataPath
                            if panel.runModal() == .OK, let url = panel.url {
                                settingsModel.updateDataPath(url)
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                    }
                }

                Text("Directory where repository configurations and eval output are stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Data Storage")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
