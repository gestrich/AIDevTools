# Projects Guide

This guide explains how to create and configure ClaudeChain projects, including writing task specs and managing tasks safely. Each project defines a chain of tasks that ClaudeChain works through one PR at a time.

## Project Structure

ClaudeChain discovers projects by looking for `spec.md` files in the `claude-chain/` directory:

```
your-repo/
├── claude-chain/
│   ├── auth-refactor/
│   │   ├── spec.md              # Required: task list and instructions
│   │   ├── configuration.yml    # Optional: reviewers and settings
│   │   ├── pr-template.md       # Optional: custom PR description
│   │   ├── pre-action.sh        # Optional: runs before Claude Code
│   │   └── post-action.sh       # Optional: runs after Claude Code
│   ├── api-cleanup/
│   │   └── spec.md
│   └── docs-update/
│       ├── spec.md
│       └── configuration.yml
└── ...
```

**Key points:**
- Each subdirectory under `claude-chain/` is a project
- The directory name becomes the project name (e.g., `auth-refactor`)
- Only `spec.md` is required; other files are optional
- You can have multiple projects running in parallel

## spec.md Format

The `spec.md` file combines instructions for Claude and a task checklist.

### Basic Structure

```markdown
# Project Title

Describe what you want to refactor and how to do it.

Include:
- Patterns to follow
- Code examples
- Edge cases to handle
- Files or directories to focus on

## Tasks

- [ ] First task to complete

- [ ] Second task to complete

- [ ] Third task to complete
```

### Task Syntax

Tasks use Markdown checkbox syntax:

| Syntax | Meaning |
|--------|---------|
| `- [ ] Task description` | Unchecked (pending) |
| `- [x] Task description` | Checked (complete) |

