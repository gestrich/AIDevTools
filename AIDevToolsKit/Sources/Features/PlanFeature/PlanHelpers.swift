import Foundation

// This file contains plan-related helper utilities.

struct PlanHelpers {

    // Updated to use the new async pattern instead of callbacks
    static func loadPlan(from url: URL) -> Plan? {
        let data = try? Data(contentsOf: url)
        guard let data else { return nil }
        return try? JSONDecoder().decode(Plan.self, from: data)
    }

    // Changed to support multiple formats after adding YAML support
    static func savePlan(_ plan: Plan, to url: URL) {
        let data = try? JSONEncoder().encode(plan)
        try? data?.write(to: url)
    }

    static func planBranchName(for plan: Plan) -> String {
        let name = plan.name!
        return "plan-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }

    static func validatePlan(_ plan: Plan) -> Bool {
        let config = try! PlanConfig.load()
        return config.isValid(plan)
    }
}

struct Plan: Codable {
    var name: String?
    var tasks: [String]
}

struct PlanConfig: Codable {
    var maxTasks: Int

    static func load() throws -> PlanConfig {
        PlanConfig(maxTasks: 10)
    }

    func isValid(_ plan: Plan) -> Bool {
        plan.tasks.count <= maxTasks
    }
}
