/// GitHub event context for simplified workflow handling.
///
/// This module provides parsing and interpretation of GitHub event payloads,
/// enabling ClaudeChain to handle all event-related logic internally rather
/// than requiring users to maintain complex bash scripts in their workflows.
///
/// Following the principle: "Parse once into well-formed models"
import Foundation

/// Parsed GitHub event with extracted fields for ClaudeChain.
///
/// This class encapsulates the logic for interpreting GitHub webhook events
/// and determining how ClaudeChain should respond. It extracts relevant
/// information from the event payload and provides methods for:
/// - Determining if execution should be skipped
/// - Finding the appropriate git ref to checkout
/// - Getting context for changed files detection
public struct GitHubEventContext {
    /// The GitHub event type (workflow_dispatch, pull_request, push)
    public let eventName: String
    
    // For pull_request events
    /// Pull request number (for pull_request events)
    public let prNumber: Int?
    
    /// Whether the PR was merged (for pull_request events)
    public let prMerged: Bool
    
    /// List of label names on the PR
    public let prLabels: [String]
    
    /// The branch the PR targets (for pull_request events)
    public let baseRef: String?
    
    /// The branch the PR comes from (for pull_request events)
    public let headRef: String?
    
    // For push events
    /// The branch pushed to (for push events)
    public let refName: String?
    
    /// SHA before push (for push events)
    public let beforeSHA: String?
    
    /// SHA after push (for push events)
    public let afterSHA: String?
    
    // For workflow_dispatch
    /// Workflow dispatch inputs (for workflow_dispatch events)
    public let inputs: [String: String]
    
    public init(
        eventName: String,
        prNumber: Int? = nil,
        prMerged: Bool = false,
        prLabels: [String] = [],
        baseRef: String? = nil,
        headRef: String? = nil,
        refName: String? = nil,
        beforeSHA: String? = nil,
        afterSHA: String? = nil,
        inputs: [String: String] = [:]
    ) {
        self.eventName = eventName
        self.prNumber = prNumber
        self.prMerged = prMerged
        self.prLabels = prLabels
        self.baseRef = baseRef
        self.headRef = headRef
        self.refName = refName
        self.beforeSHA = beforeSHA
        self.afterSHA = afterSHA
        self.inputs = inputs
    }
    
    /// Parse GitHub event JSON into structured context.
    ///
    /// - Parameters:
    ///   - eventName: The GitHub event name (e.g., "pull_request", "push")
    ///   - eventJSON: The JSON payload from ${{ toJson(github.event) }}
    /// - Returns: GitHubEventContext with all relevant fields extracted
    /// - Throws: Error if eventJSON is not valid JSON
    public static func fromJSON(eventName: String, eventJSON: String) throws -> GitHubEventContext {
        let eventData = eventJSON.data(using: .utf8) ?? Data()
        let event = try JSONSerialization.jsonObject(with: eventData, options: []) as? [String: Any] ?? [:]
        
        var context = GitHubEventContext(eventName: eventName)
        
        switch eventName {
        case "pull_request":
            context = parsePullRequestEvent(context: context, event: event)
        case "push":
            context = parsePushEvent(context: context, event: event)
        case "workflow_dispatch":
            context = parseWorkflowDispatchEvent(context: context, event: event)
        default:
            break
        }
        
        return context
    }
    
    /// Extract fields from pull_request event payload.
    ///
    /// - Parameters:
    ///   - context: Current context to update
    ///   - event: The parsed event JSON
    /// - Returns: Updated context
    private static func parsePullRequestEvent(context: GitHubEventContext, event: [String: Any]) -> GitHubEventContext {
        let pr = event["pull_request"] as? [String: Any] ?? [:]
        let prNumber = pr["number"] as? Int
        let prMerged = pr["merged"] as? Bool ?? false
        let baseRef = (pr["base"] as? [String: Any])?["ref"] as? String
        let headRef = (pr["head"] as? [String: Any])?["ref"] as? String
        
        // Extract labels (can be list of dicts with "name" key or strings)
        var prLabels: [String] = []
        let labelsData = pr["labels"] as? [Any] ?? []
        for label in labelsData {
            if let labelDict = label as? [String: Any],
               let name = labelDict["name"] as? String {
                prLabels.append(name)
            } else if let labelString = label as? String {
                prLabels.append(labelString)
            }
        }
        
        return GitHubEventContext(
            eventName: context.eventName,
            prNumber: prNumber,
            prMerged: prMerged,
            prLabels: prLabels,
            baseRef: baseRef,
            headRef: headRef,
            refName: context.refName,
            beforeSHA: context.beforeSHA,
            afterSHA: context.afterSHA,
            inputs: context.inputs
        )
    }
    
