import PlanRunnerService
import SwiftUI

struct ModuleCardView: View {
    let module: ArchitectureModule
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            if module.isAffected {
                onTap()
            }
        }) {
            Text(module.name)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: 100)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: isSelected ? 2 : (module.isAffected ? 1 : 0))
                )
                .overlay(alignment: .topTrailing) {
                    if module.isAffected {
                        Text("\(module.changes.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.tint, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var backgroundColor: Color {
        if isSelected {
            return .accentColor.opacity(0.15)
        } else if module.isAffected {
            return .accentColor.opacity(0.08)
        } else {
            return .secondary.opacity(0.1)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        } else if module.isAffected {
            return .accentColor.opacity(0.5)
        } else {
            return .clear
        }
    }
}
