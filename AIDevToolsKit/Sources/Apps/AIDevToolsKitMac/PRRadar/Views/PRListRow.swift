import ClaudeChainService
import PRRadarModelsService
import SwiftUI

struct PRListRow: View {

    let prModel: PRModel

    @Environment(\.allPRsModel) private var allPRsModel

    private var pr: PRMetadata { prModel.metadata }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(pr.displayNumber)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())

                stateIndicator

                if prModel.operationMode != .idle {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                analysisBadge

                postedCommentsBadge

                reviewStatusBadge

                buildStatusBadge

                if let relative = relativeTimestamp {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(pr.title)
                .font(.body)
                .fontWeight(isFallback ? .regular : .semibold)
                .lineLimit(2)

            if !pr.headRefName.isEmpty {
                Text(pr.headRefName)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !pr.author.login.isEmpty {
                HStack(spacing: 4) {
                    GitHubAvatarView(author: pr.author, size: 14)
                    Text(allPRsModel?.authorDisplayName(for: pr.author) ?? (pr.author.name.isEmpty ? pr.author.login : pr.author.name))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("prRow_\(pr.number)")
    }

    // MARK: - Analysis Badge

    @ViewBuilder
    private var analysisBadge: some View {
        if prModel.pendingCommentCount > 0 {
            Text("\(prModel.pendingCommentCount)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.orange, in: Capsule())
        } else if case .loaded = prModel.analysisState {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }

    // MARK: - Posted Comments Badge

    @ViewBuilder
    private var postedCommentsBadge: some View {
        switch prModel.analysisState {
        case .loaded(_, _, let postedCommentCount):
            Text("\(max(postedCommentCount, 1))")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.green, in: Capsule())
                .opacity(postedCommentCount > 0 ? 1 : 0)
        default:
            EmptyView()
        }
    }

    // MARK: - Review Status Badge

    @ViewBuilder
    private var reviewStatusBadge: some View {
        if let status = reviewStatus {
            let approved = status.approvedBy.count
            let rejected = status.changesRequestedBy.count
            if approved == 0 && rejected == 0 {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Review Pending")
            } else {
                HStack(spacing: 3) {
                    if approved > 0 {
                        countBadge(approved, color: .green,
                                   help: "Approved by \(status.approvedBy.joined(separator: ", "))")
                    }
                    if rejected > 0 {
                        countBadge(rejected, color: .red,
                                   help: "Changes requested by \(status.changesRequestedBy.joined(separator: ", "))")
                    }
                }
            }
        }
    }

    private var reviewStatus: PRReviewStatus? {
        guard let reviews = pr.reviews else { return nil }
        return PRReviewStatus(reviews: reviews)
    }

    // MARK: - Build Status Badge

    @ViewBuilder
    private var buildStatusBadge: some View {
        if pr.isMergeable == false {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Merge Conflict")
        } else if let runs = pr.checkRuns {
            let passing = runs.filter(\.isPassing).count
            let failing = runs.filter(\.isFailing).count
            let pending = runs.filter { $0.status != .completed }.count
            if passing == 0 && failing == 0 && pending == 0 {
                EmptyView()
            } else {
                HStack(spacing: 3) {
                    if passing > 0 {
                        countBadge(passing, color: .green,
                                   help: "\(passing) check\(passing == 1 ? "" : "s") passing")
                    }
                    if failing > 0 {
                        countBadge(failing, color: .red,
                                   help: "\(failing) check\(failing == 1 ? "" : "s") failing")
                    }
                    if pending > 0 && failing == 0 {
                        countBadge(pending, color: .orange,
                                   help: "\(pending) check\(pending == 1 ? "" : "s") pending")
                    }
                }
            }
        }
    }

    // MARK: - Shared Badge Helper

    private func countBadge(_ count: Int, color: Color, help: String) -> some View {
        Text("\(count)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color, in: Capsule())
            .help(help)
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        let state = PRRadarModelsService.PRState(rawValue: pr.state.uppercased()) ?? .open
        let (color, label): (Color, String) = {
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
        }()
        
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var isFallback: Bool {
        pr.author.login.isEmpty && pr.headRefName.isEmpty && pr.state.isEmpty
    }

    private var relativeTimestamp: String? {
        guard !pr.createdAt.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: pr.createdAt)
            ?? ISO8601DateFormatter().date(from: pr.createdAt)
        else { return nil }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Open PR") {
    PRListRow(
        prModel: PRModel(
            metadata: PRMetadata(
                number: 1234,
                title: "Add three-pane navigation with config sidebar and PR list",
                author: .init(login: "gestrich", name: "Bill Gestrich"),
                state: "OPEN",
                headRefName: "feature/three-pane-nav",
                baseRefName: "main",
                createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2 * 86400))
            ),
            config: .init(name: "Preview", repoPath: "", outputDir: "code-reviews", githubAccount: "preview", defaultBaseBranch: "main")
        )
    )
    .frame(width: 260)
    .padding()
}
