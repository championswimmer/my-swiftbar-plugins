#!/usr/bin/env bash
# <xbar.title>Railway</xbar.title>
# <xbar.version>v2.1</xbar.version>
# <xbar.author>championswimmer</xbar.author>
# <xbar.author.github>championswimmer</xbar.author.github>
# <xbar.desc>Workspace -> project -> environment -> service tree with current status on top and last N deploys below (click opens logs in the Railway dashboard). Volumes show size + fill. Uses the railway CLI (railway api GraphQL). Icons are Nerd Font Propo glyphs (Railway brand logo via Devicons, status via Octicons) when a Nerd Font is installed, else SF Symbols + emoji.</xbar.desc>
# <xbar.dependencies>railway,jq</xbar.dependencies>
# <xbar.abouturl>https://railway.com</xbar.abouturl>
# <swiftbar.environment>[VAR_RAILWAY_WORKSPACE=, VAR_RAILWAY_DEPLOY_COUNT=10]</swiftbar.environment>
# <xbar.var>string(VAR_RAILWAY_WORKSPACE=""): Workspace (org) to pin: name or ID. Empty (or ALL) = all workspaces; when pinned the tree starts at projects. Tip: pick from the "Workspace: ..." switcher in the menu - it saves here automatically.</xbar.var>
# <xbar.var>number(VAR_RAILWAY_DEPLOY_COUNT="10"): How many recent deploys to list per service (1-30).</xbar.var>
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
# Legacy RAILWAY_* env vars still work as fallback (e.g. via Plugin Environment).
#
# ICONS: dual set - SF Symbols (+ emoji) or Nerd Font Propo glyphs.
# A proportional ("Propo") Nerd Font is auto-detected via fc-list (mdls
# fallback); in Mono variants the icons render too small, Propo renders
# them at full size. With no Nerd Font installed, SF Symbols are used
# (top-level rows: sfimage only, inner rows may add emoji). To install one:
#   brew install --cask font-jetbrains-mono-nerd-font
# The menu bar icon is the Railway brand glyph (nf-dev-railway, Devicons
# set) under Nerd Fonts, else the train SF Symbol.

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
# 2. Nerd Font Propo glyphs (Devicons brand + Octicons sets)
# Resolved below into T_<NAME> (text prefix) + S_<NAME> (param suffix),
# so every bash output line is simply: "${T_FOO}text | ...${S_FOO} ..."
# (the jq renderer uses the G_JSON/S_JSON/E_JSON maps instead).
SF_RAILWAY="train.side.front.car";  NF_RAILWAY="$(printf '\xee\xa2\x83')"  # U+E883 dev: railway (brand)
SF_ORG="building.2";                NF_ORG="$(printf '\xef\x90\xab')"      # U+F42B organization
SF_PROJECT="rectangle.stack";       NF_PROJECT="$(printf '\xef\x94\x82')"  # U+F502 project
SF_ENV="globe";                     NF_ENV="$(printf '\xef\x92\x84')"      # U+F484 globe-ish
SF_SERVICE="server.rack";           NF_SERVICE="$(printf '\xef\x91\xb3')"  # U+F473 server-ish
SF_VOLHDR="internaldrive";          NF_VOLHDR="$(printf '\xef\x91\xb2')"   # U+F472 database-ish
SF_VOL="internaldrive";             NF_VOL="$(printf '\xef\x91\xb2')"      # U+F472 database-ish
SF_NEVER="minus.circle";            NF_NEVER="$(printf '\xef\x91\xa8')"    # U+F468 dash
SF_SUCCESS="checkmark.circle";      NF_SUCCESS="$(printf '\xef\x92\xa4')"  # U+F4A4 success-ish
SF_FAILED="xmark.circle";           NF_FAILED="$(printf '\xef\x94\xb0')"   # U+F530 failed-ish
SF_BUILDING="arrow.triangle.2.circlepath"; NF_BUILDING="$(printf '\xef\x90\xa7')" # U+F427 build-ish
SF_QUEUED="hourglass";              NF_QUEUED="$(printf '\xef\x90\xba')"    # U+F43A queued-ish
SF_SLEEPING="moon.zzz";             NF_SLEEPING="$(printf '\xef\x93\xae')" # U+F4EE sleeping-ish
SF_REMOVED="minus.circle";          NF_REMOVED="$(printf '\xef\x91\xa8')"  # U+F468 dash
SF_UNKNOWN="exclamationmark.circle"; NF_UNKNOWN="$(printf '\xef\x90\xa1')" # U+F421 alert
SF_ERR="exclamationmark.triangle";  NF_ERR="$(printf '\xef\x90\xa1')"      # U+F421 alert
SF_AUTH="person.badge.key";         NF_AUTH="$(printf '\xef\x90\x95')"     # U+F415 person
SF_REFRESH="arrow.clockwise";       NF_REFRESH="$(printf '\xef\x91\xaa')"  # U+F46A sync
EMOJI_VOL="💾"
EMOJI_SUCCESS="✅"; EMOJI_FAILED="❌"; EMOJI_BUILDING="🔨"; EMOJI_QUEUED="⏳"
EMOJI_SLEEPING="💤"; EMOJI_REMOVED="➖"; EMOJI_UNKNOWN="🟣"

