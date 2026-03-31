/// Domain model for Claude Code execution cost breakdown.
import Foundation

/// Pricing information for a Claude model.
///
/// All rates are in USD per million tokens (MTok).
/// Based on official Anthropic pricing: https://docs.anthropic.com/en/docs/about-claude/pricing
public struct ClaudeModel {
    /// Pattern to match in model name (e.g., "claude-3-haiku")
    public let pattern: String
    
    /// $ per MTok for input tokens
    public let inputRate: Double
    
    /// $ per MTok for output tokens
    public let outputRate: Double
    
    /// $ per MTok for cache write tokens
    public let cacheWriteRate: Double
    
    /// $ per MTok for cache read tokens
    public let cacheReadRate: Double
    
    public init(pattern: String, inputRate: Double, outputRate: Double, cacheWriteRate: Double, cacheReadRate: Double) {
        self.pattern = pattern
        self.inputRate = inputRate
        self.outputRate = outputRate
        self.cacheWriteRate = cacheWriteRate
        self.cacheReadRate = cacheReadRate
    }
    
    /// Calculate cost for given token counts.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    ///   - cacheWriteTokens: Number of cache write tokens
    ///   - cacheReadTokens: Number of cache read tokens
    /// - Returns: Total cost in USD
    public func calculateCost(
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        return (
            Double(inputTokens) * inputRate
            + Double(outputTokens) * outputRate
            + Double(cacheWriteTokens) * cacheWriteRate
            + Double(cacheReadTokens) * cacheReadRate
        ) / 1_000_000
    }
}

/// Claude model pricing registry
/// Source: https://docs.anthropic.com/en/docs/about-claude/pricing
public let claudeModels: [ClaudeModel] = [
    // Haiku 3 - unique cache multipliers (1.2x write, 0.12x read)
    ClaudeModel(
        pattern: "claude-3-haiku",
        inputRate: 0.25,
        outputRate: 1.25,
        cacheWriteRate: 0.30,
        cacheReadRate: 0.03
    ),
    // Haiku 4/4.5 - standard multipliers (1.25x write, 0.1x read)
    ClaudeModel(
        pattern: "claude-haiku-4",
        inputRate: 1.00,
        outputRate: 5.00,
        cacheWriteRate: 1.25,
        cacheReadRate: 0.10
    ),
    // Sonnet 3.5 - standard multipliers
    ClaudeModel(
        pattern: "claude-3-5-sonnet",
        inputRate: 3.00,
        outputRate: 15.00,
        cacheWriteRate: 3.75,
        cacheReadRate: 0.30
    ),
    // Sonnet 4/4.5 - standard multipliers
    ClaudeModel(
        pattern: "claude-sonnet-4",
        inputRate: 3.00,
        outputRate: 15.00,
        cacheWriteRate: 3.75,
        cacheReadRate: 0.30
    ),
    // Opus 4/4.5 - standard multipliers
    ClaudeModel(
        pattern: "claude-opus-4",
        inputRate: 15.00,
        outputRate: 75.00,
        cacheWriteRate: 18.75,
        cacheReadRate: 1.50
    ),
]

/// Raised when a model name is not recognized for pricing.
public struct UnknownModelError: Error {
    public let message: String
    
    public init(_ message: String) {
        self.message = message
    }
}

/// Get the ClaudeModel for a model name.
///
/// - Parameter modelName: Model name from execution file (e.g., "claude-3-haiku-20240307")
/// - Returns: ClaudeModel with pricing information
/// - Throws: UnknownModelError if model name doesn't match any known patterns
public func getModel(_ modelName: String) throws -> ClaudeModel {
    let modelLower = modelName.lowercased()
    
    for claudeModel in claudeModels {
        if modelLower.contains(claudeModel.pattern) {
            return claudeModel
        }
    }
    
    throw UnknownModelError("Unknown model '\(modelName)'. Add pricing to claudeModels in CostBreakdown.swift")
}

/// Get the input token rate (per MTok) for a model.
///
/// - Parameter modelName: Model name from execution file (e.g., "claude-3-haiku-20240307")
/// - Returns: Rate per million input tokens
/// - Throws: UnknownModelError if model name doesn't match any known patterns
public func getRateForModel(_ modelName: String) throws -> Double {
    return try getModel(modelName).inputRate
}

