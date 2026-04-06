import SwiftUI
import WorktreeFeature

struct AddWorktreeSheet: View {
    let repoPath: String
    let model: WorktreeModel

    @Environment(\.dismiss) private var dismiss
    @State private var branch = ""
    @State private var destination = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Worktree")
                .font(.headline)

            Form {
                TextField("Destination Path", text: $destination)
                TextField("Branch", text: $branch)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    Task {
                        await model.addWorktree(
                            repoPath: repoPath,
                            destination: destination,
                            branch: branch
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branch.isEmpty || destination.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}
