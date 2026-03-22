import Foundation

// MARK: - ArchitectureDiagram

public struct ArchitectureDiagram: Codable, Sendable, Equatable {
    public let layers: [ArchitectureLayer]

    public var affectedModuleCount: Int {
        layers.flatMap(\.modules).filter(\.isAffected).count
    }

    public init(layers: [ArchitectureLayer]) {
        self.layers = layers
    }
}

// MARK: - ArchitectureLayer

public struct ArchitectureLayer: Codable, Sendable, Equatable {
    public let name: String
    public let dependsOn: [String]?
    public let modules: [ArchitectureModule]

    public init(name: String, dependsOn: [String]? = nil, modules: [ArchitectureModule]) {
        self.name = name
        self.dependsOn = dependsOn
        self.modules = modules
    }
}

// MARK: - ArchitectureModule

public struct ArchitectureModule: Codable, Sendable, Equatable {
    public let name: String
    public let changes: [ArchitectureChange]

    public var isAffected: Bool { !changes.isEmpty }

    public init(name: String, changes: [ArchitectureChange]) {
        self.name = name
        self.changes = changes
    }
}

// MARK: - ArchitectureChange

public struct ArchitectureChange: Codable, Sendable, Equatable {
    public let file: String
    public let action: ChangeAction
    public let summary: String?
    public let phase: Int?

    public init(file: String, action: ChangeAction, summary: String? = nil, phase: Int? = nil) {
        self.file = file
        self.action = action
        self.summary = summary
        self.phase = phase
    }
}

// MARK: - ChangeAction

public enum ChangeAction: String, Codable, Sendable, Equatable {
    case add
    case delete
    case modify
}
