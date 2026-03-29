## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture — structured output primitives go in SDKs, use cases in Features, models/views in Apps |
| `swift-app-architecture:swift-swiftui` | SwiftUI patterns: @Observable models, view composition, environment injection |

## Background

The app has a variety of views (Plans, Evals, Chains, Skills, Architecture) and CLI functions that depend on AI to perform tasks. Currently, AI interaction is purpose-built: the Plans view uses AI to execute plan phases, the Chains view runs claude chains, etc.

The missing piece is **ad-hoc AI chat that is context-aware**. You should be able to chat with AI while looking at any view, and the AI should:
- Know what view you're looking at and what's selected
- Be able to read and modify data via CLI commands
- Trigger in-app actions (select a plan, navigate to a tab, reload data)
- Eventually capture screenshots and handle cross-process communication

A workspace-level chat panel existed previously (removed in commit `a273f1e5a` on 2026-03-28) but it was generic — no view context, no interaction capabilities. The reusable chat infrastructure (ChatModel, ChatPanelView, ChatMessagesView, SendChatMessageUseCase) remains fully intact.

**Starting point**: The Plans view. Use cases include "change this plan" (AI reads plan via CLI, asks what to change), "take me to another feature" (AI navigates to a different tab/view), and general Q&A about what's on screen.

### Design principles

1. **Structured output is a first-class, generic capability** — not hardcoded action blocks. The client that sets up the chat defines what structured outputs the AI can return, using Swift generics. This is a deep capability of the AI interaction system, not a chat-only concept.

2. **Delegate/callback pattern** — When the AI produces structured output, the system parses it and calls back to a typed delegate. The delegator defines the output types and handles them however it needs.

3. **Lower-level than chat** — Structured output handling lives in `AIOutputSDK` (SDK layer) and flows up through `ChatFeature` (Feature layer) to `ChatModel` (App layer). Any AI interaction can use it, not just chat.

4. **Integrated, not bolted on** — New concepts should feel like first-class citizens of the existing system. This means refactoring interfaces where needed so that structured output flows through the same streaming pipeline as text, thinking, and tool use — not as a side system the client must separately manage.

5. **Pull-based context, not push-based** — The system prompt is stable and sent once at conversation start. It describes the app, the available structured outputs (queries and actions), and CLI capabilities. The AI **pulls** view state on demand via query outputs rather than the app pushing dynamic context on every message. This aligns with how system prompts are intended to work (stable behavioral instructions) and enables prompt caching.

6. **Two-way structured outputs** — Structured outputs are not just fire-and-forget actions. They support both:
   - **Queries**: AI asks the view for data (e.g., "what plan is selected?"). The app responds with data that gets sent back to the AI as a follow-up message.
   - **Actions**: AI tells the view to do something (e.g., "select this plan"). The app executes and optionally confirms.

### Key existing infrastructure

The streaming pipeline today:

```
AIClient.run() → onStreamEvent callback → AsyncStream<AIStreamEvent> → StreamAccumulator → [AIContentBlock] → ChatMessage
```

Types in this pipeline (all in `AIOutputSDK`):
- `AIStreamEvent` — enum: `.textDelta`, `.thinking`, `.toolUse`, `.toolResult`, `.metrics`
- `AIContentBlock` — enum: same cases as stream events but accumulated (text deltas merge into single `.text`)
- `StreamAccumulator` — actor that applies events to produce content blocks
- `AIClientOptions` — carries system prompt, working directory, JSON schema, etc. to providers
- `AIClient` protocol — `run()` and `runStructured<T>()` methods

Higher layers:
- `SendChatMessageUseCase` (ChatFeature) — builds `AIClientOptions`, calls `AIClient.run()`, forwards stream events
- `ChatModel` (AIDevToolsKitMac) — @Observable model that owns messages, consumes streams via `StreamAccumulator`
- `ChatPanelView` / `ChatMessagesView` — SwiftUI views reading `ChatModel` from environment

### Architecture layer placement

