import AppKit
import SlashCommandSDK
import SwiftUI

struct CommandAutocompleteView: View {
    let filteredCommands: [SlashCommand]
    let selectedCommandIndex: Int
    let onSelectCommand: (SlashCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(filteredCommands.prefix(5).enumerated()), id: \.element.id) { index, command in
                    Button(action: {
                        onSelectCommand(command)
                    }) {
                        HStack {
                            Text(command.name)
                                .font(.body)
                                .fontDesign(.monospaced)
                                .foregroundStyle(index == selectedCommandIndex ? .white : .primary)

                            Spacer()

                            if index == selectedCommandIndex {
                                Text("↩")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(index == selectedCommandIndex ? Color.blue : Color.clear)
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
