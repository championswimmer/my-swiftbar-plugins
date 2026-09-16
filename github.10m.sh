#!/usr/bin/env bash
# <xbar.title>Github</xbar.title>
# <xbar.version>v2.3</xbar.version>
# <xbar.author>championswimmer</xbar.author>
# <xbar.author.github>championswimmer</xbar.author.github>
# <xbar.desc>Your GitHub issues & PRs in 4 lists (assigned/created issues, authored/assigned PRs) via gh GraphQL API, with status, review + CI state. Octicons (GitHub's own icon set) via an auto-detected Nerd Font Propo when installed, else SF Symbols + emoji fallback. GitHub Primer state colors, monochrome menubar. N and repo filter are configurable.</xbar.desc>
# <xbar.dependencies>gh,jq</xbar.dependencies>
# <xbar.abouturl>https://github.com/championswimmer</xbar.abouturl>
# <swiftbar.environment>[GH_MY_ITEMS_COUNT=10, GH_MY_ITEMS_REPOS=]</swiftbar.environment>
# <xbar.var>number(VAR_GH_ITEMS_COUNT="10"): How many items to list in each of the 4 lists (1-50).</xbar.var>
# <xbar.var>string(VAR_GH_ITEMS_REPOS=""): Repos to include/exclude, comma-separated: org/repo for one repo, org/* for a whole org, ! prefix to exclude. Empty = all repos. E.g. railwayapp/*,!railwayapp/mono.</xbar.var>
# <xbar.var>select(VAR_GH_MENUBAR_STYLE="split"): Menubar icon style: split shows PR + issue counts, github shows just the GitHub icon. [split, github]</xbar.var>
#
# CONFIG via SwiftBar Preferences > Plugins > this plugin > Variables (SwiftBar 2.1+):
#   VAR_GH_ITEMS_COUNT - how many items to list in each of the 4 lists (default 10, clamped 1-50)
#   VAR_GH_ITEMS_REPOS - comma-separated filter list. Each entry is either:
#                          org/repo   - include one repo, e.g. "championswimmer/tephra"
#                          org/*      - include whole org/user, e.g. "railwayapp/*"
#                          !org/repo  - exclude one repo, e.g. "!railwayapp/mono"
#                          !org/*     - exclude whole org/user, e.g. "!championswimmer/*"
#                        ("-" also works as the exclude prefix, e.g. "-railwayapp/mono")
#                        e.g. "railwayapp/*,!railwayapp/mono,championswimmer/tephra".
#                        Empty/unset = no filter (all repos).
#   VAR_GH_MENUBAR_STYLE - menubar icon style (default split):
#                          split  - PR icon + open PR count, issue icon + open issue count
#                          github - just the GitHub mark icon, no counts
# Legacy GH_MY_ITEMS_* env vars still work as fallback (e.g. via Plugin Environment).
#
# ICONS: dual set - SF Symbols (+ emoji) or Nerd Font Propo glyphs.
# A proportional ("Propo") Nerd Font is auto-detected via fc-list (mdls
# fallback); in Mono variants the icons render too small, Propo renders
# them at full size. With no Nerd Font installed, SF Symbols are used
# (top-level rows: sfimage only, inner rows may add emoji). To install one:
#   brew install --cask font-jetbrains-mono-nerd-font

set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# ---------- shared: Nerd Font (Propo) detection ----------
# IDENTICAL block in github.10m.sh and railway.5m.sh -
# keep the two copies in sync (each plugin must stay single-file for SwiftBar).
HAVE_NF=0; NF_FONT=""
detect_nerd_font() {
  local families fam want
  families=""
  if command -v fc-list >/dev/null 2>&1; then
    families="$(fc-list : family 2>/dev/null | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort -u | grep -i "Nerd Font Propo" || true)"
  fi
  if [ -z "$families" ] && command -v mdls >/dev/null 2>&1; then
    local d f guess
    for d in "$HOME/Library/Fonts" /Library/Fonts /System/Library/Fonts; do
      [ -d "$d" ] || continue
      for f in "$d"/*Nerd*Propo* "$d"/*NFP*Propo*; do
        [ -e "$f" ] || continue
        guess="$(mdls -raw -name kMDItemFonts "$f" 2>/dev/null | tr ',' '\n' | grep -i -m1 " Nerd Font Propo" || true)"
        guess="$(echo "$guess" | tr -d '"(),[]' | sed 's/^ *//;s/ *$//')"
        if [ -n "$guess" ]; then families="$guess"; break 2; fi
      done
    done
  fi
  [ -z "$families" ] && return 0
  families="$(echo "$families" | sort -u)"
  for want in JetBrainsMono Hack FiraCode Meslo CaskaydiaCove NotoSans 0xProto Iosevka FiraMono; do
    fam="$(echo "$families" | grep -i -m1 "$want Nerd Font Propo$" || true)"
    [ -z "$fam" ] && fam="$(echo "$families" | grep -i -m1 "$want" || true)"
    if [ -n "$fam" ]; then NF_FONT="$fam"; HAVE_NF=1; return 0; fi
  done
  fam="$(echo "$families" | grep -i -m1 " Nerd Font Propo$" || true)"
  [ -z "$fam" ] && fam="$(echo "$families" | head -1)"
  NF_FONT="$fam"; HAVE_NF=1
}
detect_nerd_font

