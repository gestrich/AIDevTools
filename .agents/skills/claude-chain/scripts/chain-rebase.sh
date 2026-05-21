#!/bin/bash
set -euo pipefail

REPO="gestrich/AIDevTools"
PROJECT="${1:-}"

echo "Fetching open ClaudeChain PRs..."

if [ -n "$PROJECT" ]; then
    PRS=$(gh pr list --repo "$REPO" --label claudechain --state open \
        --json number,headRefName,baseRefName \
        --jq "[.[] | select(.headRefName | contains(\"$PROJECT\"))]")
else
    PRS=$(gh pr list --repo "$REPO" --label claudechain --state open \
        --json number,headRefName,baseRefName)
fi

COUNT=$(echo "$PRS" | jq 'length')

if [ "$COUNT" -eq 0 ]; then
    echo "No open ClaudeChain PRs found."
    exit 0
fi

echo "Found $COUNT open PR(s) to rebase."
echo ""

echo "$PRS" | jq -r '.[] | "#\(.number): \(.headRefName) -> \(.baseRefName)"'
echo ""

read -p "Force-push rebased branches? (y/N) " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

git fetch origin

echo "$PRS" | jq -c '.[]' | while read -r PR; do
    NUMBER=$(echo "$PR" | jq -r '.number')
    HEAD=$(echo "$PR" | jq -r '.headRefName')
    BASE=$(echo "$PR" | jq -r '.baseRefName')

    echo ""
    echo "--- PR #$NUMBER: $HEAD onto $BASE ---"
    git checkout "$HEAD" 2>/dev/null || git checkout -b "$HEAD" "origin/$HEAD"
    git reset --hard "origin/$HEAD"
    if git rebase "origin/$BASE"; then
        git push --force-with-lease origin "$HEAD"
        echo "Rebased and pushed #$NUMBER"
    else
        echo "Rebase conflict on #$NUMBER — skipping (run 'git rebase --abort' if needed)"
        git rebase --abort 2>/dev/null || true
    fi
done

echo ""
echo "Done."
