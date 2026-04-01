import ArchitecturePlannerService
import RepositorySDK
import SwiftUI

struct ArchitecturePlannerView: View {
    @Environment(ArchitecturePlannerModel.self) var model

    let repository: RepositoryConfiguration

    @State private var showCreateSheet = false

    var body: some View {
        HSplitView {
            WorkspaceSidebar {
                showCreateSheet = true
            } content: {
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
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                model.deleteJob(job)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            if let job = model.selectedJob {
                ArchitecturePlannerDetailView(job: job)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Job Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a planning job or create a new one")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: repository.id) {
            model.loadJobs(repoName: repository.name, repoPath: repository.path.path())
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateArchitectureJobSheet()
        }
    }
}

// MARK: - Create Job Sheet

private struct CreateArchitectureJobSheet: View {
    @Environment(ArchitecturePlannerModel.self) var model
    @Environment(\.dismiss) var dismiss

    @State private var featureDescription = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Architecture Job").font(.headline)

            TextField("Describe your feature...", text: $featureDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    model.featureDescription = featureDescription
                    dismiss()
                    Task { await model.createJob() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(featureDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}
