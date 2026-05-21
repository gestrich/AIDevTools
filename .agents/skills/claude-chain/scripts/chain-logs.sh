#!/bin/bash
set -euo pipefail

REPO="gestrich/AIDevTools"
WORKFLOW="Claude Chain"
RUN_ID="${1:-}"

if [ -z "$RUN_ID" ]; then
    echo "Recent Claude Chain workflow runs:"
    echo "---"
    gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 10
    echo ""
    echo "To view logs for a specific run:"
    echo "  $0 <run_id>"
else
    echo "Fetching logs for run $RUN_ID..."
    echo "---"
    gh run view "$RUN_ID" --repo "$REPO"
    echo ""
    read -p "Download full logs? (y/N) " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        gh run view "$RUN_ID" --repo "$REPO" --log
    fi
fi
