import ArchitecturePlannerService
import Foundation
import SwiftData

/// Generates a final report summarizing the entire architecture planning flow.
public struct GenerateReportUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID

        public init(jobId: UUID) {
            self.jobId = jobId
        }
    }

    public struct Result: Sendable {
        public let report: String

        public init(report: String) {
            self.report = report
        }
    }

    public init() {}

    @MainActor
    public func run(_ options: Options, store: ArchitecturePlannerStore) throws -> Result {
        let context = store.createContext()

        let jobId = options.jobId
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        guard let job = try context.fetch(descriptor).first else {
            throw ArchitecturePlannerError.jobNotFound(jobId)
        }

        var lines: [String] = []
        lines.append("# Architecture Planning Report")
        lines.append("")
        lines.append("**Repository:** \(job.repoName)")
        lines.append("**Created:** \(job.createdAt.formatted())")
        lines.append("**Updated:** \(job.updatedAt.formatted())")
        lines.append("")

        // Request
        if let request = job.request {
            lines.append("## Feature Request")
            lines.append(request.text)
            lines.append("")
        }

        // Requirements
        let requirements = job.requirements.sorted(by: { $0.sortOrder < $1.sortOrder })
        if !requirements.isEmpty {
            lines.append("## Requirements (\(requirements.count))")
            for req in requirements {
                let status = req.isApproved ? "✅" : "⏳"
                lines.append("- \(status) **\(req.summary)**: \(req.details)")
            }
            lines.append("")
        }

        // Implementation Components
        let components = job.implementationComponents.sorted(by: { $0.sortOrder < $1.sortOrder })
        if !components.isEmpty {
            lines.append("## Implementation Components (\(components.count))")
            for comp in components {
                lines.append("### \(comp.summary)")
                lines.append("- **Layer:** \(comp.layerName)/\(comp.moduleName)")
                lines.append("- **Files:** \(comp.filePaths.joined(separator: ", "))")
                if !comp.tradeoffs.isEmpty {
                    lines.append("- **Tradeoffs:** \(comp.tradeoffs)")
                }

                // Guideline mappings
                let mappings = comp.guidelineMappings
                if !mappings.isEmpty {
                    lines.append("- **Guidelines:**")
                    for mapping in mappings {
                        let title = mapping.guideline?.title ?? "Unknown"
                        lines.append("  - \(title): \(mapping.conformanceScore)/10 — \(mapping.scoreRationale)")
                    }
                }

                // Unclear flags
                for flag in comp.unclearFlags {
                    lines.append("- ⚠️ **Unclear:** \(flag.guidelineTitle) — \(flag.ambiguityDescription)")
                }

                // Phase decisions
                for decision in comp.phaseDecisions {
                    lines.append("- 📝 **Decision (Phase \(decision.phaseNumber)):** \(decision.decision) — \(decision.rationale)")
                }
                lines.append("")
            }
        }

        // Process Steps
        let steps = job.processSteps.sorted(by: { $0.stepIndex < $1.stepIndex })
        if !steps.isEmpty {
            lines.append("## Process Steps")
            for step in steps {
                let icon: String
                switch step.status {
                case "completed": icon = "✅"
                case "active": icon = "🔄"
                case "stale": icon = "⚠️"
                default: icon = "⏳"
                }
                lines.append("- \(icon) **\(step.name)**: \(step.summary)")
            }
            lines.append("")
        }

        // Followups
        let followups = job.followupItems
        if !followups.isEmpty {
            lines.append("## Followups")
            for item in followups {
                let status = item.isResolved ? "✅" : "📋"
                lines.append("- \(status) \(item.summary)")
            }
            lines.append("")
        }

        let report = lines.joined(separator: "\n")

        // Update step
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.finalReport.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Report generated"
        job.updatedAt = Date()

        try context.save()

        return Result(report: report)
    }
}