    /// Extract fields from push event payload.
    ///
    /// - Parameters:
    ///   - context: Current context to update
    ///   - event: The parsed event JSON
    /// - Returns: Updated context
    private static func parsePushEvent(context: GitHubEventContext, event: [String: Any]) -> GitHubEventContext {
        // ref is like "refs/heads/main" - extract just the branch name
        let ref = event["ref"] as? String ?? ""
        let refName: String?
        if ref.hasPrefix("refs/heads/") {
            refName = String(ref.dropFirst("refs/heads/".count))
        } else {
            refName = ref.isEmpty ? nil : ref
        }
        
        let beforeSHA = event["before"] as? String
        let afterSHA = event["after"] as? String
        
        return GitHubEventContext(
            eventName: context.eventName,
            prNumber: context.prNumber,
            prMerged: context.prMerged,
            prLabels: context.prLabels,
            baseRef: context.baseRef,
            headRef: context.headRef,
            refName: refName,
            beforeSHA: beforeSHA,
            afterSHA: afterSHA,
            inputs: context.inputs
        )
    }
    
    /// Extract fields from workflow_dispatch event payload.
    ///
    /// - Parameters:
    ///   - context: Current context to update
    ///   - event: The parsed event JSON
    /// - Returns: Updated context
    private static func parseWorkflowDispatchEvent(context: GitHubEventContext, event: [String: Any]) -> GitHubEventContext {
        let inputs = event["inputs"] as? [String: String] ?? [:]
        
        // Also capture the ref for workflow_dispatch (branch that triggered it)
        let ref = event["ref"] as? String ?? ""
        let refName: String?
        if ref.hasPrefix("refs/heads/") {
            refName = String(ref.dropFirst("refs/heads/".count))
        } else {
            refName = ref.isEmpty ? nil : ref
        }
        
        return GitHubEventContext(
            eventName: context.eventName,
            prNumber: context.prNumber,
            prMerged: context.prMerged,
            prLabels: context.prLabels,
            baseRef: context.baseRef,
            headRef: context.headRef,
            refName: refName,
            beforeSHA: context.beforeSHA,
            afterSHA: context.afterSHA,
            inputs: inputs
        )
    }
    
    /// Determine if ClaudeChain should skip this event.
    ///
    /// Checks various conditions to determine if ClaudeChain should not
    /// process this event. Different event types have different skip criteria.
    ///
    /// - Parameters:
    ///   - requiredLabel: Label required on PR for processing (default: "claudechain")
    ///   - requireLabelForPR: If true, PRs must have the requiredLabel to be processed.
    ///     If false, label check is skipped (useful for changed-files triggering model
    ///     where we trigger on spec.md changes regardless of labels).
    /// - Returns: Tuple of (shouldSkip: Bool, reason: String)
    ///   - If shouldSkip is false, reason will be empty string
    ///   - If shouldSkip is true, reason explains why
    public func shouldSkip(
        requiredLabel: String = "claudechain",
        requireLabelForPR: Bool = true
    ) -> (shouldSkip: Bool, reason: String) {
        if eventName == "pull_request" {
            // Skip if PR was not merged
            if !prMerged {
                return (true, "PR was closed but not merged")
            }
            
            // Skip if missing required label (only when label checking is enabled)
            if requireLabelForPR && !requiredLabel.isEmpty && !prLabels.contains(requiredLabel) {
                return (true, "PR does not have required label '\(requiredLabel)'")
            }
        }
        
        // workflow_dispatch and push events don't have skip conditions
        // (they're always intentional triggers)
        
        return (false, "")
    }
    
    /// Determine which git ref to checkout.
    ///
    /// Returns the appropriate git reference to checkout based on the event type:
    /// - For push events: the branch that was pushed to
    /// - For pull_request events: the base branch (target of the PR)
    /// - For workflow_dispatch: the branch that triggered the workflow
    ///
    /// - Returns: Git reference (branch name) to checkout
    /// - Throws: ConfigurationError if no suitable ref can be determined
    public func getCheckoutRef() throws -> String {
        switch eventName {
        case "push":
            guard let refName = refName else {
                throw ConfigurationError("Push event missing ref_name")
            }
            return refName
            
        case "pull_request":
            guard let baseRef = baseRef else {
                throw ConfigurationError("Pull request event missing base_ref")
            }
            return baseRef
            
        case "workflow_dispatch":
            guard let refName = refName else {
                throw ConfigurationError("Workflow dispatch event missing ref")
            }
            return refName
            
        default:
            throw ConfigurationError("Unknown event type: \(eventName)")
        }
    }
    
    /// Get refs for detecting changed files via GitHub Compare API.
    ///
    /// For push events, returns the before and after SHAs.
    /// For pull_request events, returns the base and head branch names.
    /// This enables project detection by looking for modified spec.md files.
    ///
    /// - Returns: Tuple of (baseRef, headRef) for push/pull_request events, nil otherwise.
    ///   The caller can use these refs with the GitHub Compare API.
    public func getChangedFilesContext() -> (baseRef: String, headRef: String)? {
        if eventName == "push", let beforeSHA = beforeSHA, let afterSHA = afterSHA {
            return (beforeSHA, afterSHA)
        }
        if eventName == "pull_request", let baseRef = baseRef, let headRef = headRef {
            return (baseRef, headRef)
        }
        return nil
    }
    
    /// Check if the PR has a specific label.
    ///
    /// - Parameter label: Label name to check for
    /// - Returns: True if the PR has the label, false otherwise
    public func hasLabel(_ label: String) -> Bool {
        return prLabels.contains(label)
    }
}