/// Usage data for a single model within a Claude Code execution.
public struct ModelUsage {
    public let model: String
    public let cost: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    
    public init(
        model: String,
        cost: Double = 0.0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0
    ) {
        self.model = model
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }
    
    /// Total tokens for this model.
    public var totalTokens: Int {
        return inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
    
    /// Calculate cost using correct per-model pricing.
    ///
    /// - Returns: Calculated cost in USD
    /// - Throws: UnknownModelError if model is not recognized
    public func calculateCost() throws -> Double {
        let claudeModel = try getModel(model)
        return claudeModel.calculateCost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
    
    /// Parse model usage from execution file modelUsage entry.
    ///
    /// - Parameters:
    ///   - model: Model name/identifier
    ///   - data: Dict with inputTokens, outputTokens, etc.
    /// - Returns: ModelUsage instance
    /// - Throws: ConfigurationError if data format is invalid
    public static func fromDict(model: String, data: [String: Any]) throws -> ModelUsage {
        func safeInt(_ value: Any?) -> Int {
            if let intValue = value as? Int {
                return intValue
            } else if let doubleValue = value as? Double {
                return Int(doubleValue)
            } else if let stringValue = value as? String, let intValue = Int(stringValue) {
                return intValue
            }
            return 0
        }
        
        func safeDouble(_ value: Any?) -> Double {
            if let doubleValue = value as? Double {
                return doubleValue
            } else if let intValue = value as? Int {
                return Double(intValue)
            } else if let stringValue = value as? String, let doubleValue = Double(stringValue) {
                return doubleValue
            }
            return 0.0
        }
        
        return ModelUsage(
            model: model,
            cost: safeDouble(data["costUSD"]),
            inputTokens: safeInt(data["inputTokens"]),
            outputTokens: safeInt(data["outputTokens"]),
            cacheReadTokens: safeInt(data["cacheReadInputTokens"]),
            cacheWriteTokens: safeInt(data["cacheCreationInputTokens"])
        )
    }
}

/// Usage data from a single Claude Code execution.
public struct ExecutionUsage {
    public let models: [ModelUsage]
    
    /// Top-level cost from execution file (may differ from sum of model costs)
    public let totalCostUSD: Double
    
    public init(models: [ModelUsage] = [], totalCostUSD: Double = 0.0) {
        self.models = models
        self.totalCostUSD = totalCostUSD
    }
    
    /// Total cost (uses top-level totalCostUSD from file).
    public var cost: Double {
        return totalCostUSD
    }
    
    /// Calculate total cost using correct per-model pricing.
    ///
    /// Sums calculateCost() across all models, using hardcoded rates.
    public var calculatedCost: Double {
        return models.compactMap { try? $0.calculateCost() }.reduce(0, +)
    }
    
    /// Sum of input tokens across all models.
    public var inputTokens: Int {
        return models.reduce(0) { $0 + $1.inputTokens }
    }
    
    /// Sum of output tokens across all models.
    public var outputTokens: Int {
        return models.reduce(0) { $0 + $1.outputTokens }
    }
    
    /// Sum of cache read tokens across all models.
    public var cacheReadTokens: Int {
        return models.reduce(0) { $0 + $1.cacheReadTokens }
    }
    
    /// Sum of cache write tokens across all models.
    public var cacheWriteTokens: Int {
        return models.reduce(0) { $0 + $1.cacheWriteTokens }
    }
    
    /// Sum of all tokens across all models.
    public var totalTokens: Int {
        return models.reduce(0) { $0 + $1.totalTokens }
    }
    
    /// Combine two ExecutionUsage instances.
    public static func + (lhs: ExecutionUsage, rhs: ExecutionUsage) -> ExecutionUsage {
        return ExecutionUsage(
            models: lhs.models + rhs.models,
            totalCostUSD: lhs.totalCostUSD + rhs.totalCostUSD
        )
    }
    
    /// Extract usage data from a Claude Code execution file.
    ///
    /// - Parameter executionFile: Path to execution file
    /// - Returns: ExecutionUsage with cost and per-model usage
    /// - Throws: Various errors for file/parsing issues
    public static func fromExecutionFile(_ executionFile: String) throws -> ExecutionUsage {
        guard !executionFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError("execution_file cannot be empty")
        }
        
        guard FileManager.default.fileExists(atPath: executionFile) else {
            throw FileNotFoundError("Execution file not found: \(executionFile)")
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: executionFile))
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        
        // Handle list format (may have multiple executions)
        let dict: [String: Any]
        if let array = jsonObject as? [Any] {
            // Filter to only items that have cost information
            let itemsWithCost = array.compactMap { item -> [String: Any]? in
                guard let itemDict = item as? [String: Any],
                      itemDict["total_cost_usd"] != nil else {
                    return nil
                }
                return itemDict
            }
            
            if !itemsWithCost.isEmpty {
                dict = itemsWithCost.last!
            } else if let lastItem = array.last as? [String: Any] {
                dict = lastItem
            } else {
                throw ConfigurationError("Execution file contains empty list: \(executionFile)")
            }
        } else if let dictObject = jsonObject as? [String: Any] {
            dict = dictObject
        } else {
            throw ConfigurationError("Execution file must contain a dictionary or array")
        }
        
        return try fromDict(dict)
    }
    
