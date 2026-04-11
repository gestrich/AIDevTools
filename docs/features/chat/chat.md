# AI Chat

AI Chat lets you have conversations with AI providers directly from the Mac app, with streaming responses, persistent session history, and image attachment support.

## What It Does

- **Streaming responses** — output appears as it arrives, word by word
- **Session history** — conversations are saved and can be resumed across app launches
- **Image attachments** — attach screenshots or images to provide visual context
- **Contextual panels** — chat panels are scoped to a specific repository or workspace context

## Provider Selection

Choose from three providers in the chat panel header:

| Provider | Description |
|----------|-------------|
| **Anthropic API** | Direct API access via an Anthropic API key |
| **Claude Code CLI** | Routes through the `claude` CLI, using your existing Claude Code session |
| **Codex** | Routes through the OpenAI Codex CLI |

Switch providers at any time; the session history persists independently of the selected provider.

## MCP Integration

The chat panel connects to the app's built-in **MCP server** (`ai-dev-tools-kit mcp`) when a valid binary is available. MCP tools let the AI interact with the live Mac app — querying UI state, selecting plans, navigating tabs, and reloading data — via a Unix domain socket IPC channel.

### Configuring MCP

1. Open **Settings → General**
2. Set the **AIDevTools Repo Path** to the root of your local AIDevTools checkout (e.g. `~/Developer/personal/AIDevTools`)
3. The app derives the binary path automatically: `<repoPath>/AIDevToolsKit/.build/debug/ai-dev-tools-kit`
4. On the next app launch (or immediately after saving the setting), the MCP config is written to `~/Library/Application Support/AIDevTools/mcp-config.json`

No CLI run is required — the Mac app writes the config itself.

### Status Banners

The chat panel shows an inline banner when MCP is not available:

| Status | Banner |
|--------|--------|
| Repo path not set | "MCP unavailable — set AIDevTools Repo Path in Settings" |
| Binary not found at configured path | "MCP binary not found. Build the app in Xcode or run `swift build --target AIDevToolsKitCLI` in the repo." |
| No banner | MCP is ready |

## Staleness Indicator

When the MCP binary was last built more than 3 days ago, an info icon appears in the chat panel header. Tap it to see how many days ago the binary was built.

To refresh it, run:

```sh
cd <repoPath>/AIDevToolsKit
swift build --target AIDevToolsKitCLI
```

After rebuilding, reopen the chat panel — the indicator will clear automatically once the binary's modification date is current.