if [ "$HAVE_NF" -eq 1 ]; then
  T_RAILWAY="$NF_RAILWAY ";   S_RAILWAY=" font=\"$NF_FONT\""
  T_ORG="$NF_ORG ";           S_ORG=" font=\"$NF_FONT\""
  T_PROJECT="$NF_PROJECT ";   S_PROJECT=" font=\"$NF_FONT\""
  T_ENV="$NF_ENV ";           S_ENV=" font=\"$NF_FONT\""
  T_SERVICE="$NF_SERVICE ";   S_SERVICE=" font=\"$NF_FONT\""
  T_VOLHDR="$NF_VOLHDR ";     S_VOLHDR=" font=\"$NF_FONT\""
  T_VOL="$NF_VOL ";           S_VOL=" font=\"$NF_FONT\""
  T_NEVER="$NF_NEVER ";       S_NEVER=" font=\"$NF_FONT\""
  T_SUCCESS="$NF_SUCCESS ";   S_SUCCESS=" font=\"$NF_FONT\""
  T_FAILED="$NF_FAILED ";     S_FAILED=" font=\"$NF_FONT\""
  T_BUILDING="$NF_BUILDING "; S_BUILDING=" font=\"$NF_FONT\""
  T_QUEUED="$NF_QUEUED ";     S_QUEUED=" font=\"$NF_FONT\""
  T_SLEEPING="$NF_SLEEPING "; S_SLEEPING=" font=\"$NF_FONT\""
  T_REMOVED="$NF_REMOVED ";   S_REMOVED=" font=\"$NF_FONT\""
  T_UNKNOWN="$NF_UNKNOWN ";   S_UNKNOWN=" font=\"$NF_FONT\""
  T_ERR="$NF_ERR ";           S_ERR=" font=\"$NF_FONT\""
  T_AUTH="$NF_AUTH ";         S_AUTH=" font=\"$NF_FONT\""
  T_REFRESH="$NF_REFRESH ";   S_REFRESH=" font=\"$NF_FONT\""
