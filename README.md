# my-swiftbar-plugins

Small menu bar plugins I actually use every day. Drop one into your plugin folder and it just shows up in the menu bar — no build step, no config files to hand-edit.

![Railway plugin menu](screenshots/railway-plugin.png)

## Compatible apps

These scripts follow the BitBar plugin format, so they work with any app that speaks it:

- **SwiftBar** (what I use) — https://github.com/swiftbar/SwiftBar / https://swiftbar.app
- **xbar** (the maintained BitBar reboot) — https://github.com/matryer/xbar / https://xbarapp.com
- **BitBar** (the original, now archived into xbar) — https://github.com/matryer/bitbar

If a plugin header says `<xbar.*>` and `<swiftbar.*>`, that's why — same script, all three apps understand it.

## What's in here

| Plugin | What it does | Refreshes every |
| --- | --- | --- |
| `github.10m.sh` | Your open GitHub issues & PRs, with review and CI state | 10 min |
| `railway.5m.sh` | Railway workspace → project → environment → service tree, with status and recent deploys (click a deploy to open its logs) | 5 min |

The refresh interval comes from the filename (`*.5m.sh` = every 5 minutes). Rename the file if you want a different cadence, e.g. `github.30m.sh`.

## Install

1. Install one of the apps above. For SwiftBar: download from [releases](https://github.com/swiftbar/SwiftBar/releases) or `brew install --cask swiftbar`.
2. Install the CLIs each plugin shells out to:
   - GitHub plugin: `brew install gh jq`, then `gh auth login`
   - Railway plugin: `brew install jq` plus the [Railway CLI](https://docs.railway.com/guides/cli), then `railway login`
3. Copy the `.sh` file(s) into your plugin folder (SwiftBar asks for this on first launch) and make them executable:
   ```sh
   chmod +x github.10m.sh railway.5m.sh
   ```
4. Hit Refresh in the menu bar. Done.

Optional but recommended: install a proportional Nerd Font so the icons render at full size (otherwise you get SF Symbols + emoji fallback, which still looks fine):

```sh
brew install --cask font-jetbrains-mono-nerd-font
```

## Settings

No need to edit the scripts. In SwiftBar go to Preferences → Plugins → pick the plugin → Variables, and change them there. They persist into a `.vars.json` sidecar next to the script (already gitignored here, so your personal values never get committed).

**GitHub (`github.10m.sh`)**

- `VAR_GH_ITEMS_COUNT` — how many issues and PRs to list each (default `10`, clamped 1–50).
- `VAR_GH_ITEMS_REPOS` — repo filter, comma-separated. `org/repo` for one repo, `org/*` for a whole org, `!` prefix to exclude. Empty = everything. Example: `railwayapp/*,!railwayapp/mono`.
- `VAR_GH_MENUBAR_STYLE` — `split` shows PR + issue counts in the menu bar, `github` shows just the GitHub mark.

**Railway (`railway.5m.sh`)**

- `VAR_RAILWAY_WORKSPACE` — pin a workspace by name or ID. Empty (or `ALL`) = all workspaces. Easiest way to set it: use the "Workspace: …" switcher inside the menu itself, it saves back here automatically.
- `VAR_RAILWAY_DEPLOY_COUNT` — recent deploys listed per service (default `10`, clamped 1–30).

Legacy `GH_MY_ITEMS_*` / `RAILWAY_*` env vars still work as a fallback if you set them via Plugin Environment, but the `VAR_*` variables above are the way to go.

## Notes

- Each plugin is deliberately a single file (even the Nerd Font detection block that's duplicated between them) so you can install just one without anything else.
- Scripts assume Homebrew paths (`/opt/homebrew/bin`, `/usr/local/bin`) — standard Homebrew installs just work.