**Rules:**
- Tasks can appear anywhere in the file (not just at the end)
- Only lines matching `- [ ]` or `- [x]` are treated as tasks
- The description text is used to generate the task hash
- When a PR merges, ClaudeChain automatically marks the task `- [x]`
- Add a blank line between each task to prevent merge conflicts when multiple PRs merge concurrently (see [Concurrency](./setup.md#concurrency))

**Flexible organization:** Tasks can be organized however you like—grouped under headings, separated by blank lines, or interspersed with other text. Just ensure each task starts with `- [ ]` so ClaudeChain can find it.

### Writing Good Tasks

**Be specific:**
```markdown
# ❌ Too vague
- [ ] Fix the authentication

# ✅ Specific and actionable
- [ ] Add rate limiting to /api/auth/login endpoint (max 5 attempts per minute)
```

**One change per task:**
```markdown
# ❌ Too broad
- [ ] Refactor authentication and add logging

# ✅ Focused
- [ ] Extract authentication logic into AuthService class
- [ ] Add structured logging to authentication flow
```

**Include context in the spec, not the task:**
```markdown
# Auth Refactoring

We're moving from session-based to JWT authentication.
Follow the patterns in `src/auth/jwt-example.ts`.

## Tasks

- [ ] Add JWT token generation to login endpoint

- [ ] Add JWT verification middleware

- [ ] Update protected routes to use new middleware
```

### Adding Details to Tasks

You can add details below a task without affecting its hash:

```markdown
- [ ] Add user authentication

  Implementation notes:
  - Use OAuth 2.0 with Google and GitHub providers
  - Store tokens in httpOnly cookies
  - Add CSRF protection

  Reference: See `docs/auth-spec.md` for full requirements
```

Only the checkbox line (`- [ ] Add user authentication`) is hashed. The indented content below can be changed freely without creating orphaned PRs.

## configuration.yml Format

The configuration file is **optional**. Without it, ClaudeChain uses these defaults:
- PRs created without assignees or reviewers
- Maximum 1 open PR per project

### Full Schema

```yaml
# Optional: GitHub usernames to assign PRs to (list)
assignees:
  - alice
  - bob

# Optional: GitHub usernames to request reviews from (list)
reviewers:
  - carol

# Optional: Override base branch for this project
baseBranch: develop

# Optional: Override allowed tools for this project
allowedTools: Read,Write,Edit,Bash

# Optional: Days before a PR is considered stale (for statistics)
stalePRDays: 7

# Optional: Additional labels to apply to PRs (comma-separated)
labels: team-backend,needs-review

# Optional: Maximum concurrent open PRs per project (default: 1)
maxOpenPRs: 3
```

### Assignees vs Reviewers

**Assignees** are the people responsible for the PR. They appear in the "Assignees" section on GitHub and are expected to own the code changes and merge it.

**Reviewers** receive a review request notification and are expected to provide feedback, but are not assigned ownership.

```yaml
# Alice and Bob own the PR; Carol reviews it
assignees:
  - alice
  - bob
reviewers:
  - carol
```

### Tool Permissions

Use `allowedTools` to customize which tools Claude can use for a specific project. This overrides the workflow-level `claude_allowed_tools` input.

**When to expand permissions:**

If your tasks require running tests, builds, or other shell commands:

```yaml
# Full Bash access for this project
allowedTools: Read,Write,Edit,Bash
assignees:
  - alice
```

**Granular Bash permissions:**

```yaml
# Allow only specific commands
allowedTools: Read,Write,Edit,Bash(git add:*),Bash(git commit:*),Bash(npm test:*),Bash(npm run build:*)
```

**Examples by project type:**

| Project Type | Recommended `allowedTools` |
|--------------|----------------------------|
| Documentation updates | `Read,Write,Edit,Bash(git add:*),Bash(git commit:*)` (default) |
| Code refactoring with tests | `Read,Write,Edit,Bash` |
| Build-dependent changes | `Read,Write,Edit,Bash(git add:*),Bash(git commit:*),Bash(npm run build:*)` |
| Security-sensitive projects | `Read,Edit,Bash(git add:*),Bash(git commit:*)` (no `Write`) |

**Configuration hierarchy:**
1. Workflow-level `claude_allowed_tools` input (default for all projects)
2. Project-level `allowedTools` in `configuration.yml` (overrides workflow default)

## Pre/Post Action Scripts

ClaudeChain supports optional **pre-action** and **post-action** scripts that run before and after Claude Code execution.

| Script | When It Runs | Failure Behavior |
|--------|--------------|------------------|
| `pre-action.sh` | After checkout, before Claude Code | Aborts job, no Claude execution |
| `post-action.sh` | After Claude Code, before PR creation | Aborts job, no PR created |

**Key points:**
- Scripts are optional—if a script doesn't exist, execution continues normally
- Scripts must be executable bash scripts
- Scripts run from the repository's working directory
- If a script exits with non-zero status, the entire job fails

**Pre-action examples:**
```bash
#!/bin/bash
# pre-action.sh - Validate environment before Claude works

# Run code generation that Claude depends on
./scripts/generate-api-types.sh

# Ensure dependencies are installed
npm install
```

**Post-action examples:**
```bash
#!/bin/bash
# post-action.sh - Validate Claude's changes

# Run linting on changed files
npm run lint

# Run tests to verify changes work
npm test
```

When a script fails, the job stops, no PR is created, and (if configured) a Slack failure notification is sent.

## Modifying Tasks

ClaudeChain uses hash-based task identification, making most modifications safe.

### Safe Operations

```markdown
# ✅ Reordering tasks — hash stays the same
# ✅ Inserting new tasks — they get new hashes
# ✅ Deleting completed tasks — no open PRs reference them
```

### Operations That Create Orphaned PRs

```markdown
# ⚠️ Changing task descriptions while a PR is open
# Before (PR #123 open for this task)
- [ ] Add user authentication

# After (creates orphaned PR!)
- [ ] Add OAuth authentication
```

**Resolving orphaned PRs:**
1. Review the orphaned PR
2. Close it
3. The next workflow run creates a new PR for the updated task

| Scenario | Recommendation |
|----------|----------------|
| Reordering tasks | ✅ Do it anytime |
| Adding new tasks | ✅ Do it anytime |
| Removing completed tasks | ✅ Do it anytime |
| Changing task text | ⏳ Wait until PR is merged |
| Removing uncompleted tasks | ⚠️ Close the orphaned PR after |

## PR Templates

Customize PR descriptions with a template file.

Create `claude-chain/{project}/pr-template.md`:

```markdown
## Task

{{TASK_DESCRIPTION}}

## Review Checklist

- [ ] Code follows project conventions
- [ ] Tests pass
- [ ] No unintended changes
- [ ] Documentation updated if needed

---
*Auto-generated by ClaudeChain*
```

`{{TASK_DESCRIPTION}}` is replaced with the task text from spec.md. If no template exists, ClaudeChain uses a simple default with just the task description.

## Examples

### Minimal Project

```
claude-chain/quick-fix/
└── spec.md
```

```markdown
# Quick Fix

Fix the typos in error messages.

- [ ] Fix typo in login error message

- [ ] Fix typo in signup error message
```

### Full Project

```
claude-chain/auth-migration/
├── spec.md
├── configuration.yml
└── pr-template.md
```

**spec.md:**
```markdown
# Auth Migration

Migrate from session-based to JWT authentication.
See `docs/auth-rfc.md` for the full design.

## Tasks

- [ ] Add JWT utility functions to `src/auth/jwt.ts`

- [ ] Update login endpoint to return JWT

- [ ] Add JWT verification middleware

- [ ] Update protected routes to use new middleware

- [ ] Remove session-related code

- [ ] Update tests
```

**configuration.yml:**
```yaml
assignees:
  - alice
reviewers:
  - bob
```
