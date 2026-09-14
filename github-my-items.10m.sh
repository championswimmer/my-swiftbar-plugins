#!/usr/bin/env bash
# <xbar.title>My GitHub Issues & PRs</xbar.title>
# <xbar.version>v1.9</xbar.version>
# <xbar.author>championswimmer</xbar.author>
# <xbar.author.github>championswimmer</xbar.author.github>
# <xbar.desc>Lists your last N GitHub issues & PRs (via gh GraphQL API) with status, review + CI state. GitHub Primer state colors, monochrome menubar, no emoji. N and repo filter are configurable.</xbar.desc>
# <xbar.dependencies>gh,jq</xbar.dependencies>
# <xbar.abouturl>https://github.com/championswimmer</xbar.abouturl>
# <swiftbar.environment>[GH_MY_ITEMS_COUNT=10, GH_MY_ITEMS_REPOS=]</swiftbar.environment>
# <xbar.var>number(VAR_GH_ITEMS_COUNT="10"): How many issues and PRs to list each (1-50).</xbar.var>
# <xbar.var>string(VAR_GH_ITEMS_REPOS=""): Repos to include/exclude, comma-separated: org/repo for one repo, org/* for a whole org, ! prefix to exclude. Empty = all repos. E.g. railwayapp/*,!railwayapp/mono.</xbar.var>
#
# CONFIG via SwiftBar Preferences > Plugins > this plugin > Variables (SwiftBar 2.1+):
#   VAR_GH_ITEMS_COUNT - how many issues and PRs to list each (default 10, clamped 1-50)
#   VAR_GH_ITEMS_REPOS - comma-separated filter list. Each entry is either:
#                          org/repo   - include one repo, e.g. "championswimmer/tephra"
#                          org/*      - include whole org/user, e.g. "railwayapp/*"
#                          !org/repo  - exclude one repo, e.g. "!railwayapp/mono"
#                          !org/*     - exclude whole org/user, e.g. "!championswimmer/*"
#                        ("-" also works as the exclude prefix, e.g. "-railwayapp/mono")
#                        e.g. "railwayapp/*,!railwayapp/mono,championswimmer/tephra".
#                        Empty/unset = no filter (all repos).
# Legacy GH_MY_ITEMS_* env vars still work as fallback (e.g. via Plugin Environment).

set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# ---------- config ----------
N="${VAR_GH_ITEMS_COUNT:-${GH_MY_ITEMS_COUNT:-10}}"
REPOS_CSV="${VAR_GH_ITEMS_REPOS:-${GH_MY_ITEMS_REPOS:-}}"

# validate N (default 10, clamp 1..50)
if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 1 ]; then N=10; fi
if [ "$N" -gt 50 ]; then N=50; fi

