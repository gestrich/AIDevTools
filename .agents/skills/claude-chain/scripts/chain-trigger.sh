#!/bin/bash
set -euo pipefail

REPO="gestrich/AIDevTools"
PROJECT="${1:?Usage: chain-trigger.sh <project_name> [base_branch]}"
BASE_BRANCH="${2:-main}"

echo "Triggering Claude Chain workflow..."
echo "  Project:     $PROJECT"
echo "  Base branch: $BASE_BRANCH"
echo "  Ref:         $BASE_BRANCH"
echo ""

gh workflow run "Claude Chain" \
    --repo "$REPO" \
    --ref "$BASE_BRANCH" \
    --field project_name="$PROJECT" \
    --field base_branch="$BASE_BRANCH"

echo "Workflow dispatched. Check status with:"
echo "  gh run list --repo $REPO --workflow 'Claude Chain' --limit 5"
