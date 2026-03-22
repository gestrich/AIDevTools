import PlanRunnerService
import SwiftUI

struct LayerBandView: View {
    let layer: ArchitectureLayer
    let selectedModule: ModuleSelection?
    let onSelectModule: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(layer.name)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(layer.modules, id: \.name) { module in
                    ModuleCardView(
                        module: module,
                        isSelected: selectedModule?.layerName == layer.name
                            && selectedModule?.moduleName == module.name,
                        onTap: { onSelectModule(module.name) }
                    )
                }
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