# build repo filter as search tokens appended to the query:
#   org/repo  -> " repo:org/repo"   (include single repo)
#   org/*     -> " org:org"        (include whole org/user, incl. personal accounts)
#   !org/repo -> " -repo:org/repo" (exclude single repo)
#   !org/*    -> " -org:org"       (exclude whole org/user)
# "-" works as an exclude prefix too. Excludes are AND-NOT against the includes.
REPO_Q=""
FILTER_LABEL="all repos"
if [ -n "$REPOS_CSV" ]; then
  CLEANED="$(echo "$REPOS_CSV" | tr -d '[:space:]')"
  if [ -n "$CLEANED" ]; then
    FILTER_LABEL="$CLEANED"
    IFS=',' read -r -a REPO_LIST <<< "$CLEANED"
    for r in "${REPO_LIST[@]}"; do
      NEG=""
      # strip one leading ! or - as the exclude marker
      if [[ "$r" == \!* || "$r" == \-* ]]; then
        NEG="-"
        r="${r:1}"
      fi
      if [[ "$r" == */\* ]]; then
        OWNER="${r%/*}"
        # bare owner, no nested slashes/wildcards
        if [[ -n "$OWNER" && "$OWNER" != *[/\*]* ]]; then
          if [[ -n "$NEG" ]]; then
            REPO_Q+=" -org:${OWNER}"
          else
            REPO_Q+=" org:${OWNER}"
          fi
        fi
      elif [[ "$r" == */* && "$r" != *\** ]]; then
        if [[ -n "$NEG" ]]; then
          REPO_Q+=" -repo:${r}"
        else
          REPO_Q+=" repo:${r}"
        fi
      fi
      # anything else (bare names, junk) is skipped
    done
  fi
fi

PR_Q="author:@me is:pr sort:updated-desc${REPO_Q}"
ISSUE_Q="author:@me is:issue sort:updated-desc${REPO_Q}"

# ---------- preconditions ----------
if ! command -v gh >/dev/null 2>&1; then
  echo "no gh | sfimage=exclamationmark.triangle"
  echo "---"
  echo "gh CLI not found"
  echo "Install it: brew install gh | href=https://cli.github.com/"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "no jq | sfimage=exclamationmark.triangle"
  echo "---"
  echo "jq not found"
  echo "Install it: brew install jq | href=https://jqlang.github.io/jq/"
  exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "gh login | sfimage=person.badge.key"
  echo "---"
  echo "gh is not authenticated"
  echo "Run 'gh auth login' in a terminal, then refresh"
  exit 0
fi

# ---------- fetch: one GraphQL call for both PRs and issues ----------
DATA="$(gh api graphql -F prQ="$PR_Q" -F issueQ="$ISSUE_Q" -F n="$N" -f query='
query($prQ: String!, $issueQ: String!, $n: Int!) {
  prs: search(query: $prQ, type: ISSUE, first: $n) {
    nodes {
      ... on PullRequest {
        number title url isDraft state reviewDecision
        repository { nameWithOwner }
        labels(first: 5) { nodes { name } }
        comments { totalCount }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
  issues: search(query: $issueQ, type: ISSUE, first: $n) {
    nodes {
      ... on Issue {
        number title url state stateReason
        repository { nameWithOwner }
        labels(first: 5) { nodes { name } }
        comments { totalCount }
      }
    }
  }
}' 2>&1)" || {
  echo "gh error | sfimage=exclamationmark.triangle"
  echo "---"
  echo "GraphQL query failed"
  echo "--$(echo "$DATA" | head -3 | tr '\n' ' ' | cut -c1-120)"
  exit 0
}

if echo "$DATA" | jq -e '.errors' >/dev/null 2>&1; then
  echo "gh error | sfimage=exclamationmark.triangle"
  echo "---"
  echo "$(echo "$DATA" | jq -r '.errors[0].message' | cut -c1-100)"
  exit 0
fi

# ---------- format helpers (jq) ----------
# Dropdown rows: GitHub Primer state colors for text + SF Symbol icon.
# open=green, merged/completed=purple, closed-red=red, draft/not-planned=gray.
# (Menubar header stays monochrome.)
PR_FMT='
  .data.prs.nodes[] |
  (.title | gsub("\n";" ") | gsub("\\|";"-") | .[0:60]) as $t |
  (.repository.nameWithOwner) as $r |
  (.commits.nodes[0].commit.statusCheckRollup.state // "") as $ci |
  (if .state == "MERGED" then "arrow.triangle.merge"
   elif .state == "CLOSED" then "xmark.circle"
   elif .isDraft then "pencil.line"
   elif .reviewDecision == "APPROVED" then "checkmark.circle"
   elif .reviewDecision == "CHANGES_REQUESTED" then "arrow.uturn.backward.circle"
   elif .reviewDecision == "REVIEW_REQUIRED" then "eye.circle"
   else "arrow.triangle.pull" end) as $sym |
  (if .state == "MERGED" then "#8250df,#d2a8ff"
   elif .state == "CLOSED" then "#cf222e,#f85149"
   elif .isDraft then "#6e7781,#8b949e"
   else "#1a7f37,#3fb950" end) as $color |
  (if $ci == "SUCCESS" then " · ci:pass"
   elif $ci == "FAILURE" then " · ci:fail"
   elif $ci == "PENDING" or $ci == "EXPECTED" then " · ci:pending"
   else "" end) as $cis |
  (if .state == "OPEN" and .isDraft then " · draft"
   elif .state == "OPEN" and .reviewDecision == "APPROVED" then " · approved"
   elif .state == "OPEN" and .reviewDecision == "CHANGES_REQUESTED" then " · changes-requested"
   elif .state == "OPEN" and .reviewDecision == "REVIEW_REQUIRED" then " · needs-review"
   elif .state == "MERGED" then " · merged"
   elif .state == "CLOSED" then " · closed"
   else "" end) as $revs |
  "--#\(.number) \($t) (\($r)) · 💬\(.comments.totalCount)\($cis)\($revs) | href=\(.url) sfimage=\($sym) color=\($color) sfcolor=\($color) size=12"
'
ISSUE_FMT='
  .data.issues.nodes[] |
  (.title | gsub("\n";" ") | gsub("\\|";"-") | .[0:60]) as $t |
  (.repository.nameWithOwner) as $r |
  ([.labels.nodes[].name] | join(",") | .[0:40]) as $labs |
  (if .state == "OPEN" then "dot.circle"
   elif .stateReason == "COMPLETED" then "checkmark.circle"
   else "minus.circle" end) as $sym |
  (if .state == "OPEN" then "#1a7f37,#3fb950"
   elif .stateReason == "COMPLETED" then "#8250df,#d2a8ff"
   else "#6e7781,#8b949e" end) as $color |
  (if ($labs | length) > 0 then " [\($labs)]" else "" end) as $lsuf |
  "--#\(.number) \($t)\($lsuf) (\($r)) · 💬\(.comments.totalCount) | href=\(.url) sfimage=\($sym) color=\($color) sfcolor=\($color) size=12"
'

PR_LINES="$(echo "$DATA" | jq -r "$PR_FMT" 2>/dev/null)"
ISSUE_LINES="$(echo "$DATA" | jq -r "$ISSUE_FMT" 2>/dev/null)"

PR_OPEN="$(echo "$DATA" | jq '[.data.prs.nodes[] | select(.state=="OPEN")] | length' 2>/dev/null)"
ISSUE_OPEN="$(echo "$DATA" | jq '[.data.issues.nodes[] | select(.state=="OPEN")] | length' 2>/dev/null)"
PR_OPEN="${PR_OPEN:-?}"; ISSUE_OPEN="${ISSUE_OPEN:-?}"

# ---------- output ----------
# header (menu bar): single compact line with monochrome inline SF Symbols -
# no emoji, symbols adopt menu-bar text color. dropdown=false keeps the
# counts out of the dropdown itself (dropdown starts at "My Pull Requests").
echo ":arrow.triangle.pull: ${PR_OPEN}  :dot.circle: ${ISSUE_OPEN} | symbolize=true emojize=false dropdown=false"
echo "---"

echo "My Pull Requests (last ${N}) | sfimage=arrow.triangle.pull"
if [ -n "$PR_LINES" ]; then
  echo "$PR_LINES"
else
  echo "--(none found)"
fi
echo "---"
echo "My Issues (last ${N}) | sfimage=ticket"
if [ -n "$ISSUE_LINES" ]; then
  echo "$ISSUE_LINES"
else
  echo "--(none found)"
fi
echo "---"
echo "N=${N} · filter: ${FILTER_LABEL} | size=11 symbolize=false"
echo "Legend: pencil=draft eye=needs-review uturn=changes check=approved merge=merged | size=11 symbolize=false"
echo "Refresh | refresh=true sfimage=arrow.clockwise size=11"
echo "Open my GitHub profile | href=https://github.com/ sfimage=person.circle size=11"