# ---------- icons: dual set ----------
# 1. SF Symbols (+ emoji for inner rows; top-level rows use sfimage only)
# 2. Nerd Font Propo glyphs (Octicons - GitHub's own icon set)
# Resolved below into T_<NAME> (text prefix) + S_<NAME> (param suffix),
# so every output line is simply: "${T_FOO}text | ...${S_FOO} ..."
SF_GH="person.circle";                 NF_GH="$(printf '\xef\x90\x88')"         # U+F408 mark-github
SF_PR="arrow.triangle.pull";           NF_PR="$(printf '\xef\x90\x87')"         # U+F407 git-pull-request
SF_ISSUE="dot.circle";                 NF_ISSUE="$(printf '\xef\x90\x9b')"      # U+F41B issue-opened
SF_MERGED="arrow.triangle.merge";      NF_MERGED="$(printf '\xef\x90\x99')"     # U+F419 git-merge
SF_CLOSED_PR="xmark.circle";           NF_CLOSED_PR="$(printf '\xef\x93\x9c')"  # U+F4DC pull-request-closed
SF_DRAFT="pencil.line";                NF_DRAFT="$(printf '\xef\x93\x9d')"      # U+F4DD pull-request-draft
SF_APPROVED="checkmark.circle";        NF_APPROVED="$(printf '\xef\x90\xae')"  # U+F42E check
SF_CHANGES="arrow.uturn.backward.circle"; NF_CHANGES="$(printf '\xef\x93\x92')" # U+F4D2 file-diff
SF_REVIEW="eye.circle";                NF_REVIEW="$(printf '\xef\x91\x81')"     # U+F441 eye
SF_ISSUE_DONE="checkmark.circle";      NF_ISSUE_DONE="$(printf '\xef\x90\x9d')" # U+F41D issue-closed
SF_ISSUE_SKIP="minus.circle";          NF_ISSUE_SKIP="$(printf '\xef\x91\xa8')" # U+F468 dash
SF_ERR="exclamationmark.triangle";     NF_ERR="$(printf '\xef\x90\xa1')"       # U+F421 alert
SF_AUTH="person.badge.key";            NF_AUTH="$(printf '\xef\x90\x95')"       # U+F415 person
SF_REFRESH="arrow.clockwise";          NF_REFRESH="$(printf '\xef\x91\xaa')"    # U+F46A sync
SF_INBOX="tray";                      NF_INBOX="$(printf '\xef\x92\x8d')"      # U+F48D inbox
SF_LINKOUT="arrow.up.right.square";  NF_LINKOUT="$(printf '\xf3\xb0\x8f\x8c')" # U+F03CC md-open_in_new (square + arrow top-right)
SF_ASSIGNED="at.circle";               NF_ASSIGNED="$(printf '\xef\x92\x86')"   # U+F486 mention (@ = assigned to me)
SF_CREATED="square.and.pencil";        NF_CREATED="$(printf '\xef\x91\x88')"    # U+F448 pencil (written by me)
SF_SEC_ISSUES="dot.circle"
EMOJI_COMMENT="💬";                     NF_COMMENT="$(printf '\xef\x90\x9f')"     # U+F41F comment

