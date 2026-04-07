import LoggingSDK
import SwiftUI

struct DiagnosticsView: View {
    @Environment(LogsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by message, label, level, or source", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.bar)

            Divider()

            if case .loading = model.state {
                ProgressView("Loading logs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .error(let error) = model.state {
                ContentUnavailableView(
                    "Failed to Load Logs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Log Entries",
                    systemImage: "doc.text",
                    description: Text(
                        model.searchText.isEmpty
                            ? "No logs have been written yet."
                            : "No entries match your search."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                logList
            }

            Divider()

            HStack {
                Text("\(model.filteredItems.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    model.deleteLogs()
                } label: {
                    Label("Clear Logs", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(model.items.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .task { await model.load() }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(model.filteredItems) { item in
                LogEntryRow(entry: item.entry)
                    .id(item.id)
            }
            .listStyle(.plain)
            .onChange(of: model.items.count) { _, _ in
                guard !model.searchText.isEmpty else {
                    if let last = model.filteredItems.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                    return
                }
            }
            .onChange(of: model.filteredItems.count) { _, _ in
                guard model.searchText.isEmpty else { return }
                if let last = model.filteredItems.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = model.filteredItems.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 175, alignment: .leading)
                .lineLimit(1)

            LevelBadge(level: entry.level)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.message)
                    .font(.body)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct LevelBadge: View {
    let level: String

    var body: some View {
        Text(level.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(.rect(cornerRadius: 4))
    }

    private var badgeColor: Color {
        switch level {
        case "critical", "error": return .red
        case "warning": return .orange
        case "notice", "info": return .green
        case "debug": return .blue
        case "trace": return .secondary
        default: return .primary
        }
    }
}
