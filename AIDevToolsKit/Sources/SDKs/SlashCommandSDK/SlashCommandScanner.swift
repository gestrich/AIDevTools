import Foundation

public struct SlashCommandScanner: Sendable {

    public init() {}

    public func scanCommands(workingDirectory: String) -> [SlashCommand] {
        let fileManager = FileManager.default
        var commands: [SlashCommand] = []

        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let globalCommandsDir = (homeDir as NSString).appendingPathComponent(".claude/commands")
        commands.append(contentsOf: scanDirectory(globalCommandsDir))

        let localCommandsDir = (workingDirectory as NSString).appendingPathComponent(".claude/commands")
        commands.append(contentsOf: scanDirectory(localCommandsDir))

        // Remove duplicates, preferring local over global
        var uniqueCommands: [String: SlashCommand] = [:]
        for command in commands {
            uniqueCommands[command.name] = command
        }

        return Array(uniqueCommands.values).sorted { $0.name < $1.name }
    }

    public func filterCommands(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return commands }

        let searchQuery = query.hasPrefix("/") ? String(query.dropFirst()) : query
        let lowercaseQuery = searchQuery.lowercased()

        let scoredCommands: [(command: SlashCommand, score: Int)] = commands.compactMap { command in
            let score = scoreCommand(command.name, query: lowercaseQuery)
            return score > 0 ? (command, score) : nil
        }

        return scoredCommands
            .sorted { $0.score > $1.score }
            .map(\.command)
    }

    private func scanDirectory(_ directory: String) -> [SlashCommand] {
        let fileManager = FileManager.default
        var commands: [SlashCommand] = []

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            return commands
        }

        while let file = enumerator.nextObject() as? String {
            guard file.hasSuffix(".md") else { continue }

            let commandPath = (file as NSString).deletingPathExtension
            let commandName = "/\(commandPath)"

            let fullPath = (directory as NSString).appendingPathComponent(file)
            commands.append(SlashCommand(name: commandName, path: fullPath))
        }

        return commands
    }

    private func scoreCommand(_ commandName: String, query: String) -> Int {
        let name = commandName.hasPrefix("/") ? String(commandName.dropFirst()) : commandName
        let lowercaseName = name.lowercased()

        let segments = name.split(separator: "/").map { String($0) }
        let lowercaseSegments = segments.map { $0.lowercased() }

        var bestScore = 0

        for (index, segment) in lowercaseSegments.enumerated() {
            if segment == query {
                return 1000 - (index * 10)
            } else if segment.hasPrefix(query) {
                let score = 500 - (index * 10) - (segment.count - query.count)
                bestScore = max(bestScore, score)
            } else if segment.contains(query) {
                if let range = segment.range(of: query) {
                    let distanceFromStart = segment.distance(from: segment.startIndex, to: range.lowerBound)
                    let score = 250 - (index * 10) - distanceFromStart
                    bestScore = max(bestScore, score)
                }
            }
        }

        if bestScore == 0 && lowercaseName.contains(query) {
            if let range = lowercaseName.range(of: query) {
                let distanceFromStart = lowercaseName.distance(from: lowercaseName.startIndex, to: range.lowerBound)
                bestScore = 100 - distanceFromStart
            }
        }

        return bestScore
    }
}
