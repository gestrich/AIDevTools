import PlanRunnerService
import SwiftUI

struct ArchitectureDiagramView: View {
    let diagram: ArchitectureDiagram
    @Binding var selectedModule: ModuleSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(diagram.layers.enumerated()), id: \.element.name) { index, layer in
                if index > 0 {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                LayerBandView(
                    layer: layer,
                    selectedModule: selectedModule,
                    onSelectModule: { moduleName in
                        let selection = ModuleSelection(layerName: layer.name, moduleName: moduleName)
                        if selectedModule == selection {
                            selectedModule = nil
                        } else {
                            selectedModule = selection
                        }
                    }
                )
            }

            if let selection = selectedModule,
               let module = findModule(selection) {
                ModuleDetailPanel(
                    moduleName: selection.moduleName,
                    changes: module.changes,
                    onClose: { selectedModule = nil }
                )
                .padding(.top, 8)
            }
        }
    }

    private func findModule(_ selection: ModuleSelection) -> ArchitectureModule? {
        diagram.layers
            .first(where: { $0.name == selection.layerName })?
            .modules
            .first(where: { $0.name == selection.moduleName })
    }
}
