import AIOutputSDK
import Foundation

public struct AITask<Output: Decodable & Sendable>: PipelineNode {
    public static var outputKey: PipelineContextKey<Output> { .init("AITask.output.\(Output.self)") }
    public static var metricsKey: PipelineContextKey<AIMetrics> { .init("AITask.metrics") }

    public let client: any AIClient
    public let displayName: String
    public let environment: [String: String]?
    public let id: String
    public let instructions: String
    public let jsonSchema: String?
    public let workingDirectory: String?

    public init(
        id: String,
        displayName: String,
        instructions: String,
        client: any AIClient,
        jsonSchema: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.client = client
        self.displayName = displayName
        self.environment = environment
        self.id = id
        self.instructions = instructions
        self.jsonSchema = jsonSchema
        self.workingDirectory = workingDirectory
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        var updated = context
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            environment: environment,
            workingDirectory: workingDirectory
        )
        let metricsBox = MetricsBox()

        if let schema = jsonSchema {
            let result = try await client.runStructured(
                Output.self,
                prompt: instructions,
                jsonSchema: schema,
                options: options,
                onOutput: { text in onProgress(.output(text)) },
                onStreamEvent: { event in
                    if case let .metrics(duration, cost, turns) = event {
                        metricsBox.set(AIMetrics(cost: cost, duration: duration, turns: turns))
                    }
                }
            )
            updated[Self.outputKey] = result.value
        } else {
            let textBox = TextBox()
            _ = try await client.run(
                prompt: instructions,
                options: options,
                onOutput: { text in
                    textBox.append(text)
                    onProgress(.output(text))
                },
                onStreamEvent: { event in
                    if case let .metrics(duration, cost, turns) = event {
                        metricsBox.set(AIMetrics(cost: cost, duration: duration, turns: turns))
                    }
                }
            )
            guard let output = textBox.value as? Output else {
                throw PipelineError.outputTypeMismatch(
                    expected: "\(Output.self)",
                    received: "String"
                )
            }
            updated[Self.outputKey] = output
        }

        if let metrics = metricsBox.value {
            updated[Self.metricsKey] = metrics
        }

        return updated
    }
}

private final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ s: String) {
        lock.lock()
        defer { lock.unlock() }
        text += s
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

private final class MetricsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var metrics: AIMetrics?

    func set(_ m: AIMetrics) {
        lock.lock()
        defer { lock.unlock() }
        metrics = m
    }

    var value: AIMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }
}
