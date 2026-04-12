import PRRadarModelsService
import SwiftUI

struct SummaryPhaseView: View {

    let metadata: PRMetadata
    let postedComments: [GitHubComment]
    var imageURLMap: [String: String]? = nil
    var imageBaseDir: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                prInfoSection
                reviewAndChecksSection
                if !postedComments.isEmpty {
                    commentsSection
                }
            }
            .padding()
        }
    }

    // MARK: - PR Info Section

    @ViewBuilder
    private var prInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metadata.displayNumber)
                    .font(.title.bold())
                    .foregroundStyle(.secondary)

                Text(metadata.title)
                    .font(.title.bold())
            }

            HStack(spacing: 16) {
                if !metadata.author.login.isEmpty {
                    Label(
                        metadata.author.name.isEmpty ? metadata.author.login : metadata.author.name,
                        systemImage: "person"
                    )
                }

                if !metadata.headRefName.isEmpty {
                    Label {
                        Text("\(metadata.headRefName) → \(metadata.baseRefName)")
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .font(.system(.body, design: .monospaced))
                }

                if !metadata.state.isEmpty {
                    Label(metadata.state.capitalized, systemImage: "circle.fill")
                        .foregroundStyle(stateColor)
                }

                if !metadata.createdAt.isEmpty {
                    Label(formattedDate, systemImage: "calendar")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let body = metadata.body, !body.isEmpty {
                Divider()

                RichContentView(body, imageURLMap: imageURLMap, imageBaseDir: imageBaseDir)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Review & Checks Section

    @ViewBuilder
    private var reviewAndChecksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewsSubsection
            Divider()
            checksSubsection
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var reviewsSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviews")
                .font(.headline)

            if let reviews = metadata.reviews {
                if reviews.isEmpty {
                    Text("No reviews")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    let approved = reviews.filter { $0.state == .approved }.compactMap { $0.author?.login }
                    let changesRequested = reviews.filter { $0.state == .changesRequested }.compactMap { $0.author?.login }
                    let pending = reviews.filter { $0.state == .pending }.compactMap { $0.author?.login }
                    if !approved.isEmpty {
                        reviewerRow(label: "Approved", logins: approved, color: .green, icon: "checkmark.circle.fill")
                    }
                    if !changesRequested.isEmpty {
                        reviewerRow(label: "Changes requested", logins: changesRequested, color: .red, icon: "xmark.circle.fill")
                    }
                    if !pending.isEmpty {
                        reviewerRow(label: "Pending review", logins: pending, color: .secondary, icon: "clock.fill")
                    }
                }
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private func reviewerRow(label: String, logins: [String], color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text("\(label): \(logins.map { "@\($0)" }.joined(separator: ", "))")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var checksSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checks")
                .font(.headline)

            if let checkRuns = metadata.checkRuns {
                if checkRuns.isEmpty {
                    Text("No check runs")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(checkRuns, id: \.name) { run in
                        checkRunRow(run)
                    }
                }
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private func checkRunRow(_ run: GitHubCheckRun) -> some View {
        HStack(spacing: 6) {
            checkRunIcon(run)
            Text(run.name)
                .font(.subheadline)
            Spacer()
            Text(checkRunStatusText(run))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkRunIcon(_ run: GitHubCheckRun) -> some View {
        let (name, color): (String, Color) = {
            if run.isPassing { return ("checkmark.circle.fill", .green) }
            if run.isFailing { return ("xmark.circle.fill", .red) }
            if run.status != .completed { return ("clock.fill", .orange) }
            return ("circle", .secondary)
        }()
        return Image(systemName: name)
            .foregroundStyle(color)
            .font(.caption)
    }

    private func checkRunStatusText(_ run: GitHubCheckRun) -> String {
        if let conclusion = run.conclusion {
            return conclusion.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return run.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch metadata.state.uppercased() {
        case "OPEN": .green
        case "CLOSED": .red
        case "MERGED": .purple
        case "DRAFT": .orange
        default: .secondary
        }
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: metadata.createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return metadata.createdAt
    }

    // MARK: - Comments Section

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PR Comments (\(postedComments.count))")
                .font(.headline)

            ForEach(postedComments, id: \.id) { comment in
                commentRow(comment)
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: GitHubComment) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.green)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let author = comment.author {
                        Text(author.name.flatMap { $0.isEmpty ? nil : $0 } ?? author.login)
                            .font(.subheadline.bold())
                    }

                    if let createdAt = comment.createdAt {
                        Text(createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let urlString = comment.url, let url = URL(string: urlString) {
                        Link("View on GitHub", destination: url)
                            .font(.caption)
                    }
                }

                RichContentView(comment.body, imageURLMap: imageURLMap, imageBaseDir: imageBaseDir)
            }
            .padding(12)
        }
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}