if [ "$HAVE_NF" -eq 1 ]; then
  T_GH="$NF_GH ";                 S_GH=" font=\"$NF_FONT\""
  T_PR="$NF_PR ";                 S_PR=" font=\"$NF_FONT\""
  T_ISSUE="$NF_ISSUE ";           S_ISSUE=" font=\"$NF_FONT\""
  T_SEC_ISSUES="$NF_ISSUE ";      S_SEC_ISSUES=" font=\"$NF_FONT\""
  T_MERGED="$NF_MERGED ";         S_MERGED=" font=\"$NF_FONT\""
  T_CLOSED_PR="$NF_CLOSED_PR ";   S_CLOSED_PR=" font=\"$NF_FONT\""
  T_DRAFT="$NF_DRAFT ";           S_DRAFT=" font=\"$NF_FONT\""
  T_APPROVED="$NF_APPROVED ";     S_APPROVED=" font=\"$NF_FONT\""
  T_CHANGES="$NF_CHANGES ";       S_CHANGES=" font=\"$NF_FONT\""
  T_REVIEW="$NF_REVIEW ";         S_REVIEW=" font=\"$NF_FONT\""
  T_ISSUE_DONE="$NF_ISSUE_DONE "; S_ISSUE_DONE=" font=\"$NF_FONT\""
  T_ISSUE_SKIP="$NF_ISSUE_SKIP "; S_ISSUE_SKIP=" font=\"$NF_FONT\""
  T_ERR="$NF_ERR ";               S_ERR=" font=\"$NF_FONT\""
  T_AUTH="$NF_AUTH ";             S_AUTH=" font=\"$NF_FONT\""
  T_REFRESH="$NF_REFRESH ";       S_REFRESH=" font=\"$NF_FONT\""
  T_INBOX="$NF_INBOX ";           S_INBOX=" font=\"$NF_FONT\""
  T_SEEALL="$NF_GH ";            S_SEEALL=" font=\"$NF_FONT\""
  T_SEEALL_R=" $NF_LINKOUT"
  T_ASSIGNED="$NF_ASSIGNED ";     S_ASSIGNED=" font=\"$NF_FONT\""
  T_CREATED="$NF_CREATED ";       S_CREATED=" font=\"$NF_FONT\""
  CMT="$NF_COMMENT "
else
  T_GH="";                 S_GH=" sfimage=$SF_GH"
  T_PR="";                 S_PR=" sfimage=$SF_PR"
  T_ISSUE="";              S_ISSUE=" sfimage=$SF_ISSUE"
  T_SEC_ISSUES="";         S_SEC_ISSUES=" sfimage=$SF_SEC_ISSUES"
  T_MERGED="";             S_MERGED=" sfimage=$SF_MERGED"
  T_CLOSED_PR="";          S_CLOSED_PR=" sfimage=$SF_CLOSED_PR"
  T_DRAFT="";              S_DRAFT=" sfimage=$SF_DRAFT"
  T_APPROVED="";           S_APPROVED=" sfimage=$SF_APPROVED"
  T_CHANGES="";            S_CHANGES=" sfimage=$SF_CHANGES"
  T_REVIEW="";             S_REVIEW=" sfimage=$SF_REVIEW"
  T_ISSUE_DONE="";         S_ISSUE_DONE=" sfimage=$SF_ISSUE_DONE"
  T_ISSUE_SKIP="";         S_ISSUE_SKIP=" sfimage=$SF_ISSUE_SKIP"
  T_ERR="";                S_ERR=" sfimage=$SF_ERR"
  T_AUTH="";               S_AUTH=" sfimage=$SF_AUTH"
  T_REFRESH="";            S_REFRESH=" sfimage=$SF_REFRESH"
  T_INBOX="";                  S_INBOX=" sfimage=$SF_INBOX"
  T_SEEALL=":${SF_GH}: ";         S_SEEALL=" symbolize=true"
  T_SEEALL_R=" :${SF_LINKOUT}:"
  T_ASSIGNED="";               S_ASSIGNED=" sfimage=$SF_ASSIGNED"
  T_CREATED="";                S_CREATED=" sfimage=$SF_CREATED"
  CMT="$EMOJI_COMMENT"
fi

# ---------- config ----------
N="${VAR_GH_ITEMS_COUNT:-${GH_MY_ITEMS_COUNT:-10}}"
REPOS_CSV="${VAR_GH_ITEMS_REPOS:-${GH_MY_ITEMS_REPOS:-}}"
MENUBAR_STYLE="${VAR_GH_MENUBAR_STYLE:-${GH_MENUBAR_STYLE:-split}}"

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

