#!/bin/bash
set -euo pipefail

# chain-check.sh — Check status of chain projects and their open PRs.
# All data is fetched from the remote repo via GitHub API (never local files).
#
# Usage:
#   chain-check.sh all                        # All projects across all branches
#   chain-check.sh <project_prefix>           # All projects matching prefix
#   chain-check.sh <project_prefix> <branch>  # Specify base branch for discovery
#   chain-check.sh <exact_project_name>       # Single project
#
# Output: TSV lines that Claude formats into a markdown table.
# Format: PROJECT\tBASE\tPR\tTITLE\tDAYS_OPEN\tAPPROVED\tPENDING_REVIEW\tBUILD\tDONE\tTOTAL

REPO="gestrich/AIDevTools"
PREFIX="${1:?Usage: chain-check.sh <project_prefix|all> [base_branch]}"
EXPLICIT_BRANCH="${2:-}"

# Skip these directories — they are not chain projects
SKIP_DIRS="claude-skills"

# Fetch all open chain PRs once (using GraphQL pagination to avoid 30-result default limit)
ALL_PRS_JSON=$(gh api graphql --paginate -f query='
query($endCursor: String) {
  search(query: "repo:gestrich/AIDevTools is:pr is:open label:claudechain", type: ISSUE, first: 100, after: $endCursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number
        title
        headRefName
        baseRefName
        createdAt
      }
    }
  }
}' --jq '[.data.search.nodes[]]' | jq -s 'add // []')

# Discover base branches: explicit, or from open PRs + main
BRANCHES=()
if [ -n "$EXPLICIT_BRANCH" ]; then
    BRANCHES=("$EXPLICIT_BRANCH")
else
    BRANCHES=(main)
    while IFS= read -r b; do
        [ -z "$b" ] && continue
        already=false
        for existing in "${BRANCHES[@]}"; do
            [ "$existing" = "$b" ] && already=true && break
        done
        $already || BRANCHES+=("$b")
    done <<< "$(echo "$ALL_PRS_JSON" | jq -r '[.[].baseRefName] | unique | .[]')"
fi

# Discover projects across branches, track which branch each was found on
# Format: "project:branch" pairs, deduplicated (first branch wins)
PROJECT_ENTRIES=()
SEEN_PROJECTS=""

for branch in "${BRANCHES[@]}"; do
    dir_listing=$(gh api "repos/$REPO/contents/claude-chain?ref=$branch" --jq '.[].name' 2>/dev/null || true)
    while IFS= read -r name; do
        [ -z "$name" ] && continue

        # Skip non-project directories
        skip=false
        for s in $SKIP_DIRS; do
            [ "$name" = "$s" ] && skip=true && break
        done
        $skip && continue

        # Match projects starting with prefix (or all)
        if [ "$PREFIX" = "all" ] || [[ "$name" == "${PREFIX}"* ]]; then
            # Deduplicate
            if [[ ! "$SEEN_PROJECTS" == *"|${name}|"* ]]; then
                PROJECT_ENTRIES+=("${name}:${branch}")
                SEEN_PROJECTS="${SEEN_PROJECTS}|${name}|"
            fi
        fi
    done <<< "$dir_listing"
done