else
  # top-level rows: sfimage only (no emoji); inner rows may add emoji
  T_RAILWAY="";               S_RAILWAY=" sfimage=$SF_RAILWAY"
  T_ORG="";                   S_ORG=" sfimage=$SF_ORG"
  T_PROJECT="";               S_PROJECT=" sfimage=$SF_PROJECT"
  T_ENV="";                   S_ENV=" sfimage=$SF_ENV"
  T_SERVICE="";               S_SERVICE=" sfimage=$SF_SERVICE"
  T_VOLHDR="";                S_VOLHDR=" sfimage=$SF_VOLHDR"
  T_VOL="$EMOJI_VOL ";        S_VOL=" sfimage=$SF_VOL"
  T_NEVER="";                 S_NEVER=" sfimage=$SF_NEVER"
  T_SUCCESS="$EMOJI_SUCCESS ";   S_SUCCESS=" sfimage=$SF_SUCCESS"
  T_FAILED="$EMOJI_FAILED ";     S_FAILED=" sfimage=$SF_FAILED"
  T_BUILDING="$EMOJI_BUILDING "; S_BUILDING=" sfimage=$SF_BUILDING"
  T_QUEUED="$EMOJI_QUEUED ";     S_QUEUED=" sfimage=$SF_QUEUED"
  T_SLEEPING="$EMOJI_SLEEPING "; S_SLEEPING=" sfimage=$SF_SLEEPING"
  T_REMOVED="$EMOJI_REMOVED ";   S_REMOVED=" sfimage=$SF_REMOVED"
  T_UNKNOWN="$EMOJI_UNKNOWN ";   S_UNKNOWN=" sfimage=$SF_UNKNOWN"
  T_ERR="";                   S_ERR=" sfimage=$SF_ERR"
  T_AUTH="";                  S_AUTH=" sfimage=$SF_AUTH"
  T_REFRESH="";               S_REFRESH=" sfimage=$SF_REFRESH"
fi

# jq lookup maps for RENDER_FILTER: glyph prefix (g), param suffix (s),
# emoji prefix (e, "" for top-level rows so SF mode stays sfimage-only).
G_JSON="$(jq -n \
  --arg RAILWAY "${NF_RAILWAY} " --arg ORG "${NF_ORG} " \
  --arg PROJECT "${NF_PROJECT} " --arg ENV "${NF_ENV} " \
  --arg SERVICE "${NF_SERVICE} " --arg VOLHDR "${NF_VOLHDR} " \
  --arg VOL "${NF_VOL} " --arg NEVER "${NF_NEVER} " \
  --arg SUCCESS "${NF_SUCCESS} " --arg FAILED "${NF_FAILED} " \
  --arg BUILDING "${NF_BUILDING} " --arg QUEUED "${NF_QUEUED} " \
  --arg SLEEPING "${NF_SLEEPING} " --arg REMOVED "${NF_REMOVED} " \
  --arg UNKNOWN "${NF_UNKNOWN} " \
  '$ARGS.named')"
S_JSON="$(jq -n \
  --arg RAILWAY " sfimage=$SF_RAILWAY" --arg ORG " sfimage=$SF_ORG" \
  --arg PROJECT " sfimage=$SF_PROJECT" --arg ENV " sfimage=$SF_ENV" \
  --arg SERVICE " sfimage=$SF_SERVICE" --arg VOLHDR " sfimage=$SF_VOLHDR" \
  --arg VOL " sfimage=$SF_VOL" --arg NEVER " sfimage=$SF_NEVER" \
  --arg SUCCESS " sfimage=$SF_SUCCESS" --arg FAILED " sfimage=$SF_FAILED" \
  --arg BUILDING " sfimage=$SF_BUILDING" --arg QUEUED " sfimage=$SF_QUEUED" \
  --arg SLEEPING " sfimage=$SF_SLEEPING" --arg REMOVED " sfimage=$SF_REMOVED" \
  --arg UNKNOWN " sfimage=$SF_UNKNOWN" \
  '$ARGS.named')"
E_JSON="$(jq -n \
  --arg RAILWAY "" --arg ORG "" --arg PROJECT "" --arg ENV "" \
  --arg SERVICE "" --arg VOLHDR "" --arg VOL "$EMOJI_VOL " --arg NEVER "" \
  --arg SUCCESS "$EMOJI_SUCCESS " --arg FAILED "$EMOJI_FAILED " \
  --arg BUILDING "$EMOJI_BUILDING " --arg QUEUED "$EMOJI_QUEUED " \
  --arg SLEEPING "$EMOJI_SLEEPING " --arg REMOVED "$EMOJI_REMOVED " \
  --arg UNKNOWN "$EMOJI_UNKNOWN " \
  '$ARGS.named')"

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
# e.g. railway.5m.sh -> railway.5m.vars.json
VARS_FILE="${PLUGIN_PATH%.*}.vars.json"
N="${VAR_RAILWAY_DEPLOY_COUNT:-${RAILWAY_DEPLOY_COUNT:-10}}"

