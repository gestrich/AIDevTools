---
name: logging
description: Logging infrastructure for this project — reading logs, filtering output, debugging via logs, and adding logging to new features. Use this skill whenever reading logs, investigating errors via logs, adding log statements for debugging CLI or Mac app behavior, or ensuring new features are properly covered by logs. Trigger on any mention of logs, log files, Logger calls, log levels, or "what happened during the last run", and when implementing new functionality.
---

# Logging

## Log File Location

The app writes structured JSON-line logs to:
```
~/Library/Logs/AIDevTools/aidevtools.log
```

Both the Mac app and CLI write to this same file.

## Enabling Verbose Logging

Pass `--log-level` to the root CLI command to control what gets written to the log file. The default is `info`.

```bash
swift run ai-dev-tools-kit --log-level trace <subcommand>
```

Valid levels: `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`. The flag applies to all subcommands.

## Reading Logs with the CLI

Run from `AIDevToolsKit/`:

```bash
# All log entries
swift run ai-dev-tools-kit logs

# Filter by date range
swift run ai-dev-tools-kit logs --from 2026-03-14 --to 2026-03-14

# Filter by level (trace, debug, info, notice, warning, error, critical)
swift run ai-dev-tools-kit logs --level error

# JSON output for programmatic parsing
swift run ai-dev-tools-kit logs --json
```

## Log Levels

- **trace** — Fine-grained diagnostics for hard-to-reproduce bugs. Assume it won't run in production; no restrictions.
- **debug** — Selective diagnostics that provide value without overwhelming production. Some operators may enable in production.
- **info / notice** — Avoid for normal operations. Don't log things like "accepted a request" — this floods logs at volume.
- **warning** — Use sparingly. Prefer throwing/returning errors instead. Acceptable for one-time startup messages or background processes with no other communication channel. Don't repeat the same warning per-request.
- **error** — Prefer surfacing errors through the API rather than logging them. Don't log expected failures (e.g., a connection timeout for an HTTP client). Be aware that errors may trigger alerting.
- **critical** — Reserve for situations where the component will stop functioning entirely after this point.

## Logger Naming Convention

Each class or struct that needs logging declares its own logger using the class name as the label — no app name prefix:

```swift
private let logger = Logger(label: "PRModel")
private static let logger = Logger(label: "ClaudeProvider")
```

The label identifies the creator (the class). The `source` field in each log entry is automatically populated by swift-log with the Swift module name (`AIDevToolsKitMac`, `AIDevToolsKitCLI`, etc.), so adding an app prefix to the label is redundant.

## Adding Log Statements for Debugging

When investigating issues, add temporary `Logger` calls at relevant code points to capture runtime state. Declare a logger on the type using the class/struct name as the label (see convention above).

**For CLI debugging:** Add log statements, run the CLI command with `--log-level trace`, then read the log file.

**For Mac app debugging:** Since the Mac app runs separately, tell Bill you are adding log statements to help troubleshoot, explain what information the logs will capture, then ask Bill to run the app and trigger the relevant action. After the run completes, read the log file.

## Running Long CLI Commands from AI Agents

When running CLI commands (e.g., `markdown-planner execute`) from an AI agent like OpenClaw, the agent's process manager may kill child processes unexpectedly (SIGKILL). To avoid this, use `nohup` to detach the process from the agent's process tree:

```bash
nohup ai-dev-tools-kit --log-level trace markdown-planner execute \
  --plan docs/proposed/my-plan.md > /tmp/plan-execute.log 2>&1 &
```

Then monitor with:
```bash
ps -p <PID>                    # Check if still running
tail -f /tmp/plan-execute.log  # Watch stdout progress
```

And check `~/Library/Logs/AIDevTools/aidevtools.log` for structured trace/error logs.

**Why `nohup`?** Agent process managers (e.g., OpenClaw's `exec` tool) track child processes and may reap them during session management. `nohup` ensures the CLI runs independently.
