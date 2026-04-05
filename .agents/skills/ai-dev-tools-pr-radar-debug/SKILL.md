---
name: ai-dev-tools-pr-radar-debug
description: Debugging context for PRRadar with its configured repositories. Covers where rules, output, and settings live, and how to reproduce issues from the Mac app using CLI commands. Use this skill whenever debugging PRRadar behavior, investigating pipeline output, reproducing bug reports from the Mac app, or exploring rule evaluation results. Also use when Bill shares screenshots showing issues in the Mac app, or mentions code reviews, rule directories, output files, or PRRadar configs.
---

# PRRadar Debugging Guide

PRRadar has repository configurations available for debugging. Both the MacApp (GUI) and PRRadarMacCLI (CLI) share the same use cases and services, so any issue seen in the Mac app can be reproduced with CLI commands.

## Discovering Configurations

Settings are stored at:
```
~/Library/Application Support/PRRadar/settings.json
```

List configurations with:
```bash
cd PRRadarLibrary
swift run PRRadarMacCLI config list
```

Or read the JSON directly to see all config details (repo paths, rule paths, diff source, GitHub account, default base branch):
```bash
cat ~/Library/Application\ Support/PRRadar/settings.json
```

Each configuration includes:
- **Repo path** — local checkout of the repository
- **GitHub account** — owner/org on GitHub
- **Default base branch** — e.g. `develop` or `main`
- **Rule paths** — one or more named rule directories (relative to repo or absolute)

## Output Directory

Pipeline output location is defined in the configuration. Inspect the settings JSON to find the output directory. Output is organized as `<outputDir>/<PR_NUMBER>/` with subdirectories for each pipeline phase (metadata, diff, prepare, evaluate, report).

```bash
ls <outputDir>/<PR_NUMBER>/
```

## Reproducing Issues with CLI

The Mac app and CLI share the same use cases (in `PRReviewFeature`), so CLI commands reproduce the same behavior. Run from `PRRadarLibrary/`:

```bash
# Fetch diff
swift run PRRadarMacCLI diff <PR_NUMBER> --config <config-name>

# Generate focus areas and filter rules
swift run PRRadarMacCLI rules <PR_NUMBER> --config <config-name>

# Run evaluations
swift run PRRadarMacCLI evaluate <PR_NUMBER> --config <config-name>

# Generate report
swift run PRRadarMacCLI report <PR_NUMBER> --config <config-name>

# Full pipeline (diff + rules + evaluate + report)
swift run PRRadarMacCLI analyze <PR_NUMBER> --config <config-name>

# Check pipeline status
swift run PRRadarMacCLI status <PR_NUMBER> --config <config-name>
```

Use `--config <config-name>` to select the repository. Run `config list` to see available names. If `--config` is omitted, the default config is used.

## Test Repository

A dedicated test repo exists at `/Users/bill/Developer/personal/PRRadar-TestRepo` for validating changes against real PRs. Use the `test-repo` config to target it — its output directory is `~/Desktop/code-reviews/`.

**Clean before running** to avoid "uncommitted changes" errors from previous runs:
```bash
cd /Users/bill/Developer/personal/PRRadar-TestRepo
rm -rf code-reviews
git checkout main
rm -rf ~/Desktop/code-reviews
```

Then run normally with `--config test-repo`.

## Logs

Logs are the primary tool for troubleshooting CLI and Mac app behavior. For reading logs, filtering output, and adding log statements for debugging, use the logging skill:

`.agents/skills/ai-dev-tools-logging/SKILL.md`

## Debugging Tips

- **Check pipeline phase output:** Look in `<outputDir>/<PR>/` for JSON artifacts from each phase.
- **Phase order:** METADATA -> DIFF -> PREPARE (focus areas, rules, tasks) -> EVALUATE -> REPORT
- **Phase result files:** Each phase writes a `phase_result.json` indicating success/failure.
- **Rule directories:** Rule paths are defined per-config in settings. Some are relative to the repo, others are absolute paths. Check the settings JSON to find them.
- **Build and test:** Run `swift build` and `swift test` from `PRRadarLibrary/` to verify changes.
- **Daily review script:** `scripts/daily-review.sh` is a scheduling wrapper that runs the `run-all` pipeline on a daily basis (via cron or launchd). Supports `--mode` and `--lookback-hours` flags.