- **SDK layer (`AIOutputSDK`)**: `AIResponseDescriptor`, `AIResponseHandling` protocol, `AIResponseRouter`, new `AIStreamEvent`/`AIContentBlock` cases
- **Feature layer (`ChatFeature`)**: `SendChatMessageUseCase` passes response descriptors through to provider
- **App layer (`AIDevToolsKitMac`)**: `ChatModel` integration (refactored init, round-trip handling), `ViewChatContext`, `ContextualChatPanel`, `PlansChatContext`

### Open question: structured output delivery mechanism

Research shows that getting **both conversational streaming text AND structured output** from a single AI call is not straightforward across all providers:

| Provider | Text + structured in same call? | Mechanism |
|----------|---|---|
| Claude CLI (`--json-schema`) | **Unclear** — text streams during execution, structured output in result event. Need to verify the text is preserved as conversational content, not just intermediate working. | `structured_output` field in result event |
| Codex CLI (`--output-schema`) | **No** — final agent message IS the JSON. No separate conversational text. | Final `agent_message` constrained to schema |
| Anthropic API (tool_use, `tool_choice: auto`) | **Yes** — text blocks + tool_use blocks coexist natively | `tool_use` content blocks alongside `text` blocks |
| Anthropic API (`output_config.format: json_schema`) | **No** — entire response constrained to JSON | `content[0].text` is the JSON |

**Candidate approaches to validate in Phase 1:**

| Approach | Pros | Cons |
|----------|------|------|
| **A: Schema with text field** — Entire response is `{"text": "...", "actions": [...]}` | Works with all providers' native structured output. Schema-enforced. | Loses natural text streaming (full JSON must parse before text can display). Chat feels different. |
| **B: Text convention** — System prompt defines a tag format (e.g., `<app-response>`) parsed from text | Provider-agnostic. Preserves streaming. Simple. | No schema enforcement. AI can produce malformed output. Parsing is fragile. |
| **C: Tool use for Anthropic API, text convention for CLIs** — Best mechanism per provider | Uses native capabilities where available | Two code paths. Inconsistent behavior across providers. |
| **D: Schema with text field + incremental JSON parsing** — Like A, but parse the `text` field from the JSON stream as it arrives | Schema-enforced. Could preserve streaming feel. | Complex incremental JSON parsing. May not work with all providers' streaming formats. |

Phase 1 experiments will determine which approach is feasible.

## Phases

## - [x] Phase 1: Feasibility experiments

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Ran all 4 experiments against Claude CLI and Codex CLI. Key findings: Claude CLI (`--json-schema`) streams conversational text natively before the StructuredOutput tool call — text and structured data coexist. Codex CLI always delivers conversational text via shell command execution and a pure-JSON final `agent_message`; it also enforces very strict schema requirements (no generic `data: object` fields). The text convention approach (XML `<app-response>` tags embedded in streaming text) is the only approach that works consistently across both providers with generic action data and natural streaming. **Recommendation: Approach B — text convention with XML tags.**

**Skills to read**: `swift-app-architecture:swift-architecture`

Before committing to an architecture, run experiments against each provider to validate what actually works. These are small, standalone tests — not production code.

**Experiment 1: Claude CLI — text + structured output coexistence**

Run the Claude CLI with `--json-schema` and a simple schema, observe whether conversational text streams alongside the structured output:

```bash
claude -p "Tell the user a joke, then return structured data" \
  --output-format stream-json \
  --json-schema '{"type":"object","properties":{"text":{"type":"string"},"mood":{"type":"string","enum":["happy","sad"]}},"required":["text","mood"]}'
```

Questions to answer:
- Does the model produce streaming text events (assistant messages with text content) BEFORE/ALONGSIDE the structured output?
- Is that text meaningful conversational content or just the model's working/thinking?
- After completion, does the result event contain BOTH the streaming text AND the `structured_output` field?
- Does this work with `--resume` (session continuation)?

**Experiment 2: Codex CLI — text + structured output coexistence**

Run Codex with `--output-schema` and `--json`:

```bash
codex exec "Tell the user a joke, then return the mood as structured data" \
  --json \
  --output-schema ./test-schema.json
```

