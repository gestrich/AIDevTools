import SkillScannerSDK
import SwiftUI

struct MessageInputWithAutocomplete: View {
    @Binding var messageText: String
    let workingDirectory: String
    let onSubmit: () -> Void

    @State private var availableSkills: [SkillInfo] = []
    @State private var filteredSkills: [SkillInfo] = []
    @State private var selectedSkillIndex: Int = 0
    @State private var showAutocomplete: Bool = false
    @State private var scanError: String?

    private let skillScanner = SkillScanner()

    var body: some View {
        VStack(spacing: 0) {
            if let scanError {
                Text(scanError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                Divider()
            }

            if showAutocomplete {
                SkillAutocompleteView(
                    filteredSkills: filteredSkills,
                    selectedSkillIndex: selectedSkillIndex,
                    onSelectSkill: selectSkill
                )
                Divider()
            }

            CustomTextField(
                text: $messageText,
                placeholder: "Ask Claude anything...",
                onSubmit: onSubmit,
                onTab: acceptSelectedSkill,
                onUpArrow: selectPreviousSkill,
                onDownArrow: selectNextSkill
            )
        }
        .task {
            scanSkills()
        }
        .onChange(of: workingDirectory) { _, _ in
            scanSkills()
        }
        .onChange(of: messageText) { _, newValue in
            updateAutocomplete(for: newValue)
        }
    }

    // MARK: - Skill Autocomplete

    private func scanSkills() {
        let repoURL = URL(filePath: workingDirectory)
        do {
            availableSkills = try skillScanner.scanSkills(at: repoURL)
            scanError = nil
        } catch {
            availableSkills = []
            scanError = "Failed to scan skills: \(error.localizedDescription)"
        }
    }

    private func updateAutocomplete(for text: String) {
        guard text.hasPrefix("/") else {
            showAutocomplete = false
            return
        }

        filteredSkills = skillScanner.filterSkills(availableSkills, query: text)
        showAutocomplete = !filteredSkills.isEmpty
        selectedSkillIndex = 0
    }

    private func selectSkill(_ skill: SkillInfo) {
        messageText = "/" + skill.name + " "
        showAutocomplete = false
    }

    private func selectNextSkill() {
        guard !filteredSkills.isEmpty else { return }
        selectedSkillIndex = (selectedSkillIndex + 1) % filteredSkills.count
    }

    private func selectPreviousSkill() {
        guard !filteredSkills.isEmpty else { return }
        selectedSkillIndex = (selectedSkillIndex - 1 + filteredSkills.count) % filteredSkills.count
    }

    private func acceptSelectedSkill() {
        guard showAutocomplete, !filteredSkills.isEmpty,
              selectedSkillIndex < filteredSkills.count else {
            return
        }
        selectSkill(filteredSkills[selectedSkillIndex])
    }
}
