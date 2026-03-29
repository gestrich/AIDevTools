import SwiftUI

enum WorkspaceStyle {
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 260
}

struct WorkspaceSidebarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: WorkspaceStyle.sidebarMinWidth, idealWidth: WorkspaceStyle.sidebarIdealWidth, maxHeight: .infinity)
            .listStyle(.sidebar)
    }
}

extension View {
    func workspaceSidebar() -> some View {
        modifier(WorkspaceSidebarModifier())
    }
}
