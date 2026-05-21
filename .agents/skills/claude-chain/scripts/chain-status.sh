#!/bin/bash
set -euo pipefail

REPO="gestrich/AIDevTools"

# Parse flags
DRAFT_ONLY=false
PROJECT=""
for arg in "$@"; do
    case "$arg" in
        --draft) DRAFT_ONLY=true ;;
        *) PROJECT="$arg" ;;
    esac
done

QUERY='
query($endCursor: String) {
  search(query: "repo:gestrich/AIDevTools is:pr is:open label:claudechain", type: ISSUE, first: 100, after: $endCursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number
        title
        headRefName
        baseRefName
        isDraft
      }
    }
  }
}'

# Build jq filter
JQ_FILTER=""
if [ -n "$PROJECT" ]; then
    JQ_FILTER="select(.headRefName | contains(\"$PROJECT\"))"
fi
if [ "$DRAFT_ONLY" = true ]; then
    if [ -n "$JQ_FILTER" ]; then
        JQ_FILTER="$JQ_FILTER | select(.isDraft == true)"
    else
        JQ_FILTER="select(.isDraft == true)"
    fi
fi

DRAFT_LABEL=""
if [ "$DRAFT_ONLY" = true ]; then
    DRAFT_LABEL=" (draft only)"
fi

if [ -n "$PROJECT" ]; then
    echo "Open ClaudeChain PRs for project: $PROJECT$DRAFT_LABEL"
else
    echo "All open ClaudeChain PRs:$DRAFT_LABEL"
fi
echo "---"

if [ -n "$JQ_FILTER" ]; then
    FORMAT_EXPR="$JQ_FILTER | \"#\\(.number) [\\(.baseRefName)]\\(if .isDraft then \" [DRAFT]\" else \"\" end) \\(.title)\""
else
    FORMAT_EXPR='"#\(.number) [\(.baseRefName)]\(if .isDraft then " [DRAFT]" else "" end) \(.title)"'
fi

RESULTS=$(gh api graphql --paginate -f query="$QUERY" \
    --jq ".data.search.nodes[] | $FORMAT_EXPR")

echo "$RESULTS"
echo ""
echo "Total:"
echo "$RESULTS" | grep -c '^#' || echo "0"