    /// Extract usage data from parsed JSON dict.
    ///
    /// - Parameter data: Parsed JSON data from the execution file
    /// - Returns: ExecutionUsage with cost and per-model usage
    /// - Throws: ConfigurationError for invalid data format
    private static func fromDict(_ data: [String: Any]) throws -> ExecutionUsage {
        // Extract top-level cost
        let totalCost: Double
        if let cost = data["total_cost_usd"] {
            totalCost = cost as? Double ?? 0.0
        } else if let usage = data["usage"] as? [String: Any],
                  let cost = usage["total_cost_usd"] {
            totalCost = cost as? Double ?? 0.0
        } else {
            totalCost = 0.0
        }
        
        // Extract per-model usage
        var models: [ModelUsage] = []
        if let modelUsage = data["modelUsage"] as? [String: Any] {
            for (modelName, modelData) in modelUsage {
                if let modelDict = modelData as? [String: Any] {
                    models.append(try ModelUsage.fromDict(model: modelName, data: modelDict))
                }
            }
        }
        
        return ExecutionUsage(models: models, totalCostUSD: totalCost)
    }
}

/// Domain model for Claude Code execution cost breakdown.
public struct CostBreakdown {
    public let mainCost: Double
    public let reviewCost: Double
    public let summaryCost: Double

    // Token counts (summed across all models in modelUsage)
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int

    // Per-model breakdowns for detailed display
    public let mainModels: [ModelUsage]
    public let reviewModels: [ModelUsage]
    public let summaryModels: [ModelUsage]

    public init(
        mainCost: Double,
        reviewCost: Double = 0.0,
        summaryCost: Double,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        mainModels: [ModelUsage] = [],
        reviewModels: [ModelUsage] = [],
        summaryModels: [ModelUsage] = []
    ) {
        self.mainCost = mainCost
        self.reviewCost = reviewCost
        self.summaryCost = summaryCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.mainModels = mainModels
        self.reviewModels = reviewModels
        self.summaryModels = summaryModels
    }
    
    /// Calculate total cost.
    public var totalCost: Double {
        return mainCost + reviewCost + summaryCost
    }
    
    /// Parse cost and token information from execution files.
    ///
    /// - Parameters:
    ///   - mainExecutionFile: Path to main execution file
    ///   - reviewExecutionFile: Optional path to review execution file
    ///   - summaryExecutionFile: Path to summary execution file
    /// - Returns: CostBreakdown with costs and tokens extracted from files
    /// - Throws: Various errors for file/parsing issues
    public static func fromExecutionFiles(
        mainExecutionFile: String,
        reviewExecutionFile: String? = nil,
        summaryExecutionFile: String
    ) throws -> CostBreakdown {
        let mainUsage = try ExecutionUsage.fromExecutionFile(mainExecutionFile)
        let reviewUsage = try reviewExecutionFile.map { try ExecutionUsage.fromExecutionFile($0) }
        let summaryUsage = try ExecutionUsage.fromExecutionFile(summaryExecutionFile)
        let totalUsage = mainUsage + (reviewUsage ?? ExecutionUsage()) + summaryUsage

        return CostBreakdown(
            mainCost: mainUsage.calculatedCost,
            reviewCost: reviewUsage?.calculatedCost ?? 0.0,
            summaryCost: summaryUsage.calculatedCost,
            inputTokens: totalUsage.inputTokens,
            outputTokens: totalUsage.outputTokens,
            cacheReadTokens: totalUsage.cacheReadTokens,
            cacheWriteTokens: totalUsage.cacheWriteTokens,
            mainModels: mainUsage.models,
            reviewModels: reviewUsage?.models ?? [],
            summaryModels: summaryUsage.models
        )
    }
    
