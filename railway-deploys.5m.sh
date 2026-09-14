#!/usr/bin/env bash
# <xbar.title>Railway Deploys</xbar.title>
# <xbar.version>v1.4</xbar.version>
# <xbar.author>championswimmer</xbar.author>
# <xbar.author.github>championswimmer</xbar.author.github>
# <xbar.desc>Workspace -> project -> environment -> service tree with current status on top and last N deploys below (click opens logs in the Railway dashboard). Volumes show size + fill. Uses the railway CLI (railway api GraphQL).</xbar.desc>
# <xbar.dependencies>railway,jq</xbar.dependencies>
# <xbar.abouturl>https://railway.com</xbar.abouturl>
# <swiftbar.environment>[VAR_RAILWAY_WORKSPACE=, VAR_RAILWAY_DEPLOY_COUNT=10, VAR_RAILWAY_ICON=train.side.front.car]</swiftbar.environment>
# <xbar.var>string(VAR_RAILWAY_WORKSPACE=""): Workspace (org) to pin: name or ID. Empty (or ALL) = all workspaces; when pinned the tree starts at projects. Tip: pick from the "Workspace: ..." switcher in the menu - it saves here automatically.</xbar.var>
# <xbar.var>number(VAR_RAILWAY_DEPLOY_COUNT="10"): How many recent deploys to list per service (1-30).</xbar.var>
# <xbar.var>select(VAR_RAILWAY_ICON="train.side.front.car"): Menu bar icon (train/rail SF Symbols only). [train.side.front.car, train.side.middle.car, train.side.rear.car, tram, tram.fill, tram.circle, tram.circle.fill, tram.tunnel.fill, lightrail, lightrail.fill, cablecar, cablecar.fill]</xbar.var>
#
# CONFIG via SwiftBar Preferences > Plugins > this plugin > Variables (SwiftBar 2.1+):
#   VAR_RAILWAY_WORKSPACE    - workspace name or ID to pin (empty or ALL =
#                              all workspaces; when pinned the tree starts at
#                              projects, one level less). This is a plain
#                              string field - the DYNAMIC picker lives in the
#                              dropdown itself: every run fetches the user's
#                              workspaces fresh and shows a "Workspace: ..."
#                              switcher menu; clicking one invokes this script
#                              via `bash=` with select-workspace <id> (plus
#                              refresh=true), which persists the choice to the
#                              script's .vars.json sidecar - so the menu
#                              switcher and Preferences stay in sync.
#                              (Legacy RAILWAY_WORKSPACE env still works as fallback.)
#   VAR_RAILWAY_DEPLOY_COUNT - recent deploys listed per service (default 10, clamped 1-30)
#   VAR_RAILWAY_ICON         - menu bar icon, any train/rail SF Symbol
#                              (default train.side.front.car). Pick from the
#                              dropdown in Preferences > Plugins > Variables.
# Legacy RAILWAY_* env vars still work as fallback (e.g. via Plugin Environment).

