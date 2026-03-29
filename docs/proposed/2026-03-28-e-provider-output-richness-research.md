> **2026-03-29 Obsolescence Evaluation:** Plan reviewed, still relevant. This research document analyzes provider output richness gaps and provides concrete improvement recommendations. While not in standard plan format, it identifies actionable improvements like tracking tool_use_id → name mapping, handling thinking deltas for Anthropic API, and supporting array tool results.

# Provider Output Richness Research

This document captures the mapping from each provider's raw stream events to `AIContentBlock` cases,
and identifies gaps between raw data and what is currently surfaced.

## Claude CLI (`ClaudeProvider` / `ClaudeStreamFormatter`)

### Event types emitted

The Claude CLI with `--output-format stream-json --verbose` emits JSONL with these `type` values:

| Type | Handled? | Notes |
|------|----------|-------|
| `system` | Ignored | Init event — session_id, tools list, model name |
| `assistant` | Yes | Main content events |
| `user` | Partially | Only `tool_result` blocks |
| `result` | Yes | Metrics summary |

### `assistant` event content block types

Each `assistant` event has a `message.content` array. In practice each event contains one block type:

```jsonl
// Thinking block
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"...","signature":"..."}],...}}

// Tool use block
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_...","name":"Bash","input":{"command":"echo $((2+2))","description":"Calculate 2+2"},"caller":{"type":"direct"}}],...}}

// Text block
{"type":"assistant","message":{"content":[{"type":"text","text":"4"}],...}}
```

Mapping to `AIStreamEvent`:

| Block type | `AIStreamEvent` emitted | What's captured | What's dropped |
|-----------|------------------------|-----------------|----------------|
| `thinking` | `.thinking(block.thinking)` | Full thinking text | `signature` field (cryptographic, not display-relevant) |
| `text` | `.textDelta(block.text)` | Full text | — |
| `tool_use` | `.toolUse(name:, detail:)` | Name + key input field | `id` (needed for correlating tool results), `caller`, full input object |
| anything else | (ignored) | — | — |

### `user` event — tool results

```jsonl
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_0135D91...","type":"tool_result","content":"4","is_error":false}]},"tool_use_result":{"stdout":"4","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false}}
```

Mapping to `AIStreamEvent`:

| Field | `AIStreamEvent` emitted | What's captured | What's dropped |
|-------|------------------------|-----------------|----------------|
| `content` (string) | `.toolResult(name: "", summary: content.prefix(200), isError:)` | First 200 chars | Content > 200 chars |
| `content` (array) | (dropped) | — | Entire result |
| `tool_use_id` | (ignored) | — | Not correlated back to tool name |
| `tool_use_result.stderr` | (ignored) | — | stderr output |
| `tool_use_result.interrupted` | (ignored) | — | Interrupt flag |

### `result` event

```jsonl
{"type":"result","subtype":"success","is_error":false,"duration_ms":4723,"num_turns":2,"total_cost_usd":0.0514206,"result":"4","stop_reason":"end_turn",...}
```

Mapping: `.metrics(duration: 4.723, cost: 0.0514206, turns: 2)` ✓

Fields `result` (final text), `stop_reason`, and detailed `usage`/`modelUsage` breakdowns are not captured but are not needed for display.

### Identified gaps for Claude CLI

1. **Tool result name is always `""`**. The `user` event has only `tool_use_id` (not the name). To fill the name field, the formatter would need to track a `[String: String]` map of `tool_use_id → tool_name` across events within a stream. This is a stateful operation the current stateless `ClaudeStreamFormatter` does not perform.

2. **Array tool results are silently dropped**. `ToolResultContent.summary` returns `nil` for the `.array` case. Tools that return structured arrays (e.g., `Glob`, `Grep` with multiple results) produce no `toolResult` event at all.

3. **Tool result content is truncated at 200 characters**. Long Bash outputs, file reads, and grep results are cut off in the display.

4. **`tool_use_result.stderr` and `tool_use_result.interrupted` are not decoded**. These exist at the top level of the `user` event in a `tool_use_result` object outside `message`, making it invisible to the current `ClaudeUserEvent` model.

---

## Anthropic API (`AnthropicProvider`)

### Event types emitted (`MessageStreamResponse.StreamEvent`)

| SSE event type | `chunk.streamEvent` | Handled? |
|----------------|-------------------|----------|
| `message_start` | `.messageStart` | No |
| `content_block_start` | `.contentBlockStart` | Partially (tool_use name only) |
| `content_block_delta` | `.contentBlockDelta` | Partially (text only) |
| `content_block_stop` | `.contentBlockStop` | No |
| `message_delta` | `.messageDelta` | No |
| `message_stop` | `.messageStop` | No |