    /// Calculate total token count (all token types).
    public var totalTokens: Int {
        return inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
    
    /// Get all models from main, review, and summary executions.
    public var allModels: [ModelUsage] {
        return mainModels + reviewModels + summaryModels
    }
    
    /// Aggregate model usage across main and summary executions.
    ///
    /// Models with the same name are combined into a single entry.
    ///
    /// - Returns: Array of ModelUsage with unique model names, tokens/costs summed.
    public func getAggregatedModels() -> [ModelUsage] {
        var aggregated: [String: ModelUsage] = [:]
        
        for model in allModels {
            if let existing = aggregated[model.model] {
                aggregated[model.model] = ModelUsage(
                    model: model.model,
                    cost: existing.cost + model.cost,
                    inputTokens: existing.inputTokens + model.inputTokens,
                    outputTokens: existing.outputTokens + model.outputTokens,
                    cacheReadTokens: existing.cacheReadTokens + model.cacheReadTokens,
                    cacheWriteTokens: existing.cacheWriteTokens + model.cacheWriteTokens
                )
            } else {
                aggregated[model.model] = model
            }
        }
        
        return Array(aggregated.values)
    }
    
    /// Convert per-model breakdown to JSON-serializable format.
    ///
    /// - Returns: Array of dictionaries with model breakdown data for downstream steps.
    public func toModelBreakdownJSON() -> [[String: Any]] {
        let models = getAggregatedModels()
        return models.compactMap { model in
            guard let cost = try? model.calculateCost() else { return nil }
            return [
                "model": model.model,
                "input_tokens": model.inputTokens,
                "output_tokens": model.outputTokens,
                "cache_read_tokens": model.cacheReadTokens,
                "cache_write_tokens": model.cacheWriteTokens,
                "cost": cost
            ]
        }
    }
    
    /// Serialize to JSON for passing between workflow steps.
    ///
    /// - Returns: JSON string containing all cost breakdown data.
    /// - Throws: Error if JSON serialization fails
    public func toJSON() throws -> String {
        let dict: [String: Any] = [
            "main_cost": mainCost,
            "review_cost": reviewCost,
            "summary_cost": summaryCost,
            "input_tokens": inputTokens,
            "output_tokens": outputTokens,
            "cache_read_tokens": cacheReadTokens,
            "cache_write_tokens": cacheWriteTokens,
            "models": getAggregatedModels().map { model in
                [
                    "model": model.model,
                    "input_tokens": model.inputTokens,
                    "output_tokens": model.outputTokens,
                    "cache_read_tokens": model.cacheReadTokens,
                    "cache_write_tokens": model.cacheWriteTokens
                ]
            }
        ]
        
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Deserialize from JSON.
    ///
    /// - Parameter jsonStr: JSON string from toJSON()
    /// - Returns: CostBreakdown instance with all data restored.
    /// - Throws: Error if JSON is invalid or required fields are missing
    public static func fromJSON(_ jsonStr: String) throws -> CostBreakdown {
        guard let data = jsonStr.data(using: .utf8) else {
            throw ConfigurationError("Invalid JSON string encoding")
        }
        
        let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let dict = dict else {
            throw ConfigurationError("JSON does not contain a dictionary")
        }
        
        // Parse model usage data
        let models: [ModelUsage]
        if let modelsData = dict["models"] as? [[String: Any]] {
            models = modelsData.compactMap { modelDict in
                guard let modelName = modelDict["model"] as? String else { return nil }
                return try? ModelUsage.fromDict(model: modelName, data: modelDict)
            }
        } else {
            models = []
        }
        
        return CostBreakdown(
            mainCost: dict["main_cost"] as? Double ?? 0.0,
            reviewCost: dict["review_cost"] as? Double ?? 0.0,
            summaryCost: dict["summary_cost"] as? Double ?? 0.0,
            inputTokens: dict["input_tokens"] as? Int ?? 0,
            outputTokens: dict["output_tokens"] as? Int ?? 0,
            cacheReadTokens: dict["cache_read_tokens"] as? Int ?? 0,
            cacheWriteTokens: dict["cache_write_tokens"] as? Int ?? 0,
            // Store aggregated models in mainModels (they're already aggregated)
            mainModels: models,
            summaryModels: []
        )
    }
}