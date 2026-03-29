> **2026-03-29 Obsolescence Evaluation:** Obsolete. Provider-agnostic chat unification was already completed in "2026-03-25-a-unify-ai-interface-for-chat.md" and "2026-03-27-a-remove-provider-references-from-chat-ui.md". The project now has a unified ChatModel and AIClient protocol that works with any provider, eliminating separate Anthropic and Claude Code chat implementations.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | Architecture guidance for Model-View + Use Cases patterns, layer responsibilities |

## Background

There are currently two separate chat implementations: one for the Anthropic HTTP API (`ChatView` + `ChatViewModel`) and one for the Claude Code CLI (`ClaudeCodeChatView` + `ClaudeCodeChatManager`). They have separate views, models, and services. This should be unified into a single chat abstraction with provider adapters, and a single chat view that works with any provider. This also opens the door to supporting Codex or other providers.

---

## Phases

## - [ ] Phase 1: Define Chat Protocol

**Skills to read**: `swift-architecture`

Design a chat protocol/abstraction that captures the common interface:

- Send a message (with optional image attachments)
- Receive streaming responses
- Session management (create, resume, list history)
- Cancel in-progress requests
- Provider-specific settings

Both existing implementations should be able to conform to this protocol.

## - [ ] Phase 2: Create Provider Adapters

Implement adapters that conform the existing services to the new protocol:

- `AnthropicAPIChatAdapter` — wraps the existing HTTP API chat logic
- `ClaudeCodeCLIChatAdapter` — wraps the existing Claude Code CLI chat logic
- Potentially a `CodexChatAdapter` stub for future use

## - [ ] Phase 3: Build Unified Chat View

Replace the two chat views with a single `ChatView` that works with the chat protocol. The mode picker (API/CLI) becomes a provider selector. Consolidate shared UI (message list, input bar, streaming indicators) and keep provider-specific UI (e.g., Claude Code settings) behind conditional checks.

## - [ ] Phase 4: Clean Up

Remove the old separate chat views and models. Update `WorkspaceView` to use the unified chat view. Remove any dead code from the consolidation.

## - [ ] Phase 5: Validation

- Test API chat: send messages, verify streaming, check conversation persistence
- Test Claude Code chat: send messages, verify session history, test image attachments
- Test switching between providers mid-session
- Verify chat settings and session picker still work for Claude Code mode