# Sort entries by project name
if [ ${#PROJECT_ENTRIES[@]} -eq 0 ]; then
    SORTED_ENTRIES=()
else
    IFS=$'\n' SORTED_ENTRIES=($(printf '%s\n' "${PROJECT_ENTRIES[@]}" | sort)); unset IFS
fi

if [ ${#SORTED_ENTRIES[@]} -eq 0 ]; then
    echo "ERROR: No projects found matching '${PREFIX}'" >&2
    exit 1
fi

TODAY=$(date -u +%s)

# Helper: fetch spec.md task counts from remote
fetch_spec_counts() {
    local project="$1"
    local branch="$2"
    local spec_content
    spec_content=$(gh api "repos/$REPO/contents/claude-chain/$project/spec.md?ref=$branch" --jq '.content' 2>/dev/null | base64 -D 2>/dev/null || true)
    if [ -z "$spec_content" ]; then
        echo "0 0"
        return
    fi
    local total done_count
    total=$(echo "$spec_content" | grep -c '^- \[' || true)
    done_count=$(echo "$spec_content" | grep -c '^- \[x\]' || true)
    total=${total:-0}
    done_count=${done_count:-0}
    echo "$done_count $total"
}

# Header
echo -e "PROJECT\tBASE\tPR\tTITLE\tDAYS_OPEN\tAPPROVED\tPENDING_REVIEW\tBUILD\tDONE\tTOTAL"

for entry in "${SORTED_ENTRIES[@]}"; do
    project="${entry%%:*}"
    discovery_branch="${entry#*:}"

    # Determine base branch: check if any open PR tells us, otherwise use discovery branch
    project_base="$discovery_branch"
    branch_pattern="^claude-chain-${project}-[0-9a-f]{8}$"
    pr_base=$(echo "$ALL_PRS_JSON" | jq -r \
        --arg pat "$branch_pattern" \
        '[.[] | select(.headRefName | test($pat)) | .baseRefName] | first // empty')
    if [ -n "$pr_base" ]; then
        project_base="$pr_base"
    fi

    # Fetch spec counts from remote
    read -r done_count total <<< "$(fetch_spec_counts "$project" "$project_base")"

    # Match PRs by branch: claude-chain-{project}-{8hex}
    project_prs=$(echo "$ALL_PRS_JSON" | jq -r \
        --arg pat "$branch_pattern" \
        '.[] | select(.headRefName | test($pat)) | "\(.number)\t\(.headRefName)\t\(.baseRefName)\t\(.createdAt)\t\(.title)"')

    if [ -z "$project_prs" ]; then
        echo -e "$project\t$project_base\t-\t-\t-\t-\t-\t-\t$done_count\t$total"
        continue
    fi

    while IFS=$'\t' read -r pr_number branch base_ref created_at pr_title; do
        [ -z "$pr_number" ] && continue

        # Calculate days open
        created_epoch=$(date -juf "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || date -d "$created_at" +%s 2>/dev/null || echo "$TODAY")
        days_open=$(( (TODAY - created_epoch) / 86400 ))

        # Get approved reviewers, pending reviewers, and mergeable state
        pr_meta=$(gh pr view "$pr_number" --repo "$REPO" --json reviews,reviewRequests,mergeable \
            --jq '{approved: ([.reviews[] | select(.state == "APPROVED") | .author.login] | unique | join(", ")), pending: ([.reviewRequests[] | (.login // .name)] | join(", ")), mergeable: .mergeable}' 2>/dev/null || echo '{"approved":"","pending":"","mergeable":"UNKNOWN"}')
        approved=$(echo "$pr_meta" | jq -r '.approved // ""')
        pending_review=$(echo "$pr_meta" | jq -r '.pending // ""')
        mergeable=$(echo "$pr_meta" | jq -r '.mergeable // "UNKNOWN"')

        # Get check status
        checks_raw=$(gh pr checks "$pr_number" --repo "$REPO" 2>&1 || true)
        checks_filtered=$(echo "$checks_raw" | grep -v -E '(skipping|not_required|no checks|^Process|^Deploy)' || true)
        failed=$(echo "$checks_filtered" | grep -i 'fail' | awk '{print $1}' | paste -sd',' - || true)
        pending=$(echo "$checks_filtered" | grep -i 'pending\|in_progress' | awk '{print $1}' | paste -sd',' - || true)

        if [ "$mergeable" = "CONFLICTING" ]; then
            build_status="CONFLICTING"
        elif [ -n "$failed" ]; then
            build_status="FAIL:$failed"
        elif [ -n "$pending" ]; then
            build_status="PENDING:$pending"
        else
            build_status="PASS"
        fi

        short_title=$(echo "$pr_title" | sed "s/^ClaudeChain: \[${project}\] //" | cut -c1-80)

        echo -e "$project\t$project_base\t#$pr_number\t$short_title\t${days_open}d\t$approved\t$pending_review\t$build_status\t$done_count\t$total"
    done <<< "$project_prs"
done
