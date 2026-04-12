import PRRadarModelsService
import SwiftUI

struct PullRequestsRowView: View {

    let metadata: PRMetadata
    let isFetching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metadata.displayNumber)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())

                stateLabel

                if isFetching {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                reviewStatusBadge

                buildStatusBadge

                if let relative = relativeTimestamp {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(metadata.title)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(2)

            if !metadata.headRefName.isEmpty {
                Text(metadata.headRefName)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !metadata.author.login.isEmpty {
                Text(metadata.author.name.isEmpty ? metadata.author.login : metadata.author.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("pullRequestRow_\(metadata.number)")
    }

    // MARK: - State Label

    @ViewBuilder
    private var stateLabel: some View {
        let prState = PRState(rawValue: metadata.state.uppercased()) ?? .open
        let (color, label) = stateDisplay(prState)
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func stateDisplay(_ state: PRState) -> (Color, String) {
        switch state {
        case .open:
            return (Color(red: 35/255, green: 134/255, blue: 54/255), "Open")
        case .merged:
            return (Color(red: 138/255, green: 86/255, blue: 221/255), "Merged")
        case .closed:
            return (Color(red: 218/255, green: 55/255, blue: 51/255), "Closed")
        case .draft:
            return (Color(red: 101/255, green: 108/255, blue: 118/255), "Draft")
        }
    }

    // MARK: - Review Status Badge

    @ViewBuilder
    private var reviewStatusBadge: some View {
        switch reviewStatus {
        case .approved:
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .help("Approved")
        case .changesRequested:
            Image(systemName: "xmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .help("Changes Requested")
        case .pending:
            Image(systemName: "clock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("Review Pending")
        case .none:
            EmptyView()
        }
    }

    private enum ReviewStatus {
        case approved, changesRequested, pending
    }

    private var reviewStatus: ReviewStatus? {
        guard let reviews = metadata.reviews else { return nil }
        if reviews.contains(where: { $0.state == .changesRequested }) { return .changesRequested }
        if reviews.contains(where: { $0.state == .approved }) { return .approved }
        return .pending
    }

    // MARK: - Build Status Badge

    @ViewBuilder
    private var buildStatusBadge: some View {
        switch buildStatus {
        case .passing:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .help("Checks Passing")
        case .failing:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .help("Checks Failing")
        case .pending:
            Image(systemName: "circle.dotted")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Checks Pending")
        case .conflicting:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Merge Conflict")
        case .none:
            EmptyView()
        }
    }

    private enum BuildStatus {
        case passing, failing, pending, conflicting
    }

    private var buildStatus: BuildStatus? {
        if metadata.isMergeable == false { return .conflicting }
        guard let checkRuns = metadata.checkRuns else { return nil }
        if checkRuns.contains(where: { $0.conclusion == .failure }) { return .failing }
        if checkRuns.contains(where: { $0.status == .inProgress || $0.status == .queued }) { return .pending }
        if !checkRuns.isEmpty && checkRuns.allSatisfy({ $0.conclusion == .success }) { return .passing }
        return checkRuns.isEmpty ? nil : .pending
    }

    // MARK: - Timestamp

    private var relativeTimestamp: String? {
        guard !metadata.createdAt.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: metadata.createdAt)
            ?? ISO8601DateFormatter().date(from: metadata.createdAt)
        else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Open PR — enriched") {
    PullRequestsRowView(
        metadata: PRMetadata(
            number: 42,
            title: "Add unified GitHub PR loader with incremental updates",
            author: .init(login: "gestrich", name: "Bill Gestrich"),
            state: "OPEN",
            headRefName: "feature/unified-pr-loader",
            baseRefName: "main",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3 * 86400)),
            reviews: [.init(id: "r1", body: "", state: .approved, author: nil, submittedAt: nil)],
            checkRuns: [.init(name: "CI", status: .completed, conclusion: .success)]
        ),
        isFetching: false
    )
    .frame(width: 300)
    .padding()
}

#Preview("Fetching") {
    PullRequestsRowView(
        metadata: PRMetadata(
            number: 43,
            title: "Fix rate-limit handling in PR loader",
            author: .init(login: "gestrich", name: "Bill Gestrich"),
            state: "OPEN",
            headRefName: "fix/rate-limit",
            baseRefName: "main",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        ),
        isFetching: true
    )
    .frame(width: 300)
    .padding()
}
