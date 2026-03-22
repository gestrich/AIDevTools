import ArchitecturePlannerService
import SwiftUI

struct GuidelineBrowserView: View {
    let guidelines: [Guideline]
    let componentGuidelines: [GuidelineMapping]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Guidelines")
                    .font(.title2)
                    .bold()

                // Applied guidelines
                if !componentGuidelines.isEmpty {
                    Section {
                        ForEach(componentGuidelines, id: \.mappingId) { mapping in
                            GuidelineMappingRow(mapping: mapping)
                        }
                    } header: {
                        Text("Applied to Current Component")
                            .font(.headline)
                    }
                }

                Divider()

                // All guidelines by category
                let byCat = Dictionary(grouping: guidelines) { guideline -> String in
                    guideline.categories.first?.name ?? "Uncategorized"
                }

                ForEach(Array(byCat.keys.sorted()), id: \.self) { category in
                    Section {
                        if let catGuidelines = byCat[category] {
                            ForEach(catGuidelines, id: \.guidelineId) { guideline in
                                GuidelineRow(
                                    guideline: guideline,
                                    isApplied: componentGuidelines.contains { $0.guideline?.guidelineId == guideline.guidelineId }
                                )
                            }
                        }
                    } header: {
                        Text(category)
                            .font(.headline)
                    }
                }
            }
            .padding()
        }
    }
}

struct GuidelineMappingRow: View {
    let mapping: GuidelineMapping

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(mapping.guideline?.title ?? "Unknown Guideline")
                    .font(.body)
                    .bold()
                Spacer()
                Text("\(mapping.conformanceScore)/10")
                    .font(.headline)
                    .foregroundStyle(scoreColor)
            }
            Text("Match: \(mapping.matchReason)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Score: \(mapping.scoreRationale)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.background.secondary)
        .cornerRadius(8)
    }

    private var scoreColor: Color {
        switch mapping.conformanceScore {
        case 8...10: return .green
        case 5...7: return .orange
        default: return .red
        }
    }
}

struct GuidelineRow: View {
    let guideline: Guideline
    let isApplied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(guideline.title)
                    .font(.body)
                    .bold()
                if isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if !guideline.highLevelOverview.isEmpty {
                Text(guideline.highLevelOverview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !guideline.filePathGlobs.isEmpty {
                Text("Paths: \(guideline.filePathGlobs.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(6)
        .background(isApplied ? Color.green.opacity(0.05) : Color.clear)
        .cornerRadius(6)
    }
}