Questions to answer:
- Does the JSONL event stream include text agent_messages BEFORE the final structured response?
- Is the final agent_message purely JSON, or does it include conversational text too?
- Can we extract both streaming text and structured data from the event stream?

**Experiment 3: Schema-with-text-field approach**

Test whether a schema that includes a `text` field preserves the conversational feel:

Schema:
```json
{
  "type": "object",
  "required": ["text"],
  "properties": {
    "text": {"type": "string", "description": "Your conversational response to the user"},
    "appResponses": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "data"],
        "properties": {
          "name": {"type": "string"},
          "data": {"type": "object"}
        }
      }
    }
  }
}
```

Test with both Claude CLI and Codex CLI. Questions:
- Does the AI produce natural conversational text in the `text` field?
- Can we incrementally parse and display the `text` field while the JSON streams?
- Does the quality of the conversational response degrade when constrained to JSON?

**Experiment 4: Text convention reliability**

Test the XML tag approach without native structured output. Use a regular chat call with a system prompt instructing the AI to use `<app-response>` tags. Questions:
- How reliably does the AI produce well-formed tags?
- Does it work across Claude CLI, Codex CLI, and Anthropic API?
- Does streaming work naturally (text flows, tags appear inline)?
- Is parsing robust enough (handling edge cases like tags split across chunks)?

**Deliverable**: A short write-up documenting results for each experiment, with a recommendation on which approach to use. This determines the architecture for subsequent phases.

**Files to create:**
- `scripts/experiments/structured-output-chat/` — shell scripts for each experiment
- `docs/proposed/structured-output-experiment-results.md` — findings

## - [x] Phase 2: Structured output SDK primitives

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Added `AIResponseDescriptor`, `AIResponseHandling`, `AIResponseRouter`, and `StructuredOutputParser` to `AIOutputSDK`. Since Phase 1 selected Approach B (text convention with XML `<app-response>` tags), the streaming pipeline types (`AIStreamEvent`, `AIContentBlock`, `StreamAccumulator`) were left unchanged — no `.structuredOutput` case needed. `responseDescriptors` added to `AIClientOptions` with a default of `[]` to keep all existing callers unmodified. `AIResponseRouter` uses `NSLock` for thread safety since it's a reference type needing `@unchecked Sendable`.

**Skills to read**: `swift-app-architecture:swift-architecture`

Based on Phase 1 results, implement the structured output types in `AIOutputSDK`. The specific implementation depends on which approach wins, but the abstractions are similar regardless:

**New types in `AIOutputSDK`:**

`AIResponseDescriptor` — describes a structured output the AI can produce:
```swift
public struct AIResponseDescriptor: Sendable {
    public let name: String
    public let description: String
    public let jsonSchema: String
    public let kind: Kind

    public enum Kind: Sendable {
        case query
        case action
    }
}
```

`AIResponseHandling` — protocol for receiving structured outputs:
```swift
public protocol AIResponseHandling: Sendable {
    var responseDescriptors: [AIResponseDescriptor] { get }
    func handleResponse(name: String, json: Data) async throws -> String?
}
```

`AIResponseRouter` — type-erased router with generic routes:
```swift
public final class AIResponseRouter: AIResponseHandling, @unchecked Sendable {
    public func addRoute<T: Decodable & Sendable>(
        _ descriptor: AIResponseDescriptor,
        type: T.Type,
        handler: @escaping @Sendable (T) async -> String?
    )
}
```

**Streaming pipeline additions** (if native structured output approach wins):

Add `.structuredOutput(name: String, json: String)` to both `AIStreamEvent` and `AIContentBlock`. Update `StreamAccumulator` to handle the new event.

**Structured output extraction** (approach-dependent):

- If **native structured output** wins: Extract from result event `structured_output` field (Claude CLI) or final agent_message (Codex CLI). Emit as `.structuredOutput` stream event.
- If **text convention** wins: Create `StructuredOutputParser` that scans completed message text for `<app-response>` tags.
- If **schema-with-text-field** wins: Decode the JSON response, extract `text` for display and `appResponses` for routing.

**Extend `AIClientOptions`:**

