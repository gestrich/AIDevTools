#!/bin/bash
set -euo pipefail

# chain-fill.sh — Fill capacity for all chain projects matching a prefix.
# For each project, calls chain-capacity.sh (which reads maxOpenPRs from
# configuration.yml) and waits for all dispatched runs to complete before
# moving to the next project.
#
# Usage:
#   chain-fill.sh <project_prefix> [base_branch]
#
# Example:
#   chain-fill.sh model-cli-parity
#   chain-fill.sh model-cli-parity main

REPO="gestrich/AIDevTools"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${1:?Usage: chain-fill.sh <project_prefix> [base_branch]}"
BASE_BRANCH="${2:-main}"

# Skip these directories — they are not chain projects
SKIP_DIRS="claude-skills"

echo "Discovering projects matching '$PREFIX' on $BASE_BRANCH..."
echo ""

PROJECTS=()
while IFS= read -r name; do
    [ -z "$name" ] && continue
    skip=false
    for s in $SKIP_DIRS; do
        [ "$name" = "$s" ] && skip=true && break
    done
    $skip && continue
    [[ "$name" == "${PREFIX}"* ]] || continue
    PROJECTS+=("$name")
done <<< "$(gh api "repos/$REPO/contents/claude-chain?ref=$BASE_BRANCH" --jq 'sort_by(.name) | .[].name' 2>/dev/null || true)"

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "No projects found matching '$PREFIX' on $BASE_BRANCH"
    exit 1
fi

echo "Found ${#PROJECTS[@]} project(s):"
for p in "${PROJECTS[@]}"; do
    echo "  - $p"
done
echo ""

if [ -t 0 ]; then
    read -p "Fill capacity for all ${#PROJECTS[@]} project(s)? (y/N) " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

for project in "${PROJECTS[@]}"; do
    echo "════════════════════════════════════════"
    # Pass wait_last=1 so chain-capacity.sh waits for the final run before we
    # move on to the next project (avoids GitHub Actions concurrency collisions).
    # Redirect stdin from /dev/null to suppress chain-capacity.sh's interactive
    # prompt — we already confirmed above.
    "$SCRIPT_DIR/chain-capacity.sh" "$project" "$BASE_BRANCH" "" "wait-last" < /dev/null
    echo ""
done

echo "════════════════════════════════════════"
echo "Done. All projects filled."