# validate N (default 10, clamp 1..30)
if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 1 ]; then N=10; fi
if [ "$N" -gt 30 ]; then N=30; fi

# ---------- preconditions ----------
if ! command -v railway >/dev/null 2>&1; then
  echo "${T_ERR}no railway |${S_ERR}"
  echo "---"
  echo "railway CLI not found"
  echo "Install it: brew install railway | href=https://docs.railway.com/cli/installation"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "${T_ERR}no jq |${S_ERR}"
  echo "---"
  echo "jq not found"
  echo "Install it: brew install jq | href=https://jqlang.github.io/jq/"
  exit 0
fi
if ! railway whoami >/dev/null 2>&1; then
  echo "${T_AUTH}railway login |${S_AUTH}"
  echo "---"
  echo "railway is not authenticated"
  echo "Run 'railway login' in a terminal, then refresh"
  exit 0
fi

fail_dropdown() { # $1 = message
  echo "${T_ERR}railway error |${S_ERR}"
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
def pp($k): (if $use_nf == 1 then $g[$k] else ($e[$k] // "") end);
def qq($k): (if $use_nf == 1 then " font=\"\($nf)\"" else $s[$k] end);
def sc($col): (if $use_nf == 1 then "" else (" sfcolor=" + $col) end);
def st($s):
  if $s == "SUCCESS" then {k:"SUCCESS", col:"#1a7f37,#3fb950"}
  elif $s == "FAILED" or $s == "CRASHED" then {k:"FAILED", col:"#cf222e,#f85149"}
  elif $s == "BUILDING" or $s == "DEPLOYING" then {k:"BUILDING", col:"#9a6700,#d29922"}
  elif $s == "QUEUED" or $s == "WAITING" or $s == "INITIALIZING" then {k:"QUEUED", col:"#9a6700,#d29922"}
  elif $s == "SLEEPING" then {k:"SLEEPING", col:"#6e7781,#8b949e"}
  elif $s == "REMOVED" or $s == "SKIPPED" or $s == "REMOVING" then {k:"REMOVED", col:"#6e7781,#8b949e"}
  else {k:"UNKNOWN", col:"#8250df,#d2a8ff"} end;

.id as $pid
| (.name | esc) as $pname
| (.deployments.edges | map(.node)) as $alldeps
| (.environments.edges | map(.node) | map(select(.deletedAt == null))) as $envs
| (pfx(0) + pp("PROJECT") + "\($pname) |" + qq("PROJECT") + " href=https://railway.com/project/\($pid)"),
  (if ($envs | length) == 0 then pfx(1) + "(no environments) | size=11 symbolize=false" else empty end),
  ($envs[] as $env
   | $env.id as $eid
   | ($env.name | esc) as $ename
   | "https://railway.com/project/\($pid)?environmentId=\($eid)" as $envurl
   | ($env.serviceInstances.edges | map(.node) | map(select(.deletedAt == null))) as $svcs
   | ($env.volumeInstances.edges | map(.node)) as $vols
   | (pfx(1) + pp("ENV") + "\($ename) |" + qq("ENV") + " href=\($envurl)"),
     ($svcs[] as $svc
      | $svc.serviceId as $sid
      | ($svc.serviceName | esc) as $sname
      | "https://railway.com/project/\($pid)/service/\($sid)?environmentId=\($eid)" as $svcurl
      | ($alldeps | map(select(.environmentId == $eid and .serviceId == $sid))
          | sort_by(.createdAt) | reverse) as $sdeps
      | ($sdeps[0:$n]) as $show
      | ($svc.latestDeployment) as $ld
      | (pfx(2) + pp("SERVICE") + "\($sname) |" + qq("SERVICE") + " href=\($svcurl)"),
        (if $ld == null then
           pfx(3) + pp("NEVER") + "Current · never deployed | href=\($svcurl) color=#6e7781,#8b949e size=12" + qq("NEVER")
         else
           ($ld.id) as $lid
           | ($ld.status) as $lst
           | ($alldeps | map(select(.id == $lid)) | .[0]) as $ldfull
           | st($lst) as $c
           | ((if $ldfull != null and ($ldfull.meta.branch // "") != ""
               then " · \($ldfull.meta.branch | tostring | esc | .[0:30])" else "" end)) as $br
           | (pfx(3) + pp($c.k) + "Current · \($lst)\($br) · \($ld.createdAt | ts) | href=\($svcurl) color=\($c.col)\(sc($c.col)) size=12" + qq($c.k))
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
         | (pfx(3) + pp($c.k) + "\($d.status)\($extra) · \($d.createdAt | ts) | href=\($durl) color=\($c.col)\(sc($c.col)) size=12" + qq($c.k) + " emojize=false")
        )
     ),
     (if ($vols | length) > 0 then
        (range(0; $vols | length) as $i
         | $vols[$i] as $v
         | (($v.volume.name // "volume") | esc) as $vname
         | ($v.sizeMB) as $size
         | (($v.currentSizeMB // 0)) as $cur
         | (if $size != null and $size > 0
            then (($cur / $size * 100) | floor) else null end) as $pct
         | (if $pct == null then {bar:"", col:"#6e7781,#8b949e"}
            elif $pct >= 90 then {bar:(("■" * (($pct / 10) | floor)) + ("□" * (10 - (($pct / 10) | floor)))), col:"#cf222e,#f85149"}
            elif $pct >= 75 then {bar:(("■" * (($pct / 10) | floor)) + ("□" * (10 - (($pct / 10) | floor)))), col:"#9a6700,#d29922"}
            else {bar:(("■" * (($pct / 10) | floor)) + ("□" * (10 - (($pct / 10) | floor)))), col:"#1a7f37,#3fb950"} end) as $vc
         | "https://railway.com/project/\($pid)/volume/\($v.volumeId)/metrics?environmentId=\($eid)" as $vurl
         | ((if ($v.mountPath // "") != "" then ($v.mountPath | esc) else "mount path unknown" end)) as $vmount
         | ((if ($v.service.name // "") != "" then ($v.service.name | esc) else "unattached" end)) as $vsvc
         | ((if $size != null
             then "\($cur | floor | hum) of \($size | hum)"
             else "usage unknown" end)) as $vuse
         | (if $i > 0 then (pfx(2) + " ---") else empty end),
           (pfx(2) + pp("VOL") + "\($vname) | href=\($vurl) size=12" + qq("VOL")),
           (if $size != null
             then (pfx(3) + "Used · \($vuse) | href=\($vurl) size=11 symbolize=false"),
               (pfx(3) + "Fill · \($pct)% \($vc.bar) | href=\($vurl) color=\($vc.col) size=11 symbolize=false")
             else (pfx(3) + "Usage unknown | href=\($vurl) color=#6e7781,#8b949e size=11 symbolize=false") end),
           (pfx(3) + "Mounted at · \($vmount) | href=\($vurl) size=11 symbolize=false"),
           (pfx(3) + "Service · \($vsvc) | href=\($vurl) size=11 symbolize=false"),
           (if ($v.state // "") != "" then pfx(3) + "State · \($v.state | esc) | href=\($vurl) size=11 symbolize=false" else empty end)
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
    { echo "--${T_ERR}${WSNAME} (projects query failed) |${S_ERR}" >>"$TMPBODY"; continue; }
  if echo "$PROJ_JSON" | jq -e '.errors' >/dev/null 2>&1; then
    echo "--${T_ERR}${WSNAME} ($(echo "$PROJ_JSON" | jq -r '.errors[0].message' | cut -c1-60)) |${S_ERR}" >>"$TMPBODY"
    continue
  fi
  IDS_JSON="$(echo "$PROJ_JSON" | jq -c '[.data.projects.edges[].node.id]')"
  NUM="$(echo "$IDS_JSON" | jq 'length')"

  if [ -z "$PIN" ]; then
    SAFE_WS="$(echo "$WSNAME" | tr '\n' ' ' | tr '|' '-')"
    echo "${T_ORG}${SAFE_WS} (${NUM}) |${S_ORG} href=${WSURL}" >>"$TMPBODY"
  fi
  if [ "$NUM" -eq 0 ]; then
    if [ -n "$PIN" ]; then echo "(no projects in ${PINNED_WS_NAME}) | size=11 symbolize=false" >>"$TMPBODY";
    else echo "--(no projects) | size=11 symbolize=false" >>"$TMPBODY"; fi
    continue
  fi

  # hydrate in chunks of 10 project ids
  # (process substitution, NOT a pipe - a pipe would run the loop in a
  #  subshell and the TOT/OKC/BADC/... counter increments would be lost)
  while read -r CHUNK; do
    HYDR="$(railway_api --variables "{\"ids\":$CHUNK}" "$HYDRATE_Q")" || continue
    if echo "$HYDR" | jq -e '.errors' >/dev/null 2>&1; then continue; fi
    if ! echo "$HYDR" | jq -e '.data.projectsByIds' >/dev/null 2>&1; then continue; fi

    # header counters (non-deleted envs + non-deleted service instances)
    TOT=$((TOT + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null)] | length')))
    OKC=$((OKC + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null and .latestDeployment != null and .latestDeployment.status == "SUCCESS")] | length')))
    # BADC = actually failing (FAILED/CRASHED) - REMOVED etc. don't badge the menubar
    BADC=$((BADC + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null and .latestDeployment != null and (.latestDeployment.status == "FAILED" or .latestDeployment.status == "CRASHED"))] | length')))
    NEVERC=$((NEVERC + $(echo "$HYDR" | jq '[.data.projectsByIds[] | .environments.edges[].node | select(.deletedAt == null) | .serviceInstances.edges[].node | select(.deletedAt == null and .latestDeployment == null)] | length')))
    PROJC=$((PROJC + $(echo "$HYDR" | jq '.data.projectsByIds | length')))

    echo "$HYDR" | jq -r --argjson base "$BASE" --argjson n "$N" --arg nf "$NF_FONT" --argjson use_nf "$HAVE_NF" --argjson g "$G_JSON" --argjson s "$S_JSON" --argjson e "$E_JSON" \
      '.data.projectsByIds[] | '"$RENDER_FILTER" >>"$TMPBODY"
  done < <(echo "$IDS_JSON" | jq -c 'range(0; length; 10) as $i | .[$i:$i+10]')
done < <(echo "$WS_LIST_JSON" | jq -c '.[]')

BUSYC=$((TOT - OKC - BADC - NEVERC))

# ---------- output ----------
# header (menu bar): monochrome. Always the Railway brand glyph; when
# anything is failing the alert glyph + failing count is appended after it.
# Nerd Font mode uses glyphs; SF mode uses inline :symbol: names
# (symbolize=true). dropdown=false keeps the header out of the dropdown itself.
if [ "$BADC" -gt 0 ]; then
  if [ "$HAVE_NF" -eq 1 ]; then
    HEAD="${NF_RAILWAY} ${NF_ERR} ${BADC}"; HEAD_P=" font=\"${NF_FONT}\" size=16 emojize=false dropdown=false"
  else
    HEAD=":${SF_RAILWAY}: :${SF_ERR}: ${BADC}"; HEAD_P=" symbolize=true emojize=false dropdown=false"
  fi
else
  if [ "$HAVE_NF" -eq 1 ]; then
    HEAD="${NF_RAILWAY}"; HEAD_P=" font=\"${NF_FONT}\" size=16 emojize=false dropdown=false"
  else
    HEAD=":${SF_RAILWAY}:"; HEAD_P=" symbolize=true emojize=false dropdown=false"
  fi
fi
echo "${HEAD} |${HEAD_P}"
echo "---"
# Dynamic workspace switcher: fresh list every run. Each item invokes this
# script via `bash=` (self-invocation, see select-workspace handler above)
# with refresh=true terminal=false - clickable on all SwiftBar versions.
if [ -n "$PIN" ]; then CUR_LABEL="$(echo "$PINNED_WS_NAME" | tr '\n' ' ' | tr '|' '-')"; ALL_SEL=""; else CUR_LABEL="All"; ALL_SEL=" checked=true"; fi
echo "${T_ORG}Workspace: ${CUR_LABEL} |${S_ORG}"
echo "--${T_ORG}All workspaces | bash=\"${PLUGIN_PATH}\" param1=select-workspace param2=ALL refresh=true terminal=false${ALL_SEL}${S_ORG}"
echo "$ME_JSON" | jq -r --arg pin "$PIN" --arg plug "$PLUGIN_PATH" --arg org_p "$T_ORG" --arg org_q "$S_ORG" '
  .data.me.workspaces[]
  | (.name | gsub("\n";" ") | gsub("\\|";"-")) as $safe
  | (if .id == $pin or .name == $pin then " checked=true" else "" end) as $sel
  | "--\($org_p)\($safe) | bash=\"\($plug)\" param1=select-workspace param2=\(.id) refresh=true terminal=false\($sel)\($org_q)"'
echo "---"
cat "$TMPBODY"
echo "---"
# Footer stats: keep top-level lines short; counts live in submenus.
# sfcolor only applies in SF mode (NF mode uses font= + color= like the jq rows).
if [ "$HAVE_NF" -eq 1 ]; then
  SC_OK=""; SC_BAD=""; SC_BUSY=""; SC_GRAY=""; SC_PURPLE=""
else
  SC_OK=" sfcolor=#1a7f37,#3fb950"; SC_BAD=" sfcolor=#cf222e,#f85149"
  SC_BUSY=" sfcolor=#9a6700,#d29922"; SC_GRAY=" sfcolor=#6e7781,#8b949e"
  SC_PURPLE=" sfcolor=#8250df,#d2a8ff"
fi
if [ -n "$PIN" ]; then
  WS_LABEL="$(echo "$PINNED_WS_NAME" | tr '\n' ' ' | tr '|' '-')"
  echo "Workspace: ${WS_LABEL} | size=11 symbolize=false"
else
  echo "All workspaces | size=11 symbolize=false"
fi
echo "--Projects: ${PROJC} | size=11 symbolize=false"
echo "--Services: ${TOT} | size=11 symbolize=false"
echo "----${T_SUCCESS}Healthy: ${OKC} | size=11${S_SUCCESS} color=#1a7f37,#3fb950${SC_OK}"
echo "----${T_FAILED}Failing: ${BADC} | size=11${S_FAILED} color=#cf222e,#f85149${SC_BAD}"
echo "----${T_BUILDING}Busy/other: ${BUSYC} | size=11${S_BUILDING} color=#9a6700,#d29922${SC_BUSY}"
echo "----${T_NEVER}Never deployed: ${NEVERC} | size=11${S_NEVER} color=#6e7781,#8b949e${SC_GRAY}"
echo "--Deploys: last ${N} per service | size=11 symbolize=false"
echo "Legend | size=11 symbolize=false"
echo "--${T_SUCCESS}SUCCESS · healthy | size=11${S_SUCCESS} color=#1a7f37,#3fb950${SC_OK}"
echo "--${T_FAILED}FAILED / CRASHED · failing | size=11${S_FAILED} color=#cf222e,#f85149${SC_BAD}"
echo "--${T_BUILDING}BUILDING / DEPLOYING | size=11${S_BUILDING} color=#9a6700,#d29922${SC_BUSY}"
echo "--${T_QUEUED}QUEUED / WAITING | size=11${S_QUEUED} color=#9a6700,#d29922${SC_BUSY}"
echo "--${T_SLEEPING}SLEEPING | size=11${S_SLEEPING} color=#6e7781,#8b949e${SC_GRAY}"
echo "--${T_REMOVED}REMOVED / SKIPPED | size=11${S_REMOVED} color=#6e7781,#8b949e${SC_GRAY}"
echo "--${T_UNKNOWN}other states | size=11${S_UNKNOWN} color=#8250df,#d2a8ff${SC_PURPLE}"
echo "--${T_NEVER}never deployed | size=11${S_NEVER} color=#6e7781,#8b949e${SC_GRAY}"
echo "${T_REFRESH}Refresh | refresh=true size=11${S_REFRESH}"
echo "${T_RAILWAY}Open Railway dashboard | href=https://railway.com/dashboard size=11${S_RAILWAY}"
