# PRRadar

PRRadar reviews pull requests against configurable markdown rule files. It fetches the PR diff, evaluates changed code against matching rules, and posts inline review comments on GitHub.

## How it Works

The review pipeline runs in four sequential phases:

1. **sync** — Fetches PR metadata and diff from GitHub
2. **prepare** — Uses AI to generate focus areas, loads matching rules, and creates evaluation tasks
3. **analyze** — Evaluates each task against its rule via regex pattern matching or AI
4. **comment** — Posts inline review comments on the PR for any violations found

## Rule Files

Rules are markdown files with YAML frontmatter in a `rules/` directory. The frontmatter controls when a rule applies:

```markdown
---
description: Division operations should use error handling
category: safety
focus_type: file
applies_to:
  file_patterns:
    - "*.swift"
grep:
  any:
    - "divide"
    - "/ "
---

# Guard Against Unsafe Division

Explanation of the rule and examples...
```

The `grep` section enables regex-based matching so rules can be evaluated without AI calls. See `docs/rule-examples/` for more examples.

## Analysis Modes

The `analyze` command's `--mode` flag controls how rules are evaluated:

| Mode | Description | Cost |
|------|-------------|------|
| `regex` | Pattern matching only (uses `grep` frontmatter) | Free (no AI calls) |
| `ai` | AI evaluation only (uses Claude Sonnet) | API costs per evaluation |
| `all` | Both regex and AI evaluation | API costs per AI evaluation |

## Local Usage

Both the Mac app and the CLI share the same pipeline. From the CLI, run from `AIDevToolsKit/`:

```bash
# Fetch diff
swift run ai-dev-tools-kit prradar diff <PR_NUMBER> --config <config-name>

# Generate focus areas and filter rules
swift run ai-dev-tools-kit prradar rules <PR_NUMBER> --config <config-name>

# Run evaluations
swift run ai-dev-tools-kit prradar evaluate <PR_NUMBER> --config <config-name>

# Generate report
swift run ai-dev-tools-kit prradar report <PR_NUMBER> --config <config-name>

# Full pipeline
swift run ai-dev-tools-kit prradar analyze <PR_NUMBER> --config <config-name>

# Post review comments
swift run ai-dev-tools-kit prradar comment <PR_NUMBER> --config <config-name>
```

Use `--config <config-name>` to select a named configuration. Run `config list` to see available names.

## Configuration

Configurations are stored in `~/Library/Application Support/PRRadar/settings.json`. Add a configuration with:

```bash
swift run ai-dev-tools-kit prradar config add <name> \
  --repo-path <PATH>           # Path to the repository (required)
  --github-account <ACCOUNT>   # Credential account name (required)
  --rules-dir <DIR>            # Rules directory relative to repo root
  --set-default                # Make this the default config
```

Each configuration includes the repo path, GitHub account, default base branch, and one or more rule directories.

## CI Setup (GitHub Actions)

PRRadar can run as a GitHub Actions workflow to automatically review pull requests.

### Prerequisites

- A GitHub repository with pull requests to review
- An `ANTHROPIC_API_KEY` secret (used during the `prepare` step for focus area generation)
- A `rules/` directory in your repository containing rule files

`GITHUB_TOKEN` is automatically provided by GitHub Actions.

### Workflow File

Create `.github/workflows/pr-review.yml` in your repository:

```yaml
name: PR Review

on:
  pull_request:
    types: [opened, synchronize]
  workflow_dispatch:
    inputs:
      pr_number:
        description: 'PR number to review'
        required: true

permissions:
  contents: read
  pull-requests: write

jobs:
  review:
    runs-on: ubuntu-latest
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
    steps:
      - name: Setup Swift
        uses: swift-actions/setup-swift@v3
        with:
          swift-version: "6.2"
          skip-verify-signature: true

      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Checkout PRRadar
        uses: actions/checkout@v4
        with:
          repository: gestrich/PRRadar
          path: prradar-tool

      - name: Build PRRadar
        run: |
          cd prradar-tool/PRRadarLibrary
          swift build -c release 2>&1 | tail -5

      - name: Create config
        run: |
          cd prradar-tool/PRRadarLibrary
          swift run -c release PRRadarMacCLI config add ci \
            --repo-path ${{ github.workspace }} \
            --rules-dir rules \
            --github-account ci \
            --set-default

      - name: Resolve PR number
        id: pr
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "number=${{ github.event.inputs.pr_number }}" >> "$GITHUB_OUTPUT"
          else
            echo "number=${{ github.event.pull_request.number }}" >> "$GITHUB_OUTPUT"
          fi

      - name: Sync PR data
        run: |
          cd prradar-tool/PRRadarLibrary
          swift run -c release PRRadarMacCLI sync ${{ steps.pr.outputs.number }} \
            --config ci \
            --output-dir /tmp/prradar-output

      - name: Prepare evaluation tasks
        run: |
          cd prradar-tool/PRRadarLibrary
          swift run -c release PRRadarMacCLI prepare ${{ steps.pr.outputs.number }} \
            --config ci \
            --output-dir /tmp/prradar-output

      - name: Analyze (regex only)
        run: |
          cd prradar-tool/PRRadarLibrary
          swift run -c release PRRadarMacCLI analyze ${{ steps.pr.outputs.number }} \
            --config ci \
            --output-dir /tmp/prradar-output \
            --mode regex

      - name: Post review comments
        run: |
          cd prradar-tool/PRRadarLibrary
          swift run -c release PRRadarMacCLI comment ${{ steps.pr.outputs.number }} \
            --config ci \
            --output-dir /tmp/prradar-output
```

**Important:** The workflow file must exist on the repository's default branch for `pull_request` triggers to work.

### CI Config Notes

In CI, `--github-account ci` is a placeholder — the actual token comes from the `GITHUB_TOKEN` environment variable.

For CI, `--mode regex` is recommended to keep costs predictable. The `prepare` step still makes a single Haiku call for focus area generation.

## Troubleshooting

### Review comments not appearing

The GitHub API for creating review comments requires:
- **`pull-requests: write` permission** in the workflow's `permissions` block
- **Bearer token auth** — GitHub Actions tokens use `Authorization: Bearer <token>`
- **Comfort-fade preview header** — The `line` parameter requires `Accept: application/vnd.github.comfort-fade-preview+json`

### Rules not matching

- Verify `--rules-dir` points to the correct directory relative to the repo root
- Check that rule frontmatter `applies_to.file_patterns` matches the changed files
- Check that `grep.any` patterns match content in the diff

### Workflow not triggering

- The workflow YAML must be committed to the repository's default branch
- For `workflow_dispatch`, use the GitHub Actions UI or `gh workflow run` to trigger manually

### Runner requirements

The workflow uses `ubuntu-latest` with Swift 6.2 installed via [`swift-actions/setup-swift@v3`](https://github.com/swift-actions/setup-swift). Linux runners are significantly cheaper than macOS runners. If you need macOS-specific features, change `runs-on` to `macos-26` and remove the Setup Swift step.

### Linux build errors

If you encounter Linux build errors when pinning to a specific PRRadar version, these issues are resolved in the current main branch:

- **`setup-swift` GPG verification failure** — Add `skip-verify-signature: true` to the Setup Swift step
- **`CryptoKit` not available** — PRRadar uses `swift-crypto` as a fallback on Linux
- **`FoundationNetworking` missing** — `URLSession`/`URLRequest` require `import FoundationNetworking` on Linux
- **`CFAbsoluteTimeGetCurrent` not available** — CoreFoundation timing replaced with `Date().timeIntervalSinceReferenceDate`