### `content_block_start` — `chunk.contentBlock`

| `contentBlock.type` | Currently emitted | What's dropped |
|--------------------|-------------------|----------------|
| `text` | Nothing | — (text comes in deltas) |
| `tool_use` | `.toolUse(name: name, detail: "")` | Input (arrives as delta partial JSON) |
| `thinking` | Nothing | Entire thinking block |
| `redacted_thinking` | Nothing | — (expected) |

### `content_block_delta` — `chunk.delta`

| `delta.type` | Currently emitted | What's dropped |
|-------------|-------------------|----------------|
| `text_delta` (`delta.text`) | `.textDelta(text)` ✓ | — |
| `thinking_delta` (`delta.thinking`) | Nothing | Full thinking content |
| `input_json_delta` (`delta.partialJson`) | Nothing | Tool input (partial JSON accumulation) |
| `signature_delta` (`delta.signature`) | Nothing | — (cryptographic, not display-relevant) |
| `citations_delta` (`delta.citation`) | Nothing | Citation data |

### `message_delta` — stop reason / usage

| Field | Currently emitted | What's dropped |
|-------|-------------------|----------------|
| `delta.stopReason` | Nothing | End of response reason |
| `usage` | Nothing | No `.metrics` event ever emitted |

### Identified gaps for AnthropicProvider

1. **No thinking events**. `delta.type == "thinking_delta"` carries the thinking text, but is not handled. Additionally, thinking is disabled at the API call site (`thinking: nil` in `MessageParameter`), so it would need to be enabled first.

2. **Tool input detail is always `""`**. Input arrives as `partialJson` deltas across multiple `content_block_delta` events and must be accumulated into a `String` before parsing as JSON. The `content_block_stop` event signals when accumulation is complete. This requires statefulness across chunks in the streaming loop.

3. **No metrics events**. The `message_delta` event carries `usage` (input/output tokens), but no `.metrics` event is emitted. There is no equivalent to the Claude CLI `result` event — duration and cost data are not available from the Anthropic streaming API without an external timer.

4. **No tool results**. This is structural: the Anthropic API does not stream tool results back to the caller. Instead, the caller provides tool results in the next request turn. `AnthropicProvider` currently passes `tools: nil`, disabling tool calling entirely.

---

## Comparison: What each provider can surface

| `AIContentBlock` case | Claude CLI | Anthropic API |
|-----------------------|-----------|---------------|
| `.text(String)` | ✓ Full text | ✓ Full text (assembled from deltas) |
| `.thinking(String)` | ✓ Full thinking | ✗ Not captured (disabled at call site) |
| `.toolUse(name, detail)` | ✓ Name + partial input | ✓ Name only (detail always `""`) |
| `.toolResult(name, summary, isError)` | ✓ Partial (name `""`, 200-char limit) | ✗ Not applicable (no tool calling) |
| `.metrics(duration, cost, turns)` | ✓ All three | ✗ None (no equivalent event) |

---

## Recommended improvements (for Phase 1 refinement)

### For `ClaudeStreamFormatter`

1. **Track tool_use_id → name** across events within a single `formatStructured` call. The formatter would need a mutable dictionary, making it no longer truly stateless per call. Alternatively, add a `toolUseName` parameter to `.toolResult` that callers can optionally fill in, defaulting to `""`.

2. **Handle array tool results** by joining the array items into a summary string instead of returning `nil`.

3. **Increase or remove the 200-char truncation** in `ToolResultContent.summary`. A separate `truncated: Bool` flag could let the UI indicate that content was cut.

4. **Add `tool_use_result` to `ClaudeUserEvent`** to capture `stderr` and `interrupted`.

### For `AnthropicProvider`

1. **Enable thinking** by setting `thinking: .enabled(budgetTokens: N)` in `MessageParameter`.

2. **Handle `thinking_delta`** by checking `chunk.delta?.type == "thinking_delta"` and emitting `.thinking(chunk.delta?.thinking ?? "")`. Thinking content accumulates across deltas within a block.

3. **Accumulate tool input from `input_json_delta`** by keeping a `[Int: String]` map of block index → partial JSON string across the streaming loop, then emitting `.toolUse` with the assembled detail on `content_block_stop`.

4. **Emit metrics** by recording start time before the stream loop and emitting `.metrics(duration: elapsed, cost: nil, turns: nil)` at `message_stop`. Token counts from `message_delta.usage` can populate a cost estimate if a per-token price is known.
