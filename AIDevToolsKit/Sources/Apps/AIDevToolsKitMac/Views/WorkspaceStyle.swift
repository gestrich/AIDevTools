import SwiftUI

enum WorkspaceStyle {
    static let sidebarWidth: CGFloat = 250
}

struct WorkspaceSidebarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxHeight: .infinity)
            .frame(width: WorkspaceStyle.sidebarWidth)
            .listStyle(.sidebar)
    }
}

extension View {
    func workspaceSidebar() -> some View {
        modifier(WorkspaceSidebarModifier())
    }
}
