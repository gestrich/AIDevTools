import Foundation
import Testing
@testable import PlanRunnerService

struct ArchitectureDiagramTests {

    private let sampleJSON = """
    {
      "layers": [
        {
          "name": "Apps",
          "dependsOn": ["Features", "Services", "SDKs"],
          "modules": [
            {
              "name": "AIDevToolsKitMac",
              "changes": [
                {
                  "file": "Sources/Apps/AIDevToolsKitMac/Views/ArchitectureView.swift",
                  "action": "add",
                  "summary": "New view rendering the architecture diagram",
                  "phase": 5
                }
              ]
            },
            {
              "name": "AIDevToolsKitCLI",
              "changes": []
            }
          ]
        },
        {
          "name": "Features",
          "dependsOn": ["Services", "SDKs"],
          "modules": [
            {
              "name": "PlanRunnerFeature",
              "changes": [
                {
                  "file": "Sources/Features/PlanRunnerFeature/usecases/GeneratePlanUseCase.swift",
                  "action": "modify",
                  "summary": "Add architecture JSON generation to Phase 3 prompt",
                  "phase": 4
                }
              ]
            }
          ]
        },
        {
          "name": "Services",
          "dependsOn": ["SDKs"],
          "modules": []
        },
        {
          "name": "SDKs",
          "dependsOn": [],
          "modules": [
            {
              "name": "RepositorySDK",
              "changes": []
            }
          ]
        }
      ]
    }
    """

    @Test func roundTripEncodeDecode() throws {
        let data = Data(sampleJSON.utf8)
        let diagram = try JSONDecoder().decode(ArchitectureDiagram.self, from: data)
        let reencoded = try JSONEncoder().encode(diagram)
        let decoded = try JSONDecoder().decode(ArchitectureDiagram.self, from: reencoded)
        #expect(diagram == decoded)
    }

    @Test func decodesLayersCorrectly() throws {
        let data = Data(sampleJSON.utf8)
        let diagram = try JSONDecoder().decode(ArchitectureDiagram.self, from: data)
        #expect(diagram.layers.count == 4)
        #expect(diagram.layers[0].name == "Apps")
        #expect(diagram.layers[1].name == "Features")
        #expect(diagram.layers[3].dependsOn == [])
    }

    @Test func emptyChangesArrayDecodes() throws {
        let data = Data(sampleJSON.utf8)
        let diagram = try JSONDecoder().decode(ArchitectureDiagram.self, from: data)
        let cli = diagram.layers[0].modules[1]
        #expect(cli.name == "AIDevToolsKitCLI")
        #expect(cli.changes.isEmpty)
    }

    @Test func isAffectedComputedProperty() throws {
        let data = Data(sampleJSON.utf8)
        let diagram = try JSONDecoder().decode(ArchitectureDiagram.self, from: data)
        let mac = diagram.layers[0].modules[0]
        let cli = diagram.layers[0].modules[1]
        #expect(mac.isAffected == true)
        #expect(cli.isAffected == false)
    }

    @Test func affectedModuleCount() throws {
        let data = Data(sampleJSON.utf8)
        let diagram = try JSONDecoder().decode(ArchitectureDiagram.self, from: data)
        #expect(diagram.affectedModuleCount == 2)
    }

    @Test func allActionEnumCases() throws {
        let json = """
        {
          "layers": [{
            "name": "Test",
            "modules": [{
              "name": "Mod",
              "changes": [
                {"file": "a.swift", "action": "add"},
                {"file": "b.swift", "action": "modify"},
                {"file": "c.swift", "action": "delete"}
              ]
            }]
          }]
        }
        """
        let diagram = try JSONDecoder().decode(ArchitectureDiagram.self, from: Data(json.utf8))
        let actions = diagram.layers[0].modules[0].changes.map(\.action)
        #expect(actions == [.add, .modify, .delete])
    }

    @Test func optionalFieldsOmitted() throws {
        let json = """
        {"layers":[{"name":"L","modules":[{"name":"M","changes":[{"file":"f.swift","action":"add"}]}]}]}
        """
        let diagram = try JSONDecoder().decode(ArchitectureDiagram.self, from: Data(json.utf8))
        let change = diagram.layers[0].modules[0].changes[0]
        #expect(change.summary == nil)
        #expect(change.phase == nil)
        #expect(change.action == .add)
    }
}
