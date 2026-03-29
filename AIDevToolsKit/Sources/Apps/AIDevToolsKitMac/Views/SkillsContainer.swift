import ProviderRegistryService
import RepositorySDK
import SkillScannerSDK
import SwiftUI

struct SkillsContainer: View {
    @Environment(WorkspaceModel.self) var model

    let repository: RepositoryInfo
    let evalProviderRegistry: EvalProviderRegistry

    @AppStorage("selectedSkillName") private var storedSkillName: String = ""
    @State private var selectedSkillName: String?

    private var selectedSkill: SkillInfo? {
        guard let name = selectedSkillName else { return nil }
        return model.skills.first(where: { $0.name == name })
    }

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedSkillName == nil, !storedSkillName.isEmpty {
                selectedSkillName = storedSkillName
            }
        }
        .onChange(of: selectedSkillName) { _, newValue in
            storedSkillName = newValue ?? ""
        }
    }

    private var sidebar: some View {
        List(model.skills, id: \.name, selection: $selectedSkillName) { skill in
            Text(skill.name)
                .tag(skill.name)
        }
        .overlay {
            if model.isLoadingSkills {
                ProgressView("Loading skills...")
            }
        }
        .workspaceSidebar()
    }

    @ViewBuilder
    private var detail: some View {
        if let skill = selectedSkill {
            SkillDetailView(
                skill: skill,
                evalConfig: model.evalConfig(for: repository),
                evalRegistry: evalProviderRegistry
            )
        } else {
            ContentUnavailableView("Select a Skill", systemImage: "star", description: Text("Choose a skill to view details."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
