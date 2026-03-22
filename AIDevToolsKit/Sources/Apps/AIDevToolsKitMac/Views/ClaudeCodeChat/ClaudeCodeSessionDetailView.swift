import AppKit
import ClaudeCodeChatService
import SwiftUI

struct ClaudeCodeSessionDetailView: View {
    @Environment(ClaudeCodeChatManager.self) private var chatManager: ClaudeCodeChatManager
    @Environment(\.dismiss) private var dismiss
    let session: ClaudeSession
    @State private var sessionDetails: SessionDetails?
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading session details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let details = sessionDetails {
                    VStack(spacing: 0) {
                        metadataBar(details: details)
                        Divider()
                        searchBar
                        Divider()
                        jsonLinesView
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)

                        Text("Failed to Load Session")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Could not read session data from file")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(session.summary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                if sessionDetails != nil {
                    ToolbarItem(placement: .automatic) {
                        Button(action: copyAllJson) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                        .help("Copy all JSON to clipboard")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button("Resume This Session") {
                            Task { await chatManager.resumeSession(session.id) }
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .task {
                isLoading = true
                let workDir = chatManager.workingDirectory
                let s = session
                let details = await Task.detached {
                    ClaudeCodeChatManager.getSessionDetails(for: s, workingDirectory: workDir)
                }.value
                sessionDetails = details
                isLoading = false
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Subviews

    private func metadataBar(details: SessionDetails) -> some View {
        HStack(spacing: 16) {
            if let cwd = details.cwd {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text(cwd)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let branch = details.gitBranch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                    Text(branch)
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
            }

            Spacer()

            Text("\(details.rawJsonLines.count) JSON lines")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search JSON...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var jsonLinesView: some View {
        List(Array(filteredJsonLines.enumerated()), id: \.offset) { index, line in
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Text(prettyPrintJson(line))
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Helpers

    private var filteredJsonLines: [String] {
        guard let details = sessionDetails else { return [] }

        if searchText.isEmpty {
            return details.rawJsonLines
        }

        return details.rawJsonLines.filter { line in
            line.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func prettyPrintJson(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return jsonString
        }
        return prettyString
    }

    private func copyAllJson() {
        guard let details = sessionDetails else { return }
        let allJson = details.rawJsonLines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allJson, forType: .string)
    }
}
