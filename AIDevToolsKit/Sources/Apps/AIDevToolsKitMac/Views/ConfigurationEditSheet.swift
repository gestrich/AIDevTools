import RepositorySDK
import SwiftUI

struct ConfigurationEditSheet: View {
    @State var config: RepositoryInfo
    @State private var nameText: String
    @State private var repoPathText: String
    @State private var casesDirectoryText: String
    @State private var completedDirectoryText: String
    @State private var proposedDirectoryText: String
    let isNew: Bool
    let onSave: (RepositoryInfo, String?, String?, String?) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        config: RepositoryInfo,
        casesDirectory: String?,
        completedDirectory: String?,
        proposedDirectory: String?,
        isNew: Bool,
        onSave: @escaping (RepositoryInfo, String?, String?, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.config = config
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        _nameText = State(initialValue: config.name)
        _repoPathText = State(initialValue: isNew ? "" : config.path.path(percentEncoded: false))
        _casesDirectoryText = State(initialValue: casesDirectory ?? "")
        _completedDirectoryText = State(initialValue: completedDirectory ?? "")
        _proposedDirectoryText = State(initialValue: proposedDirectory ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Repository" : "Edit Repository")
                .font(.title2)
                .bold()

            LabeledContent("Name") {
                TextField("my-repo", text: $nameText)
                    .textFieldStyle(.roundedBorder)
            }

            pathField(label: "Repo Path", text: $repoPathText, placeholder: "/path/to/repo")

            pathField(label: "Cases Directory", text: $casesDirectoryText, placeholder: "Optional — relative or absolute path")

            pathField(label: "Proposed Plans Directory", text: $proposedDirectoryText, placeholder: "Optional — defaults to docs/proposed")

            pathField(label: "Completed Plans Directory", text: $completedDirectoryText, placeholder: "Optional — defaults to docs/completed")

            Text("Directories can be relative to the repo path, absolute, or use ~.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let repoURL = URL(filePath: repoPathText)
                    let finalName = nameText.isEmpty ? repoURL.lastPathComponent : nameText
                    let cases = casesDirectoryText.isEmpty ? nil : casesDirectoryText
                    let proposed = proposedDirectoryText.isEmpty ? nil : proposedDirectoryText
                    let completed = completedDirectoryText.isEmpty ? nil : completedDirectoryText
                    let updated = RepositoryInfo(
                        id: config.id,
                        path: repoURL,
                        name: finalName
                    )
                    onSave(updated, cases, completed, proposed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(repoPathText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }

    private func pathField(label: String, text: Binding<String>, placeholder: String) -> some View {
        LabeledContent(label) {
            HStack {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        text.wrappedValue = url.path
                    }
                } label: {
                    Image(systemName: "folder")
                }
            }
        }
    }
}