set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# ---------- config ----------
RAW_PIN="${VAR_RAILWAY_WORKSPACE:-${RAILWAY_WORKSPACE:-}}"
PIN="$RAW_PIN"
# select-dropdown sentinel: ALL (or empty/unset) = show all workspaces
if [ "$PIN" = "ALL" ]; then PIN=""; fi
# absolute path of this plugin (SwiftBar sets SWIFTBAR_PLUGIN_PATH at runtime;
# $0 fallback is for manual runs). Used for the .vars.json sidecar + menu URLs.
PLUGIN_PATH="${SWIFTBAR_PLUGIN_PATH:-$0}"
case "$PLUGIN_PATH" in
  /*) ;;
  *) PLUGIN_PATH="$PWD/${PLUGIN_PATH#./}" ;;
esac
PLUGIN_FILE="$(basename "$PLUGIN_PATH")"
# Sidecar path MUST match SwiftBar's convention (PluginVariableStorage):
# strip the last extension, then append .vars.json
# e.g. railway-deploys.5m.sh -> railway-deploys.5m.vars.json
VARS_FILE="${PLUGIN_PATH%.*}.vars.json"
N="${VAR_RAILWAY_DEPLOY_COUNT:-${RAILWAY_DEPLOY_COUNT:-10}}"
# menu bar icon: any train/rail SF Symbol (configurable via Preferences dropdown)
ICON="${VAR_RAILWAY_ICON:-${RAILWAY_ICON:-train.side.front.car}}"
case "$ICON" in
  train.side.front.car|train.side.middle.car|train.side.rear.car|tram|tram.fill|tram.circle|tram.circle.fill|tram.tunnel.fill|lightrail|lightrail.fill|cablecar|cablecar.fill) ;;
  *) ICON="train.side.front.car" ;;
esac

# validate N (default 10, clamp 1..30)
if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 1 ]; then N=10; fi
if [ "$N" -gt 30 ]; then N=30; fi

# ---------- preconditions ----------
if ! command -v railway >/dev/null 2>&1; then
  echo "no railway | sfimage=exclamationmark.triangle"
  echo "---"
  echo "railway CLI not found"
  echo "Install it: brew install railway | href=https://docs.railway.com/cli/installation"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "no jq | sfimage=exclamationmark.triangle"
  echo "---"
  echo "jq not found"
  echo "Install it: brew install jq | href=https://jqlang.github.io/jq/"
  exit 0
fi
if ! railway whoami >/dev/null 2>&1; then
  echo "railway login | sfimage=person.badge.key"
  echo "---"
  echo "railway is not authenticated"
  echo "Run 'railway login' in a terminal, then refresh"
  exit 0
fi

fail_dropdown() { # $1 = message
  echo "railway error | sfimage=exclamationmark.triangle"
  echo "---"
  echo "$1"
  exit 0
}

# thin wrapper: railway_api '<graphql>' [--var k=v ...] [--variables '{...}']
# prints stdout JSON; returns non-zero on CLI failure
railway_api() {
  railway api "$@" 2>/dev/null
}

# In-menu workspace switcher handler. Menu items invoke this script as
#   "<plugin>" select-workspace <workspace-id|ALL>
# via `bash=` (with refresh=true terminal=false). Persist the choice to the
# .vars.json sidecar and exit; SwiftBar then refreshes the plugin, which
# picks the new value up from the sidecar. `bash=` (not `href=
# swiftbar://refreshplugin?...`) is used deliberately: it is the documented
# action mechanism that works on every SwiftBar version and always yields
# an enabled, clickable menu item (custom-scheme hrefs need a new SwiftBar
# and can render as disabled/dead items on older ones).
if [ "${1:-}" = "select-workspace" ]; then
  CHOICE="${2:-ALL}"
  if [ "$CHOICE" = "ALL" ]; then
    WANT="ALL"
  else
    WNAME="$(railway_api 'query { me { workspaces { id name } } }' \
      | jq -r --arg id "$CHOICE" '.data.me.workspaces[] | select(.id==$id) | .name // empty' 2>/dev/null)"
    WANT="${WNAME:-$CHOICE}"
  fi
  if [ -f "$VARS_FILE" ]; then
    jq --arg v "$WANT" '. + {VAR_RAILWAY_WORKSPACE: $v}' "$VARS_FILE" >"$VARS_FILE.tmp" \
      && mv "$VARS_FILE.tmp" "$VARS_FILE"
  else
    jq -n --arg v "$WANT" '{VAR_RAILWAY_WORKSPACE: $v}' >"$VARS_FILE"
  fi
  exit 0
fi

# ---------- step 1: workspaces (orgs) ----------
ME_JSON="$(railway_api 'query { me { workspaces { id name } } }')" || \
  fail_dropdown "railway api call failed"
if echo "$ME_JSON" | jq -e '.errors' >/dev/null 2>&1; then
  fail_dropdown "$(echo "$ME_JSON" | jq -r '.errors[0].message' | cut -c1-100)"
fi
if ! echo "$ME_JSON" | jq -e '.data.me.workspaces' >/dev/null 2>&1; then
  fail_dropdown "unexpected response from railway api"
fi

# resolve pinned workspace (match by id first, then name)
PINNED_WS_ID=""; PINNED_WS_NAME=""
if [ -n "$PIN" ]; then
  PINNED_WS_ID="$(echo "$ME_JSON" | jq -r --arg pin "$PIN" '
    .data.me.workspaces as $ws
    | (($ws | map(select(.id==$pin)) | .[0])
       // ($ws | map(select(.name==$pin)) | .[0])) | .id // empty')"
  if [ -z "$PINNED_WS_ID" ]; then
    AVAIL="$(echo "$ME_JSON" | jq -r '.data.me.workspaces[].name' | paste -sd ', ' -)"
    fail_dropdown "workspace '$PIN' not found (have: $AVAIL)"
  fi
  PINNED_WS_NAME="$(echo "$ME_JSON" | jq -r --arg id "$PINNED_WS_ID" \
    '.data.me.workspaces[] | select(.id==$id) | .name')"
  WS_LIST_JSON="$(echo "$ME_JSON" | jq -c --arg id "$PINNED_WS_ID" \
    '[.data.me.workspaces[] | select(.id==$id)]')"
else
  WS_LIST_JSON="$(echo "$ME_JSON" | jq -c '[.data.me.workspaces[]]')"
fi

# depth offset: workspace level shown -> projects start at depth 1,
# pinned -> projects start at depth 0 (one level less)
if [ -n "$PIN" ]; then BASE=0; else BASE=1; fi

# (Workspace choice persistence lives in the select-workspace handler above:
# menu clicks invoke this script via `bash=`, which writes the .vars.json
# sidecar directly. Plain plugin runs only read it.)

# ---------- jq renderer: one hydrated project -> dropdown lines ----------
# input: project object from projectsByIds (with environments + deployments)
# args: $base (depth offset), $n (deploys per service)
RENDER_FILTER='
def pfx($d): "--" * ($base + $d);
def esc: ((. // "") | tostring | gsub("\n";" ") | gsub("\\|";"-"));
def ts: (((. // "") | tostring | .[5:16]) | sub("T";" "));
def mstr($m; $k): ((try ($m | .[$k]) catch "") // "" | tostring);
def hum: if . >= 1024 then "\(((. / 102.4) | floor) / 10) GB" else "\(floor) MB" end;
def st($s):
  if $s == "SUCCESS" then {sym:"checkmark.circle", col:"#1a7f37,#3fb950", e:"✅"}
  elif $s == "FAILED" or $s == "CRASHED" then {sym:"xmark.circle", col:"#cf222e,#f85149", e:"❌"}
  elif $s == "BUILDING" or $s == "DEPLOYING" then {sym:"arrow.triangle.2.circlepath", col:"#9a6700,#d29922", e:"🔨"}
  elif $s == "QUEUED" or $s == "WAITING" or $s == "INITIALIZING" then {sym:"hourglass", col:"#9a6700,#d29922", e:"⏳"}
  elif $s == "SLEEPING" then {sym:"moon.zzz", col:"#6e7781,#8b949e", e:"💤"}
  elif $s == "REMOVED" or $s == "SKIPPED" or $s == "REMOVING" then {sym:"minus.circle", col:"#6e7781,#8b949e", e:"➖"}
  else {sym:"exclamationmark.circle", col:"#8250df,#d2a8ff", e:"🟣"} end;

.id as $pid
| (.name | esc) as $pname
| (.deployments.edges | map(.node)) as $alldeps
| (.environments.edges | map(.node) | map(select(.deletedAt == null))) as $envs
| (pfx(0) + "\($pname) | sfimage=rectangle.stack href=https://railway.com/project/\($pid)"),
  (if ($envs | length) == 0 then pfx(1) + "(no environments) | size=11 symbolize=false" else empty end),
  ($envs[] as $env
   | $env.id as $eid
   | ($env.name | esc) as $ename
   | "https://railway.com/project/\($pid)?environmentId=\($eid)" as $envurl
   | ($env.serviceInstances.edges | map(.node) | map(select(.deletedAt == null))) as $svcs
   | ($env.volumeInstances.edges | map(.node)) as $vols
   | (pfx(1) + "\($ename) | sfimage=globe href=\($envurl)"),
     ($svcs[] as $svc
      | $svc.serviceId as $sid
      | ($svc.serviceName | esc) as $sname
      | "https://railway.com/project/\($pid)/service/\($sid)?environmentId=\($eid)" as $svcurl
      | ($alldeps | map(select(.environmentId == $eid and .serviceId == $sid))
          | sort_by(.createdAt) | reverse) as $sdeps
      | ($sdeps[0:$n]) as $show
      | ($svc.latestDeployment) as $ld
      | (pfx(2) + "\($sname) | sfimage=server.rack href=\($svcurl)"),
        (if $ld == null then
           pfx(3) + "Current · never deployed | href=\($svcurl) sfimage=minus.circle color=#6e7781,#8b949e size=12"
         else
           ($ld.id) as $lid
           | ($ld.status) as $lst
           | ($alldeps | map(select(.id == $lid)) | .[0]) as $ldfull
           | st($lst) as $c
           | ((if $ldfull != null and ($ldfull.meta.branch // "") != ""
               then " · \($ldfull.meta.branch | tostring | esc | .[0:30])" else "" end)) as $br
           | (pfx(3) + "Current · \($lst)\($br) · \($ld.createdAt | ts) | href=\($svcurl) sfimage=\($c.sym) color=\($c.col) sfcolor=\($c.col) size=12")
         end),
        (pfx(3) + "Last \($n) deploys | size=11 symbolize=false disabled=true"),
        (if ($show | length) == 0 then pfx(3) + "(no deploys yet) | size=11 symbolize=false" else empty end),
        ($show[] as $d
         | st($d.status) as $c
         | "https://railway.com/project/\($pid)/service/\($sid)?environmentId=\($eid)&id=\($d.id)" as $durl
         | (($d.meta.branch // "") | tostring | esc | .[0:24]) as $br
         | ((($d.meta.commitMessage // "") | tostring | split("\n")[0] | esc | .[0:44])) as $msg
         | ((if $br != "" then " · \($br)" else "" end)
            + (if $msg != "" then " · \($msg)" else "" end)) as $extra
         | (pfx(3) + "\($c.e) \($d.status)\($extra) · \($d.createdAt | ts) | href=\($durl) sfimage=\($c.sym) color=\($c.col) sfcolor=\($c.col) size=12")
        )
     ),
     (if ($vols | length) > 0 then
        (pfx(2) + "Volumes (\(($vols | length))) | sfimage=internaldrive size=12"),
        ($vols[] as $v
         | (($v.volume.name // "volume") | esc) as $vname
         | ($v.sizeMB) as $size
         | (($v.currentSizeMB // 0)) as $cur
         | (if $size != null and $size > 0
            then (($cur / $size * 100) | floor) else null end) as $pct
         | (if $pct == null then {bar:"", col:"#6e7781,#8b949e"}
            elif $pct >= 90 then {bar:(("█" * (($pct / 10) | floor)) + ("░" * (10 - (($pct / 10) | floor)))), col:"#cf222e,#f85149"}
            elif $pct >= 75 then {bar:(("█" * (($pct / 10) | floor)) + ("░" * (10 - (($pct / 10) | floor)))), col:"#9a6700,#d29922"}
            else {bar:(("█" * (($pct / 10) | floor)) + ("░" * (10 - (($pct / 10) | floor)))), col:"#1a7f37,#3fb950"} end) as $vc
         | "https://railway.com/project/\($pid)/volume/\($v.volumeId)/metrics?environmentId=\($eid)" as $vurl
         | ((if ($v.mountPath // "") != "" then ($v.mountPath | esc) else "mount path unknown" end)) as $vmount
         | ((if ($v.service.name // "") != "" then ($v.service.name | esc) else "unattached" end)) as $vsvc
         | ((if $size != null
             then "\($cur | floor | hum) of \($size | hum) · \($pct)% \($vc.bar)"
             else "usage unknown" end)) as $vfill
         | (pfx(3) + "💾 \($vname) | href=\($vurl) sfimage=internaldrive color=\($vc.col) sfcolor=\($vc.col) size=12"),
           (pfx(4) + "Filled · \($vfill) | href=\($vurl) color=\($vc.col) sfcolor=\($vc.col) size=12"),
           (pfx(4) + "Mounted at · \($vmount) | href=\($vurl) size=11 symbolize=false"),
           (pfx(4) + "Service · \($vsvc) | href=\($vurl) size=11 symbolize=false"),
           (if ($v.state // "") != "" then pfx(4) + "State · \($v.state | esc) | href=\($vurl) size=11 symbolize=false" else empty end)
        )
      else empty end)
  )
'

# hydration query: environments + service instances (with latest deploy) +
# volume instances + recent project deployments (grouped per service in jq)
HYDRATE_Q='query($ids: [String!]!) {
  projectsByIds(ids: $ids) {
    id name workspaceId
    environments(first: 20) { edges { node { id name deletedAt
      serviceInstances(first: 50) { edges { node {
        serviceId serviceName deletedAt
        latestDeployment { id status createdAt } } } }
      volumeInstances(first: 20) { edges { node {
        id volumeId sizeMB currentSizeMB state mountPath
        service { name } volume { name } } } }
    } } }
    deployments(first: 50) { edges { node {
      id status createdAt environmentId serviceId meta } } }
  }
}'

TMPBODY="$(mktemp)"; trap 'rm -f "$TMPBODY"' EXIT
TOT=0; OKC=0; BADC=0; BUSYC=0; NEVERC=0; PROJC=0

# ---------- step 2+3: per workspace -> projects -> batched hydration ----------
while IFS= read -r WS; do
  WSID="$(echo "$WS" | jq -r '.id')"
  WSNAME="$(echo "$WS" | jq -r '.name')"
  WSURL="https://railway.com/workspace?workspaceId=${WSID}"

  PROJ_JSON="$(railway_api --var workspaceId="$WSID" \
    'query($workspaceId: String) { projects(workspaceId: $workspaceId, first: 50) { edges { node { id name } } } }')" || \
    { echo "--${WSNAME} (projects query failed) | sfimage=exclamationmark.triangle" >>"$TMPBODY"; continue; }
  if echo "$PROJ_JSON" | jq -e '.errors' >/dev/null 2>&1; then
    echo "--${WSNAME} ($(echo "$PROJ_JSON" | jq -r '.errors[0].message' | cut -c1-60)) | sfimage=exclamationmark.triangle" >>"$TMPBODY"
    continue
  fi
  IDS_JSON="$(echo "$PROJ_JSON" | jq -c '[.data.projects.edges[].node.id]')"
  NUM="$(echo "$IDS_JSON" | jq 'length')"

  if [ -z "$PIN" ]; then
    SAFE_WS="$(echo "$WSNAME" | tr '\n' ' ' | tr '|' '-')"
    echo "${SAFE_WS} (${NUM}) | sfimage=building.2 href=${WSURL}" >>"$TMPBODY"
  fi
  if [ "$NUM" -eq 0 ]; then
    if [ -n "$PIN" ]; then echo "(no projects in ${PINNED_WS_NAME}) | size=11 symbolize=false" >>"$TMPBODY";
    else echo "--(no projects) | size=11 symbolize=false" >>"$TMPBODY"; fi
    continue
  fi

  # hydrate in chunks of 10 project ids
  echo "$IDS_JSON" | jq -c 'range(0; length; 10) as $i | .[$i:$i+10]' | while read -r CHUNK; do
    HYDR="$(railway_api --variables "{\"ids\":$CHUNK}" "$HYDRATE_Q")" || continue
    if echo "$HYDR" | jq -e '.errors' >/dev/null 2>&1; then continue; fi
    if ! echo "$HYDR" | jq -e '.data.projectsByIds' >/dev/null 2>&1; then continue; fi

    # header counters (non-deleted envs + non-deleted service instances)
    TOT=$((TOT + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null)] | length')))
    OKC=$((OKC + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null and .latestDeployment != null and .latestDeployment.status == "SUCCESS")] | length')))
    BADC=$((BADC + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null and (.latestDeployment == null or (.latestDeployment.status != "SUCCESS" and .latestDeployment.status != "BUILDING" and .latestDeployment.status != "DEPLOYING" and .latestDeployment.status != "QUEUED" and .latestDeployment.status != "WAITING" and .latestDeployment.status != "INITIALIZING")))] | length')))
    NEVERC=$((NEVERC + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null and .latestDeployment == null)] | length')))
    PROJC=$((PROJC + $(echo "$HYDR" | jq '.data.projectsByIds | length')))

    echo "$HYDR" | jq -r --argjson base "$BASE" --argjson n "$N" \
      '.data.projectsByIds[] | '"$RENDER_FILTER" >>"$TMPBODY"
  done
done < <(echo "$WS_LIST_JSON" | jq -c '.[]')

BUSYC=$((TOT - OKC - BADC - NEVERC))

# ---------- output ----------
# header (menu bar): just the Railway icon when everything is running;
# error icon + failing count when anything is failed / not running.
if [ "$BADC" -gt 0 ]; then
  HEAD=":exclamationmark.triangle: ${BADC}"
else
  HEAD=":${ICON}:"
fi
echo "${HEAD} | symbolize=true emojize=false dropdown=false"
echo "---"
# Dynamic workspace switcher: fresh list every run. Each item invokes this
# script via `bash=` (self-invocation, see select-workspace handler above)
# with refresh=true terminal=false - clickable on all SwiftBar versions.
if [ -n "$PIN" ]; then CUR_LABEL="$(echo "$PINNED_WS_NAME" | tr '\n' ' ' | tr '|' '-')"; ALL_SEL=""; else CUR_LABEL="All"; ALL_SEL=" checked=true"; fi
echo "Workspace: ${CUR_LABEL} | sfimage=building.2"
echo "--All workspaces | bash=\"${PLUGIN_PATH}\" param1=select-workspace param2=ALL refresh=true terminal=false${ALL_SEL} sfimage=building.2"
echo "$ME_JSON" | jq -r --arg pin "$PIN" --arg plug "$PLUGIN_PATH" '
  .data.me.workspaces[]
  | (.name | gsub("\n";" ") | gsub("\\|";"-")) as $safe
  | (if .id == $pin or .name == $pin then " checked=true" else "" end) as $sel
  | "--\($safe) | bash=\"\($plug)\" param1=select-workspace param2=\(.id) refresh=true terminal=false\($sel) sfimage=building.2"'
echo "---"
cat "$TMPBODY"
echo "---"
if [ -n "$PIN" ]; then
  echo "workspace: ${PINNED_WS_NAME} · ${PROJC} projects · N=${N} deploys/svc | size=11 symbolize=false"
else
  echo "${PROJC} projects · N=${N} deploys/svc | size=11 symbolize=false"
fi
echo "Refresh | refresh=true sfimage=arrow.clockwise size=11"
echo "Open Railway dashboard | href=https://railway.com/dashboard sfimage=${ICON} size=11"
