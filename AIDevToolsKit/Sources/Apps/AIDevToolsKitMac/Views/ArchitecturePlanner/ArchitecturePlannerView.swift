import ArchitecturePlannerService
import SwiftUI

struct ArchitecturePlannerView: View {
    @Bindable var model: ArchitecturePlannerModel

    var body: some View {
        HSplitView {
            jobListSidebar
                .frame(minWidth: 200, maxWidth: 300)

            if let job = model.selectedJob {
                ArchitecturePlannerDetailView(model: model, job: job)
            } else {
                ContentUnavailableView(
                    "No Job Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a planning job or create a new one")
                )
            }
        }
    }

    private var jobListSidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { model.selectedJob?.jobId },
                set: { newId in
                    model.selectedJob = model.jobs.first { $0.jobId == newId }
                }
            )) {
                ForEach(model.jobs, id: \.jobId) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.request?.text.prefix(60).description ?? "Untitled")
                            .font(.headline)
                            .lineLimit(2)
                        HStack {
                            Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            let completedSteps = job.processSteps.filter { $0.status == "completed" }.count
                            Text("\(completedSteps)/\(job.processSteps.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(job.jobId)
                    .padding(.vertical, 2)
                }
            }

            Divider()

            VStack(spacing: 8) {
                TextField("Describe your feature...", text: $model.featureDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Button("Create Job") {
                    Task { await model.createJob() }
                }
                .disabled(model.featureDescription.isEmpty)
            }
            .padding()
        }
    }
}
