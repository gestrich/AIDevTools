import Foundation

/// Defines the ordered steps in the architecture-driven planning flow.
public enum ArchitecturePlannerStep: Int, CaseIterable, Sendable {
    case describeFeature = 0
    case formRequirements = 1
    case compileArchitectureInfo = 2
    case planAcrossLayers = 3
    case checklistValidation = 4
    case buildImplementationModel = 5
    case reviewImplementationPlan = 6
    case executeImplementation = 7
    case finalReport = 8
    case followups = 9

    public var name: String {
        switch self {
        case .describeFeature: return "Describe Feature"
        case .formRequirements: return "Form Requirements"
        case .compileArchitectureInfo: return "Compile Architecture Info"
        case .planAcrossLayers: return "Plan Across Layers"
        case .checklistValidation: return "Checklist Validation"
        case .buildImplementationModel: return "Build Implementation Model"
        case .reviewImplementationPlan: return "Review Implementation Plan"
        case .executeImplementation: return "Execute Implementation"
        case .finalReport: return "Final Report"
        case .followups: return "Compile Followups"
        }
    }

    /// The CLI-friendly name used in `--step` arguments.
    public var cliName: String {
        switch self {
        case .describeFeature: return "describe-feature"
        case .formRequirements: return "form-requirements"
        case .compileArchitectureInfo: return "compile-arch-info"
        case .planAcrossLayers: return "plan-across-layers"
        case .checklistValidation: return "checklist-validation"
        case .buildImplementationModel: return "build-implementation-model"
        case .executeImplementation: return "execute"
        case .finalReport: return "report"
        case .followups: return "followups"
        case .reviewImplementationPlan: return "review-implementation-plan"
        }
    }

    /// Resolves a CLI step name to the corresponding step.
    public static func fromCLIName(_ name: String) -> ArchitecturePlannerStep? {
        allCases.first { $0.cliName == name }
    }

    /// Creates default ProcessStep models for a new PlanningJob.
    public static func defaultSteps() -> [ProcessStep] {
        allCases.map { step in
            ProcessStep(stepIndex: step.rawValue, name: step.name)
        }
    }
}
