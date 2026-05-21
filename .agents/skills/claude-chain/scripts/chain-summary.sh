#!/bin/bash
set -euo pipefail

REPO="gestrich/AIDevTools"
PR_NUMBER="${1:-}"

if [ -z "$PR_NUMBER" ]; then
    echo "Fetch the ClaudeChain summary comment posted on a chain PR."
    echo ""
    echo "Usage: $0 <pr_number>"
    echo "       $0 all              # Summaries for all open chain PRs"
    echo "       $0 all <project>    # Summaries for open chain PRs in a project"
    exit 1
fi

fetch_summary() {
    local pr="$1"
    gh pr view "$pr" --repo "$REPO" --json comments \
        --jq '.comments[] | select(.author.login == "devops_jepp") | .body'
}

if [ "$PR_NUMBER" = "all" ]; then
    PROJECT="${2:-}"
    if [ -n "$PROJECT" ]; then
        PRS=$(gh pr list --repo "$REPO" --label claudechain --state open \
            --json number,headRefName \
            --jq ".[] | select(.headRefName | contains(\"$PROJECT\")) | .number")
    else
        PRS=$(gh pr list --repo "$REPO" --label claudechain --state open \
            --json number --jq '.[].number')
    fi

    if [ -z "$PRS" ]; then
        echo "No open chain PRs found."
        exit 0
    fi

    for pr in $PRS; do
        echo "=== PR #$pr ==="
        SUMMARY=$(fetch_summary "$pr")
        if [ -n "$SUMMARY" ]; then
            echo "$SUMMARY"
        else
            echo "(no summary comment found)"
        fi
        echo ""
    done
else
    SUMMARY=$(fetch_summary "$PR_NUMBER")
    if [ -n "$SUMMARY" ]; then
        echo "$SUMMARY"
    else
        echo "No ClaudeChain summary comment found on PR #$PR_NUMBER."
        echo "The comment is posted by devops_jepp after the chain workflow completes."
    fi
fi
