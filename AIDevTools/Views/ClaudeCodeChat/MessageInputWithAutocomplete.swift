import SlashCommandSDK
import SwiftUI

struct MessageInputWithAutocomplete: View {
    @Binding var messageText: String
    let workingDirectory: String
    let onSubmit: () -> Void

    @State private var availableCommands: [SlashCommand] = []
    @State private var filteredCommands: [SlashCommand] = []
    @State private var selectedCommandIndex: Int = 0
    @State private var showAutocomplete: Bool = false

    private let commandScanner = SlashCommandScanner()

    var body: some View {
        VStack(spacing: 0) {
            if showAutocomplete {
                CommandAutocompleteView(
                    filteredCommands: filteredCommands,
                    selectedCommandIndex: selectedCommandIndex,
                    onSelectCommand: selectCommand
                )
                Divider()
            }

            CustomTextField(
                text: $messageText,
                placeholder: "Ask Claude anything...",
                onSubmit: onSubmit,
                onTab: acceptSelectedCommand,
                onUpArrow: selectPreviousCommand,
                onDownArrow: selectNextCommand
            )
        }
        .task {
            scanSlashCommands()
        }
        .onChange(of: workingDirectory) { _, _ in
            scanSlashCommands()
        }
        .onChange(of: messageText) { _, newValue in
            updateAutocomplete(for: newValue)
        }
    }

    // MARK: - Slash Command Autocomplete

    private func scanSlashCommands() {
        availableCommands = commandScanner.scanCommands(workingDirectory: workingDirectory)
    }

    private func updateAutocomplete(for text: String) {
        guard text.hasPrefix("/") else {
            showAutocomplete = false
            return
        }

        filteredCommands = commandScanner.filterCommands(availableCommands, query: text)
        showAutocomplete = !filteredCommands.isEmpty
        selectedCommandIndex = 0
    }

    private func selectCommand(_ command: SlashCommand) {
        messageText = command.name + " "
        showAutocomplete = false
    }

    private func selectNextCommand() {
        guard !filteredCommands.isEmpty else { return }
        selectedCommandIndex = (selectedCommandIndex + 1) % filteredCommands.count
    }

    private func selectPreviousCommand() {
        guard !filteredCommands.isEmpty else { return }
        selectedCommandIndex = (selectedCommandIndex - 1 + filteredCommands.count) % filteredCommands.count
    }

    private func acceptSelectedCommand() {
        guard showAutocomplete, !filteredCommands.isEmpty,
              selectedCommandIndex < filteredCommands.count else {
            return
        }
        selectCommand(filteredCommands[selectedCommandIndex])
    }
}
