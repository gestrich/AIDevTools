## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | Architecture guidance for Model-View + Use Cases patterns, layer responsibilities |

## Background

There are currently two separate chat implementations: one for the Anthropic HTTP API (`ChatView` + `ChatViewModel`) and one for the Claude Code CLI (`ClaudeCodeChatView` + `ClaudeCodeChatManager`). They have separate views, models, and services. This should be unified into a single chat abstraction with provider adapters, and a single chat view that works with any provider. This also opens the door to supporting Codex or other providers.

---

## Phases

## - [x] Phase 1: Define Chat Protocol

**Skills used**: `swift-architecture`
**Principles applied**: Protocol placed in ChatFeature (Features layer) following 4-layer architecture. Reuses existing AIOutputSDK types (AIStreamEvent, ImageAttachment, ChatSession, ChatSessionMessage) for streaming and session data. Created focused ChatProviderOptions/ChatProviderResult types rather than reusing general-purpose AIClient types. Default protocol extensions for optional capabilities (session history, cancellation) so providers only implement what they support.

**Skills to read**: `swift-architecture`

Design a chat protocol/abstraction that captures the common interface:

- Send a message (with optional image attachments)
- Receive streaming responses
- Session management (create, resume, list history)
- Cancel in-progress requests
- Provider-specific settings

Both existing implementations should be able to conform to this protocol.

## - [x] Phase 2: Create Provider Adapters

**Skills used**: `swift-architecture`
**Principles applied**: Created a single generic `AIClientChatAdapter` in ChatFeature rather than three separate adapter types, since all providers (AnthropicProvider, ClaudeProvider, CodexProvider) already conform to `AIClient & SessionListable`. This avoids code duplication and respects the 4-layer architecture — the adapter lives in the Features layer and depends only on `AIOutputSDK` protocols, not concrete SDK types. Image attachment handling (base64 → temp files) is included in the adapter. Also fixed pre-existing `runStructured` signature mismatches in AnthropicProvider and CodexProvider after Phase 1 protocol changes.

Implement adapters that conform the existing services to the new protocol:

- `AnthropicAPIChatAdapter` — wraps the existing HTTP API chat logic
- `ClaudeCodeCLIChatAdapter` — wraps the existing Claude Code CLI chat logic
- Potentially a `CodexChatAdapter` stub for future use

## - [x] Phase 3: Build Unified Chat View

**Skills used**: `swift-architecture`
**Principles applied**: Refactored ChatModel to depend on ChatProvider protocol instead of AIClient + SendChatMessageUseCase, completing the protocol adoption from Phases 1-2. Added getSessionDetails to ChatProvider with default nil implementation. Created AIClientChatAdapter.make(from:) factory for easy provider creation. Added chat as a workspace item in WorkspaceView with a provider selector Picker, session history button (conditional on supportsSessionHistory), and settings/new conversation controls. Updated CLI ChatCommand to also use ChatProvider. No layer violations — factory lives in ChatFeature (Features layer), not ProviderRegistryService (Services layer).

Replace the two chat views with a single `ChatView` that works with the chat protocol. The mode picker (API/CLI) becomes a provider selector. Consolidate shared UI (message list, input bar, streaming indicators) and keep provider-specific UI (e.g., Claude Code settings) behind conditional checks.

## - [x] Phase 4: Clean Up

**Skills used**: none
**Principles applied**: Removed dead ChatService module (ChatSessionManager, Conversation, ChatMessageRecord, ChatStreamEvent) and its tests — no code in the app imported it after the Phase 1-3 unification. Updated Package.swift to remove the library, target, and test target. Updated ARCHITECTURE.md and README.md to reflect the current unified ChatFeature and remove references to deleted AnthropicChatFeature, ClaudeCodeChatFeature, AnthropicChatService, and ClaudeCodeChatService.

Remove the old separate chat views and models. Update `WorkspaceView` to use the unified chat view. Remove any dead code from the consolidation.

## - [x] Phase 5: Validation

**Skills used**: none
**Principles applied**: Added comprehensive validation tests for the unified chat system. Created AIClientChatAdapterTests covering adapter properties, factory detection, message forwarding, option mapping, stream event forwarding, image attachment prompt augmentation, and session delegation (list/load/details) for both SessionListable and plain AIClient. Created ChatModelTests as integration-style tests validating full send/receive flow, streaming event delivery, session persistence across messages, image attachment forwarding, session history listing/loading, provider switching with distinct properties and results, ChatSettings defaults/mutability, and end-to-end conversation flows with both session-aware and plain providers. Added AIOutputSDK as explicit test dependency.

- Test API chat: send messages, verify streaming, check conversation persistence
- Test Claude Code chat: send messages, verify session history, test image attachments
- Test switching between providers mid-session
- Verify chat settings and session picker still work for Claude Code mode