PR_AUTHORED_Q="is:pr author:@me state:open archived:false sort:updated-desc${REPO_Q}"
PR_ASSIGNED_Q="is:pr assignee:@me state:open archived:false sort:updated-desc${REPO_Q}"
ISSUE_ASSIGNED_Q="is:issue archived:false assignee:@me sort:updated-desc${REPO_Q}"
ISSUE_CREATED_Q="is:issue archived:false author:@me sort:updated-desc${REPO_Q}"

# web URLs mirroring each list (space -> +, @ -> %40; : and - are legal raw)
q2url() { echo "$1" | sed 's/@/%40/g; s/ /+/g'; }
PR_AUTHORED_URL="https://github.com/pulls?q=$(q2url "$PR_AUTHORED_Q")"
PR_ASSIGNED_URL="https://github.com/pulls?q=$(q2url "$PR_ASSIGNED_Q")"
ISSUE_ASSIGNED_URL="https://github.com/issues?q=$(q2url "$ISSUE_ASSIGNED_Q")"
ISSUE_CREATED_URL="https://github.com/issues?q=$(q2url "$ISSUE_CREATED_Q")"

# ---------- preconditions ----------
if ! command -v gh >/dev/null 2>&1; then
  echo "${T_ERR}no gh |${S_ERR}"
  echo "---"
  echo "gh CLI not found"
  echo "Install it: brew install gh | href=https://cli.github.com/"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "${T_ERR}no jq |${S_ERR}"
  echo "---"
  echo "jq not found"
  echo "Install it: brew install jq | href=https://jqlang.github.io/jq/"
  exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "${T_AUTH}gh login |${S_AUTH}"
  echo "---"
  echo "gh is not authenticated"
  echo "Run 'gh auth login' in a terminal, then refresh"
  exit 0
fi

