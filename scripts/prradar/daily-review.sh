#!/usr/bin/env bash
# =============================================================================
# PRRadar Daily Review Script
# =============================================================================
#
# >>> CURRENTLY DISABLED (2026-05-15, until further notice) <<<
# The launchd agent com.aidevtools.prradar.daily-review has been unloaded,
# so this script will NOT run automatically. The plist is still on disk at:
#   ~/Library/LaunchAgents/com.aidevtools.prradar.daily-review.plist
# To re-enable the daily schedule:
#   launchctl load ~/Library/LaunchAgents/com.aidevtools.prradar.daily-review.plist
# To verify it's loaded:
#   launchctl list | grep prradar
#

# SETUP: Fill in --config with your saved configuration name (see:
#   ai-dev-tools-kit prradar config list
# Then choose one of the scheduling options below.
#
# -----------------------------------------------------------------------------
# Option A — cron (simpler)
# -----------------------------------------------------------------------------
# Add to crontab with: crontab -e
#
#   30 5 * * * /path/to/repo/scripts/prradar/daily-review.sh >> /tmp/prradar-daily.log 2>&1
#
# Note: cron requires the machine to be awake at 5:30 AM. If it's asleep, the
# job is skipped until the next day.
#
# -----------------------------------------------------------------------------
# Option B — launchd (preferred on macOS)
# -----------------------------------------------------------------------------
# launchd wakes the machine to run the job even if it was asleep at 5:30 AM.
#
# 1. Save the plist below to ~/Library/LaunchAgents/com.aidevtools.prradar.daily-review.plist
#    (replace /path/to/repo with the absolute path to this repository)
#
# 2. Load it:
#      launchctl load ~/Library/LaunchAgents/com.aidevtools.prradar.daily-review.plist
#
# 3. To unload:
#      launchctl unload ~/Library/LaunchAgents/com.aidevtools.prradar.daily-review.plist
#
# Plist template:
# ---------------
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
#   "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <dict>
#   <key>Label</key>
#   <string>com.aidevtools.prradar.daily-review</string>
#   <key>ProgramArguments</key>
#   <array>
#     <string>/path/to/repo/scripts/prradar/daily-review.sh</string>
#   </array>
#   <key>StartCalendarInterval</key>
#   <dict>
#     <key>Hour</key>
#     <integer>5</integer>
#     <key>Minute</key>
#     <integer>30</integer>
#   </dict>
#   <key>StandardOutPath</key>
#   <string>/tmp/prradar-daily.log</string>
#   <key>StandardErrorPath</key>
#   <string>/tmp/prradar-daily.log</string>
# </dict>
# </plist>
# =============================================================================

set -euo pipefail

LOOKBACK_HOURS=72

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="$REPO_ROOT/AIDevToolsKit/.build/release/ai-dev-tools-kit"

# Build if binary is missing or any source file is newer
if [ ! -f "$CLI" ] || [ -n "$(find "$REPO_ROOT/AIDevToolsKit/Sources" -newer "$CLI" -name '*.swift' -print -quit)" ]; then
  (cd "$REPO_ROOT/AIDevToolsKit" && swift build -c release --quiet)
fi

run_review() {
  local config="$1"
  local rules_path_name="$2"
  local base_branch="${3:-}"

  RULES_ARGS=()
  if [ -n "$rules_path_name" ]; then
    RULES_ARGS+=(--rules-path-name "$rules_path_name")
  fi

  BRANCH_ARGS=()
  if [ -n "$base_branch" ]; then
    BRANCH_ARGS+=(--base-branch "$base_branch")
  fi

  set +e
  "$CLI" prradar run-all \
    --config "$config" \
    "${RULES_ARGS[@]+"${RULES_ARGS[@]}"}" \
    "${BRANCH_ARGS[@]+"${BRANCH_ARGS[@]}"}" \
    --updated-lookback-hours "$LOOKBACK_HOURS" \
    --state open
    # --comment   # uncomment to post comments automatically
  local exit_code=$?
  set -e
  return $exit_code
}

OVERALL_EXIT=0

run_review "ios-auto" "main"       "develop" || OVERALL_EXIT=$?
run_review "ios-auto" "experiment" "develop" || OVERALL_EXIT=$?

# macOS notification and open PRRadar app
if [ $OVERALL_EXIT -eq 0 ]; then
  osascript -e 'display notification "Daily PR review complete" with title "PRRadar" sound name "Glass"'
  open -a AIDevTools 2>/dev/null || true
else
  osascript -e 'display notification "Daily PR review failed (exit '"$OVERALL_EXIT"')" with title "PRRadar" sound name "Basso"'
fi

exit $OVERALL_EXIT
