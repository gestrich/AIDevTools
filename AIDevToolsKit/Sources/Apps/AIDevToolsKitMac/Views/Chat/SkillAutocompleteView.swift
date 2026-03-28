import AppKit
import SkillScannerSDK
import SwiftUI

struct SkillAutocompleteView: View {
    let filteredSkills: [SkillInfo]
    let selectedSkillIndex: Int
    let onSelectSkill: (SkillInfo) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(filteredSkills.prefix(5).enumerated()), id: \.element.id) { index, skill in
                    Button(action: {
                        onSelectSkill(skill)
                    }) {
                        HStack {
                            Text("/" + skill.name)
                                .font(.body)
                                .fontDesign(.monospaced)
                                .foregroundStyle(index == selectedSkillIndex ? .white : .primary)

                            Text(skill.source.rawValue)
                                .font(.caption2)
                                .foregroundStyle(index == selectedSkillIndex ? .white.opacity(0.7) : .secondary)

                            Spacer()

                            if index == selectedSkillIndex {
                                Text("↩")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(index == selectedSkillIndex ? Color.blue : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .frame(maxHeight: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
