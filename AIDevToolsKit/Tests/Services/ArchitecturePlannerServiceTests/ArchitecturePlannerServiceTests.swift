import Foundation
import SwiftData
import Testing
@testable import ArchitecturePlannerService

@Suite
struct ArchitecturePlannerModelTests {

    @Test func planningJobCreation() throws {
        let job = PlanningJob(repoName: "TestRepo", repoPath: "/tmp/test")
        #expect(job.repoName == "TestRepo")
        #expect(job.repoPath == "/tmp/test")
        #expect(job.currentStepIndex == 0)
        #expect(job.requirements.isEmpty)
        #expect(job.implementationComponents.isEmpty)
        #expect(job.processSteps.isEmpty)
        #expect(job.followupItems.isEmpty)
    }

    @Test func architectureRequestCreation() throws {
        let request = ArchitectureRequest(text: "Build a new feature")
        #expect(request.text == "Build a new feature")
    }

    @Test func requirementCreation() throws {
        let req = Requirement(summary: "Test requirement", details: "Some details", sortOrder: 0)
        #expect(req.summary == "Test requirement")
        #expect(req.details == "Some details")
        #expect(!req.isApproved)
        #expect(req.sortOrder == 0)
    }

    @Test func guidelineCreation() throws {
        let guideline = Guideline(
            repoName: "TestRepo",
            title: "Layer Rules",
            body: "Keep services pure",
            filePathGlobs: ["Sources/Services/**"],
            descriptionMatchers: ["service layer"],
            goodExamples: ["struct MyService {}"],
            badExamples: ["class MyService: UIViewController {}"],
            highLevelOverview: "Services should not depend on UI"
        )
        #expect(guideline.title == "Layer Rules")
        #expect(guideline.filePathGlobs == ["Sources/Services/**"])
        #expect(guideline.goodExamples.count == 1)
        #expect(guideline.badExamples.count == 1)
    }

    @Test func guidelineCategoryCreation() throws {
        let cat = GuidelineCategory(name: "architecture", repoName: "TestRepo", summary: "Architecture rules")
        #expect(cat.name == "architecture")
        #expect(cat.repoName == "TestRepo")
    }

    @Test func implementationComponentCreation() throws {
        let comp = ImplementationComponent(
            summary: "Add new model",
            details: "Create SwiftData model",
            filePaths: ["Sources/Services/MyService/Model.swift"],
            layerName: "Services",
            moduleName: "MyService",
            sortOrder: 0,
            phaseNumber: 1
        )
        #expect(comp.summary == "Add new model")
        #expect(comp.layerName == "Services")
        #expect(comp.phaseNumber == 1)
    }

    @Test func guidelineMappingCreation() throws {
        let mapping = GuidelineMapping(
            matchReason: "File path matches",
            conformanceScore: 8,
            scoreRationale: "Good adherence"
        )
        #expect(mapping.conformanceScore == 8)
        #expect(mapping.matchReason == "File path matches")
    }

    @Test func processStepCreation() throws {
        let step = ProcessStep(stepIndex: 0, name: "Describe Feature")
        #expect(step.stepIndex == 0)
        #expect(step.name == "Describe Feature")
        #expect(step.status == "pending")
    }

    @Test func unclearFlagCreation() throws {
        let flag = UnclearFlag(
            guidelineTitle: "Layer Rules",
            ambiguityDescription: "Unclear if SDK can depend on another SDK",
            choiceMade: "Allowed it based on existing patterns"
        )
        #expect(flag.guidelineTitle == "Layer Rules")
        #expect(!flag.isPromotedToFollowup)
    }

    @Test func phaseDecisionCreation() throws {
        let decision = PhaseDecision(
            guidelineTitle: "Clean Architecture",
            decision: "Placed logic in feature layer",
            rationale: "Business logic belongs in features",
            phaseNumber: 1
        )
        #expect(decision.phaseNumber == 1)
        #expect(!decision.wasSkipped)
    }

    @Test func followupItemCreation() throws {
        let item = FollowupItem(summary: "Add caching", details: "Consider adding a cache layer")
        #expect(item.summary == "Add caching")
        #expect(!item.isResolved)
    }

    @Test func defaultStepDefinitions() throws {
        let steps = ArchitecturePlannerStep.defaultSteps()
        #expect(steps.count == ArchitecturePlannerStep.allCases.count)
        #expect(steps[0].name == "Describe Feature")
        #expect(steps[1].name == "Form Requirements")
        #expect(steps[9].name == "Compile Followups")
    }

    @Test func stepNameMapping() throws {
        #expect(ArchitecturePlannerStep.describeFeature.name == "Describe Feature")
        #expect(ArchitecturePlannerStep.formRequirements.name == "Form Requirements")
        #expect(ArchitecturePlannerStep.compileArchitectureInfo.name == "Compile Architecture Info")
        #expect(ArchitecturePlannerStep.planAcrossLayers.name == "Plan Across Layers")
        #expect(ArchitecturePlannerStep.checklistValidation.name == "Checklist Validation")
        #expect(ArchitecturePlannerStep.buildImplementationModel.name == "Build Implementation Model")
        #expect(ArchitecturePlannerStep.reviewImplementationPlan.name == "Review Implementation Plan")
        #expect(ArchitecturePlannerStep.executeImplementation.name == "Execute Implementation")
        #expect(ArchitecturePlannerStep.finalReport.name == "Final Report")
        #expect(ArchitecturePlannerStep.followups.name == "Compile Followups")
    }
}

@Suite
struct ArchitecturePlannerStoreTests {

    @Test func storeCreation() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-store-\(UUID().uuidString.prefix(8))")
        let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
        #expect(store.container.schema.entities.count > 0)
    }
}