# ---------- fetch: one GraphQL call for all four lists ----------
DATA="$(gh api graphql -F prAuthoredQ="$PR_AUTHORED_Q" -F prAssignedQ="$PR_ASSIGNED_Q" -F issueAssignedQ="$ISSUE_ASSIGNED_Q" -F issueCreatedQ="$ISSUE_CREATED_Q" -F n="$N" -f query='
query($prAuthoredQ: String!, $prAssignedQ: String!, $issueAssignedQ: String!, $issueCreatedQ: String!, $n: Int!) {
  prAuthored: search(query: $prAuthoredQ, type: ISSUE, first: $n) {
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
  prAssigned: search(query: $prAssignedQ, type: ISSUE, first: $n) {
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
  issueAssigned: search(query: $issueAssignedQ, type: ISSUE, first: $n) {
    nodes {
      ... on Issue {
        number title url state stateReason
        repository { nameWithOwner }
        labels(first: 5) { nodes { name } }
        comments { totalCount }
      }
    }
  }
  issueCreated: search(query: $issueCreatedQ, type: ISSUE, first: $n) {
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
  echo "${T_ERR}gh error |${S_ERR}"
  echo "---"
  echo "GraphQL query failed"
  echo "--$(echo "$DATA" | head -3 | tr '\n' ' ' | cut -c1-120)"
  exit 0
}

if echo "$DATA" | jq -e '.errors' >/dev/null 2>&1; then
  echo "${T_ERR}gh error |${S_ERR}"
  echo "---"
  echo "$(echo "$DATA" | jq -r '.errors[0].message' | cut -c1-100)"
  exit 0
fi

# ---------- format helpers (jq) ----------
# Dropdown rows: Octicons glyphs (Nerd Font) + GitHub Primer state colors.
# The glyph is part of the text, so color= tints the icon too.
# open=green, merged/completed=purple, closed-red=red, draft/not-planned=gray.
# (Menubar header stays monochrome.)
PR_FMT='
  .data[$src].nodes[] |
  (.title | gsub("\n";" ") | gsub("\\|";"-") | .[0:70]) as $t |
  (.repository.nameWithOwner) as $r |
  (.commits.nodes[0].commit.statusCheckRollup.state // "") as $ci |
  (if .state == "MERGED" then {n:"\uf419", s:"arrow.triangle.merge"}
   elif .state == "CLOSED" then {n:"\uf4dc", s:"xmark.circle"}
   elif .isDraft then {n:"\uf4dd", s:"pencil.line"}
   elif .reviewDecision == "APPROVED" then {n:"\uf42e", s:"checkmark.circle"}
   elif .reviewDecision == "CHANGES_REQUESTED" then {n:"\uf4d2", s:"arrow.uturn.backward.circle"}
   elif .reviewDecision == "REVIEW_REQUIRED" then {n:"\uf441", s:"eye.circle"}
   else {n:"\uf407", s:"arrow.triangle.pull"} end) as $ic |
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
  (if $use_nf == 1 then $ic.n + " " else "" end) as $p |
  (if $use_nf == 1 then " font=\"\($nf)\"" else (" sfimage=" + $ic.s) end) as $q |
  (if $use_nf == 1 then " font=\"\($nf)\"" else "" end) as $q2 |
  (if $use_nf == 1 then "" else (" sfcolor=" + $color) end) as $sc |
  "----\($p)#\(.number) \($t) | href=\(.url) color=\($color)\($sc) size=12\($q)\n----  \($r) · \($cmt)\(.comments.totalCount)\($cis)\($revs) | size=11 trim=false\($q2)"
'
ISSUE_FMT='
  .data[$src].nodes[] |
  (.title | gsub("\n";" ") | gsub("\\|";"-") | .[0:70]) as $t |
  (.repository.nameWithOwner) as $r |
  ([.labels.nodes[].name] | join(",") | .[0:40]) as $labs |
  (if .state == "OPEN" then {n:"\uf41b", s:"dot.circle"}
   elif .stateReason == "COMPLETED" then {n:"\uf41d", s:"checkmark.circle"}
   else {n:"\uf468", s:"minus.circle"} end) as $ic |
  (if .state == "OPEN" then "#1a7f37,#3fb950"
   elif .stateReason == "COMPLETED" then "#8250df,#d2a8ff"
   else "#6e7781,#8b949e" end) as $color |
  (if ($labs | length) > 0 then " · \($labs)" else "" end) as $lsuf |
  (if .state == "OPEN" then ""
   elif .stateReason == "COMPLETED" then " · completed"
   elif .state == "CLOSED" then " · not-planned"
   else "" end) as $st |
  (if $use_nf == 1 then $ic.n + " " else "" end) as $p |
  (if $use_nf == 1 then " font=\"\($nf)\"" else (" sfimage=" + $ic.s) end) as $q |
  (if $use_nf == 1 then " font=\"\($nf)\"" else "" end) as $q2 |
  (if $use_nf == 1 then "" else (" sfcolor=" + $color) end) as $sc |
  "----\($p)#\(.number) \($t) | href=\(.url) color=\($color)\($sc) size=12\($q)\n----  \($r) · \($cmt)\(.comments.totalCount)\($lsuf)\($st) | size=11 trim=false\($q2)"
'

fmt_list() { # $1 = src key (prAuthored|prAssigned|issueAssigned|issueCreated), $2 = PR|ISSUE
  local src="$1" kind="$2" fmt
  if [ "$kind" = "PR" ]; then fmt="$PR_FMT"; else fmt="$ISSUE_FMT"; fi
  echo "$DATA" | jq -r --argjson use_nf "$HAVE_NF" --arg nf "$NF_FONT" --arg cmt "$CMT" --arg src "$src" "$fmt" 2>/dev/null
}

PR_AUTHORED_LINES="$(fmt_list prAuthored PR)"
PR_ASSIGNED_LINES="$(fmt_list prAssigned PR)"
ISSUE_ASSIGNED_LINES="$(fmt_list issueAssigned ISSUE)"
ISSUE_CREATED_LINES="$(fmt_list issueCreated ISSUE)"

# menubar counts: unique OPEN items across both lists of each kind
PR_OPEN="$(echo "$DATA" | jq '[.data.prAuthored.nodes[], .data.prAssigned.nodes[]] | unique_by("\(.repository.nameWithOwner)#\(.number)") | map(select(.state=="OPEN")) | length' 2>/dev/null)"
ISSUE_OPEN="$(echo "$DATA" | jq '[.data.issueAssigned.nodes[], .data.issueCreated.nodes[]] | unique_by("\(.repository.nameWithOwner)#\(.number)") | map(select(.state=="OPEN")) | length' 2>/dev/null)"
PR_OPEN="${PR_OPEN:-?}"; ISSUE_OPEN="${ISSUE_OPEN:-?}"

# ---------- output ----------
# header (menu bar): monochrome. Nerd Font mode uses Octicons text glyphs;
# SF mode uses inline :symbol: names (symbolize=true). dropdown=false keeps
# the header out of the dropdown itself (dropdown starts at "Pull Requests").
# MENUBAR_STYLE=github shows just the GitHub mark; anything else = split PR/issue counts.
if [ "$MENUBAR_STYLE" = "github" ]; then
  if [ "$HAVE_NF" -eq 1 ]; then
    echo "${NF_GH} | font=\"${NF_FONT}\" size=14 emojize=false dropdown=false"
  else
    echo ":${SF_GH}: | symbolize=true emojize=false dropdown=false"
  fi
elif [ "$HAVE_NF" -eq 1 ]; then
  echo "${NF_PR} ${PR_OPEN}  ${NF_ISSUE} ${ISSUE_OPEN} | font=\"${NF_FONT}\" size=14 emojize=false dropdown=false"
else
  echo ":arrow.triangle.pull: ${PR_OPEN}  :dot.circle: ${ISSUE_OPEN} | symbolize=true emojize=false dropdown=false"
fi
echo "---"

echo "${T_PR}Pull Requests |${S_PR}"
echo "--${T_CREATED}Authored |${S_CREATED}"
if [ -n "$PR_AUTHORED_LINES" ]; then
  echo "$PR_AUTHORED_LINES"
else
  echo "----(none found)"
fi
echo "----${T_SEEALL}See all${T_SEEALL_R} | href=${PR_AUTHORED_URL} size=11${S_SEEALL}"
echo "--${T_ASSIGNED}Assigned |${S_ASSIGNED}"
if [ -n "$PR_ASSIGNED_LINES" ]; then
  echo "$PR_ASSIGNED_LINES"
else
  echo "----(none found)"
fi
echo "----${T_SEEALL}See all${T_SEEALL_R} | href=${PR_ASSIGNED_URL} size=11${S_SEEALL}"
echo "---"
echo "${T_SEC_ISSUES}Issues |${S_SEC_ISSUES}"
echo "--${T_ASSIGNED}Assigned |${S_ASSIGNED}"
if [ -n "$ISSUE_ASSIGNED_LINES" ]; then
  echo "$ISSUE_ASSIGNED_LINES"
else
  echo "----(none found)"
fi
echo "----${T_SEEALL}See all${T_SEEALL_R} | href=${ISSUE_ASSIGNED_URL} size=11${S_SEEALL}"
echo "--${T_CREATED}Created |${S_CREATED}"
if [ -n "$ISSUE_CREATED_LINES" ]; then
  echo "$ISSUE_CREATED_LINES"
else
  echo "----(none found)"
fi
echo "----${T_SEEALL}See all${T_SEEALL_R} | href=${ISSUE_CREATED_URL} size=11${S_SEEALL}"
echo "---"
echo "N=${N} · filter: ${FILTER_LABEL} | size=11 symbolize=false"
if [ "$HAVE_NF" -eq 1 ]; then
  echo "Legend | size=11 font=\"${NF_FONT}\""
  echo "--${NF_DRAFT} draft | size=11 font=\"${NF_FONT}\""
  echo "--${NF_REVIEW} needs-review | size=11 font=\"${NF_FONT}\""
  echo "--${NF_CHANGES} changes-requested | size=11 font=\"${NF_FONT}\""
  echo "--${NF_APPROVED} approved | size=11 font=\"${NF_FONT}\""
  echo "--${NF_MERGED} merged | size=11 font=\"${NF_FONT}\""
else
  echo "Legend | size=11 symbolize=false"
  echo "--:${SF_DRAFT}: draft | size=11 symbolize=true"
  echo "--:${SF_REVIEW}: needs-review | size=11 symbolize=true"
  echo "--:${SF_CHANGES}: changes-requested | size=11 symbolize=true"
  echo "--:${SF_APPROVED}: approved | size=11 symbolize=true"
  echo "--:${SF_MERGED}: merged | size=11 symbolize=true"
fi
echo "${T_REFRESH}Refresh | refresh=true size=11${S_REFRESH}"
echo "${T_INBOX}Inbox (notifications) | href=https://github.com/notifications size=11${S_INBOX}"
