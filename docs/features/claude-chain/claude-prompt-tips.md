# Claude Prompt Tips

Best practices for writing effective prompts and configuring Claude Code for reliable automated workflows.

## Build Tooling Before Claude Runs

If your task requires custom tooling (scripts, binaries, dependencies), build them **before** Claude Code runs rather than asking Claude to build them.

### Why This Matters

When Claude encounters a missing tool or build failure, it will attempt workarounds—trying alternative approaches, modifying code to skip the failing step, or making assumptions about what the tool would have done. This wastes tokens and often produces incorrect results. **Fail fast instead.**

### Solution: Pre-build in Your Workflow

**Option 1: GitHub Workflow Step**

Add a build step before the ClaudeChain action:

```yaml
- name: Build custom tooling
  run: |
    cd scripts
    swift build -c release
    cp .build/release/my-tool /usr/local/bin/

- name: Run ClaudeChain
  uses: gestrich/claude-chain@main
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

**Option 2: Pre-action Script**

Create a `pre-action.sh` script in your project directory:

```bash
#!/bin/bash
# claude-chain/my-project/pre-action.sh
set -e

echo "Building required tooling..."
cd "$GITHUB_WORKSPACE/scripts"
swift build -c release

echo "Installing to PATH..."
cp .build/release/my-tool /usr/local/bin/
```

See [Pre/Post Action Scripts](./projects.md#prepost-action-scripts) for details.

## Enforce Critical Tool Success

When your prompt includes tools that **must succeed** for the task to be valid, use explicit language to prevent Claude from working around failures.

### The Problem

Claude is helpful and will try to make progress even when things fail. If a critical validation tool fails, Claude might skip the validation step, assume it would have passed, or continue with subsequent steps anyway.

### Solution: Use MUST Language

In your spec.md, be explicit about critical requirements:

```markdown
## Critical Requirements

The following tools are CRITICAL and MUST succeed:

1. **my-validation-script.sh** - MUST return exit code 0
2. **xcodegen** - MUST complete without errors

### MANDATORY Rules

- You MUST check the exit code of every critical tool
- If a critical tool returns a non-zero exit code, you MUST STOP IMMEDIATELY
- You MUST NOT continue to subsequent steps after a critical failure
- You MUST NOT implement workarounds to avoid running the tools
- You MUST report the error details and STOP

### On Failure

If a critical tool fails:
1. Read the full log/output to understand the error
2. Include the error details in your response
3. STOP - do not proceed with any further steps
```

### Include Error Details in Output

Ask Claude to log errors explicitly:

```markdown
If any step fails, you MUST include:
- The exact command that failed
- The exit code
- The full error output
```

This ensures error details appear in the workflow logs and Slack notifications (if configured).

## Using Custom Commands

Claude Code's slash commands (like `/commit`) don't work in automated GitHub Actions environments. Reference command files directly instead.

### The Problem

If your prompt says:
```
Run /my-custom-command to validate the changes
```

Claude won't be able to execute this—slash commands require the interactive Claude Code CLI.

### Solution: Reference the File Path

```markdown
Before completing the task, follow the instructions in
`.claude/commands/my-custom-command.md` to validate your changes.
```

Or include the steps directly in your spec:

```markdown
## Validation Steps

After making changes:

1. Run the linter: `npm run lint`
2. Run tests: `npm test`
3. Verify types: `npm run typecheck`
```

Claude will read the file at the specified path and follow its instructions.

## Working Directory Restrictions

Claude Code has security restrictions that prevent using `cat` (and similar commands) to read files outside the working directory.

### The Problem

If your workflow writes files to `/tmp` or another directory outside the project:

```bash
# This will fail in Claude Code
echo "results" > /tmp/output.txt
cat /tmp/output.txt  # ❌ Blocked - outside working directory
```

### Solution: Use the Working Directory

Write temporary files within the project directory instead:

```bash
mkdir -p .tmp
echo "results" > .tmp/output.txt
cat .tmp/output.txt  # ✅ Works
```

In your prompts:

```markdown
When writing temporary files, always write them within the current
working directory (e.g., `.tmp/` folder). Do not use `/tmp` or other
system directories.
```

## Quick Reference

| Tip | Do | Don't |
|-----|-----|-------|
| Tooling | Build before Claude runs | Ask Claude to build tools |
| Critical tools | Use MUST/STOP language | Hope Claude checks exit codes |
| Error details | Request explicit logging | Assume errors will be captured |
| Custom commands | Reference file path | Use slash command syntax |
| Temp files | Write to working directory | Write to `/tmp` or outside dirs |
