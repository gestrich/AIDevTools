import ProviderRegistryService
import RepositorySDK
import SkillScannerSDK
import SwiftUI

struct SkillsContainer: View {
    @Environment(WorkspaceModel.self) var model

    let repository: RepositoryConfiguration
    let evalProviderRegistry: EvalProviderRegistry

    @AppStorage("selectedSkillName") private var storedSkillName: String = ""
    @State private var selectedSkillName: String?
    @State private var showCreateSheet = false

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
        .sheet(isPresented: $showCreateSheet) {
            CreateSkillSheet()
        }
    }

    private var sidebar: some View {
        WorkspaceSidebar {
            showCreateSheet = true
        } content: {
            List(model.skills, id: \.name, selection: $selectedSkillName) { skill in
                Text(skill.name)
                    .tag(skill.name)
            }
            .listStyle(.sidebar)
            .overlay {
                if model.isLoadingSkills {
                    ProgressView("Loading skills...")
                }
            }
        }
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

// MARK: - Create Skill Sheet

private struct CreateSkillSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("New Skill").font(.headline)
            Text("Skill creation is not yet implemented.\nAdd a skill file to .agents/skills/ in your repo.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 300)
    }
}
