#!/bin/bash
set -euo pipefail

REPO="gestrich/AIDevTools"
PROJECT="${1:?Usage: chain-capacity.sh <project_name> [base_branch] [max_open_prs] [wait_last]}"
BASE_BRANCH="${2:-main}"
EXPLICIT_MAX="${3:-}"
WAIT_LAST="${4:-}"  # If non-empty, wait for the last dispatched run to complete

# Read maxOpenPRs from remote configuration.yml, defaulting to 1 per upstream convention
CONFIG_MAX=""
CONFIG_CONTENT=$(gh api "repos/$REPO/contents/claude-chain/$PROJECT/configuration.yml?ref=$BASE_BRANCH" \
    --jq '.content' \
    -H "Accept: application/vnd.github.v3+json" 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -n "$CONFIG_CONTENT" ]; then
    CONFIG_MAX=$(echo "$CONFIG_CONTENT" | grep -E '^maxOpenPRs:' | awk '{print $2}' || true)
fi

# Priority: explicit CLI arg > configuration.yml > default of 1
if [ -n "$EXPLICIT_MAX" ]; then
    MAX_OPEN="$EXPLICIT_MAX"
elif [ -n "$CONFIG_MAX" ]; then
    MAX_OPEN="$CONFIG_MAX"
else
    MAX_OPEN=1
fi

echo "Checking capacity for project: $PROJECT"
echo "  Base branch:   $BASE_BRANCH"
echo "  Max open PRs:  $MAX_OPEN"
echo ""

# Count unchecked tasks from remote spec.md
SPEC_CONTENT=$(gh api "repos/$REPO/contents/claude-chain/$PROJECT/spec.md?ref=$BASE_BRANCH" \
    --jq '.content' \
    -H "Accept: application/vnd.github.v3+json" | base64 -d)

UNCHECKED=$(echo "$SPEC_CONTENT" | grep -c '^\- \[ \]' || true)

# Count open PRs for this project
OPEN_PRS=$(gh pr list --repo "$REPO" --label claudechain --state open \
    --json headRefName \
    --jq "[.[] | select(.headRefName | contains(\"$PROJECT\"))] | length")

AVAILABLE=$((MAX_OPEN - OPEN_PRS))
if [ "$AVAILABLE" -lt 0 ]; then
    AVAILABLE=0
fi

REMAINING=$((UNCHECKED - OPEN_PRS))
if [ "$REMAINING" -lt 0 ]; then
    REMAINING=0
fi

# How many to trigger: min of available slots and remaining tasks
TO_TRIGGER=$((AVAILABLE < REMAINING ? AVAILABLE : REMAINING))

echo "  Unchecked tasks: $UNCHECKED"
echo "  Open PRs:        $OPEN_PRS"
echo "  Remaining:       $REMAINING"
echo "  Slots available: $AVAILABLE"
echo "  To trigger:      $TO_TRIGGER"
echo ""

if [ "$TO_TRIGGER" -eq 0 ]; then
    echo "No capacity to fill."
    exit 0
fi

if [ -t 0 ]; then
    read -p "Trigger $TO_TRIGGER workflow run(s)? (y/N) " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
else
    echo "Triggering $TO_TRIGGER workflow run(s) (non-interactive mode)..."
fi

WORKFLOW_NAME="Claude Chain"
POLL_INTERVAL=30

# Dispatch one run at a time and wait for it to complete before dispatching the next.
# GitHub's concurrency group only allows 1 running + 1 pending workflow. Dispatching
# 2 at once seems safe (1 runs, 1 queues) but when the running one finishes and we
# dispatch a 3rd, the 3rd replaces the queued one — cancelling it. So we must
# strictly serialize: dispatch, wait for completion, then dispatch the next.
for i in $(seq 1 "$TO_TRIGGER"); do
    echo "[$i/$TO_TRIGGER] Dispatching workflow run..."

    BEFORE_DISPATCH=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    sleep 1

    gh workflow run "$WORKFLOW_NAME" \
        --repo "$REPO" \
        --ref "$BASE_BRANCH" \
        --field project_name="$PROJECT" \
        --field base_branch="$BASE_BRANCH"

    # Wait for the dispatched run to appear in the API
    RUN_ID=""
    for attempt in $(seq 1 20); do
        sleep 5
        RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW_NAME" --limit 5 \
            --json databaseId,createdAt,status \
            --jq "[.[] | select(.createdAt >= \"$BEFORE_DISPATCH\")] | sort_by(.createdAt) | last | .databaseId // empty")
        if [ -n "$RUN_ID" ]; then
            break
        fi
    done

    if [ -z "$RUN_ID" ]; then
        echo "  Warning: could not find workflow run after dispatch. Continuing anyway."
        continue
    fi

    echo "  Run ID: $RUN_ID (https://github.com/$REPO/actions/runs/$RUN_ID)"

    # If this is the last run and caller doesn't require us to wait, skip the wait
    if [ "$i" -eq "$TO_TRIGGER" ] && [ -z "$WAIT_LAST" ]; then
        echo "  Last run dispatched — not waiting."
        break
    fi

    # Poll until the run completes
    echo "  Waiting for run to complete before dispatching next..."
    while true; do
        STATUS=$(gh run view "$RUN_ID" --repo "$REPO" --json status --jq '.status')
        case "$STATUS" in
            completed)
                CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion --jq '.conclusion')
                echo "  Run $RUN_ID completed ($CONCLUSION)."
                break
                ;;
            queued|in_progress|waiting|pending|requested)
                sleep "$POLL_INTERVAL"
                ;;
            *)
                echo "  Run $RUN_ID has unexpected status: $STATUS. Moving on."
                break
                ;;
        esac
    done
done

echo ""
echo "Dispatched $TO_TRIGGER workflow run(s)."