Add `responseDescriptors: [AIResponseDescriptor]` to `AIClientOptions`. How providers use these depends on the chosen approach (compile to JSON schema, inject into system prompt, or define as tools).

**Files to create:**
- `AIOutputSDK/AIResponseDescriptor.swift`
- `AIOutputSDK/AIResponseHandling.swift`
- `AIOutputSDK/AIResponseRouter.swift`
- Approach-dependent: `AIOutputSDK/StructuredOutputParser.swift` or modifications to stream formatters

**Files to modify:**
- `AIOutputSDK/AIStreamEvent.swift` — add `.structuredOutput` case (if applicable)
- `AIOutputSDK/AIContentBlock.swift` — add `.structuredOutput` case (if applicable)
- `AIOutputSDK/StreamAccumulator.swift` — handle new event (if applicable)
- `AIOutputSDK/AIClient.swift` — add `responseDescriptors` to `AIClientOptions`

## - [ ] Phase 3: Structured output through the stack (Feature + App layers)

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`

Wire structured output through `SendChatMessageUseCase` and into `ChatModel`.

**SendChatMessageUseCase changes:**

Add `responseDescriptors: [AIResponseDescriptor]` to `SendChatMessageUseCase.Options`. The use case passes these through to `AIClientOptions`.

**ChatModel refactor for clean integration:**

Currently `ChatModel.init` has 9 parameters, and the 4 use case dependencies + 2 provider strings are always derived from the same `AIClient`. Refactor to a configuration-based init:

```swift
public struct ChatModelConfiguration: Sendable {
    public let client: any AIClient
    public let responseHandler: (any AIResponseHandling)?
    public let settings: ChatSettings
    public let systemPrompt: String?
    public let workingDirectory: String?
}
```

`ChatModel.init(configuration:)` constructs use cases internally from `configuration.client`. Provider names derived from the client.

The `systemPrompt` is a plain `String?` — stable, set once. The AI pulls context via structured output queries.

**Round-trip handling:**

After a message completes, `ChatModel` processes any structured outputs. For each:
1. Call `responseHandler?.handleResponse(name:json:)`
2. If handler returns a `String` (query response), enqueue it as a follow-up message to the AI
3. If handler returns `nil` (action), optionally append a confirmation status message

**Update existing callers:**

Migrate `MarkdownPlannerModel.makeChatModel()` and `ClaudeChainModel.makeChatModel()` to use `ChatModelConfiguration`.

**Files to modify:**
- `ChatFeature/SendChatMessageUseCase.swift` — add `responseDescriptors` to Options
- `AIDevToolsKitMac/Models/ChatModel.swift` — refactor init, add structured output processing
- `AIDevToolsKitMac/Models/MarkdownPlannerModel.swift` — update `makeChatModel`
- `AIDevToolsKitMac/Models/ClaudeChainModel.swift` — update `makeChatModel`

## - [ ] Phase 4: ViewChatContext protocol and ContextualChatPanel

**Skills to read**: `swift-app-architecture:swift-swiftui`

Define the protocol for view contexts and create the reusable chat panel.

**ViewChatContext protocol:**
```swift
@MainActor
protocol ViewChatContext: AnyObject {
    var chatContextIdentifier: String { get }
    var chatSystemPrompt: String { get }
    var chatWorkingDirectory: String { get }
    var responseRouter: AIResponseRouter { get }
}
```

- `chatSystemPrompt` — **stable** description of view capabilities. Not dynamic state.
- `responseRouter` — first-class part of the protocol. Defines available queries and actions.

**ContextualChatPanel view:**
- Accepts a `ViewChatContext`
- Creates `ChatModelConfiguration` with stable system prompt and response handler
- Owns `ChatModel` as `@State`
- Header toolbar: provider picker, new chat button, collapse toggle
- Collapsible via `@AppStorage("contextualChatVisible")`

**SystemPromptBuilder:**
Composes stable system prompt from:
1. Base instructions — app identity, chat context
2. Structured output instructions — available queries and actions (from `responseRouter.responseDescriptors`)
3. CLI instructions — available `ai-dev-tools-kit` commands
4. View context — `context.chatSystemPrompt`

**Files to create:**
- `AIDevToolsKitMac/Views/Chat/ViewChatContext.swift`
- `AIDevToolsKitMac/Views/Chat/ContextualChatPanel.swift`
- `AIDevToolsKitMac/Views/Chat/SystemPromptBuilder.swift`

## - [ ] Phase 5: PlansChatContext and PlansContainer integration

**Skills to read**: `swift-app-architecture:swift-swiftui`

First concrete implementation using the Plans tab.

**PlansChatContext:**
- Conforms to `ViewChatContext`
- Initialized with `MarkdownPlannerModel`, `WorkspaceModel`, `selectedPlanName` binding
- Stable system prompt: "You are in the Plans tab. The user can view, generate, execute, and iterate on implementation plans."
- `chatWorkingDirectory` returns repository path

**Queries (AI pulls data on demand):**

| Query | Input | Returns |
|-------|-------|---------|
| `getViewState` | `{}` | Selected plan, list of plans with completion status, execution state |
| `getPlanDetails` | `{"name": "..."}` | Plan file path, phases, completion, content summary |

**Actions (AI triggers changes):**

| Action | Input | Effect |
|--------|-------|--------|
| `selectPlan` | `{"name": "..."}` | Selects plan in sidebar |
| `reloadPlans` | `{}` | Reloads plan list from disk |
| `navigateToTab` | `{"tab": "..."}` | Switches workspace tab |

**PlansContainer changes:**
- Wrap `HSplitView` in `VSplitView` with `ContextualChatPanel` at bottom
- Create `PlansChatContext` when repository loads
- Chat persists when switching plans (container-level ownership)

**Coexistence with execution/iteration chat:**
- Existing `MarkdownPlannerDetailView` chat stays as-is
- Contextual chat for ad-hoc interaction, execution chat for plan running

**Files to create:**
- `AIDevToolsKitMac/Models/PlansChatContext.swift`

**Files to modify:**
- `AIDevToolsKitMac/Views/PlansContainer.swift`

## - [ ] Phase 6: Deep link file watching for cross-process triggers

**Skills to read**: `swift-app-architecture:swift-architecture`

When the AI modifies data via CLI, the app needs to reload. File-based trigger using existing `FileWatcher` pattern.

**Note**: Verify whether `ActivePlanModel` (which already watches plan files) handles CLI-driven changes before adding infrastructure.

**DeepLinkWatcher:**
- Watches `~/Library/Application Support/AIDevTools/deeplink.txt`
- Reads URL content, routes to appropriate view
- System prompt tells AI to write trigger after CLI modifications

**Files to create:**
- `AIDevToolsKitMac/Navigation/DeepLinkWatcher.swift`
- `AIDevToolsKitMac/Navigation/DeepLinkRouter.swift`

**Files to modify:**
- `AIDevToolsKitMac/Views/WorkspaceView.swift`
- `AIDevToolsKitMac/Views/Chat/SystemPromptBuilder.swift`

## - [ ] Phase 7: Validation

**Skills to read**: `swift-app-architecture:swift-swiftui`

**Build verification:**
- Project builds cleanly
- Existing tests pass (ChatModel refactor, AIStreamEvent additions)
- Unit tests for `AIResponseRouter` (routes correctly, decodes types, returns replies for queries)
- Unit tests for structured output extraction (approach-dependent)

**Manual testing — query round-trip:**
1. Open Plans tab — chat panel appears, collapsible
2. Ask "what plan am I looking at?" — AI queries view → data returns → AI answers
3. Ask about a specific plan — AI queries details → responds with summary

**Manual testing — actions:**
4. Ask "select plan X" — sidebar selection changes
5. Ask "reload plans" — list refreshes
6. Ask "take me to evals" — tab switches

**Manual testing — coexistence and persistence:**
7. Plan execution chat coexists with contextual chat
8. Switch plans — chat persists, AI can query new state
9. Collapse/expand — AppStorage persists state

**Regression checks:**
- Existing execution/iteration chat unchanged
- `makeChatModel()` callers work with refactored init
- Other tabs unaffected
- Existing `runStructured<T>()` callers unaffected
