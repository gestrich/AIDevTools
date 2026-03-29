import SwiftUI

enum WorkspaceStyle {
    static let sidebarWidth: CGFloat = 250
}

struct WorkspaceSidebar<Content: View>: View {
    let onAdd: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxHeight: .infinity)

            Divider()

            Button { onAdd() } label: {
                Label("New", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(8)
        }
        .frame(width: WorkspaceStyle.sidebarWidth)
    }
}
