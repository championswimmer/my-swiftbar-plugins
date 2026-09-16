# AGENTS.md

This repo holds personal **SwiftBar plugins** (executable scripts that print menu-bar output to stdout).

## Compatibility

All plugins follow the **BitBar plugin format**, so the same script runs unmodified on:

- **SwiftBar** (primary target here)
- **xbar** (maintained BitBar reboot)
- **BitBar** (original, archived)

That is why script headers carry both `<xbar.*>` and `<swiftbar.*>` metadata tags.

## Repo conventions (must follow)

- **One plugin = one self-contained file.** Users install a single `.sh`; never split shared code into extra files. The Nerd Font detection block is intentionally duplicated between `github.10m.sh` and `railway.5m.sh` — keep the copies in sync when editing.
- **Filename sets refresh:** `{name}.{interval}.{ext}`, e.g. `github.10m.sh` (see README for rename-to-change-cadence).
- **Metadata:** keep `<xbar.title/version/author/author.github/desc/dependencies/abouturl>` current; version as `vN.N`.
- **Config = `<xbar.var>` only.** New settings go in as `VAR_*` metadata tags (surface in SwiftBar Preferences → Plugins → Variables). Values persist to a `.vars.json` sidecar that is gitignored — never commit personal values. Legacy env fallbacks exist; don't add new ones.
- **Scripts must stay executable** (`chmod +x`), `#!/usr/bin/env bash`, `set -u`, and prepend Homebrew paths (`/opt/homebrew/bin:/usr/local/bin`) to `PATH`.
- **Errors → stderr, menu output → stdout.** Test with `./github.10m.sh` / `./railway.5m.sh` before committing.

For user-facing install/settings/screenshots, see `README.md` — don't duplicate it here.

## Reference docs (read before writing plugin code)

- SwiftBar plugin API (output format, params, metadata, plugin types, URL scheme): https://github.com/swiftbar/SwiftBar#readme
- Plugin examples: https://github.com/swiftbar/swiftbar-plugins
- xbar docs (writing plugins, parameters, metadata, advanced APIs): https://xbarapp.com/docs/index.html
- xbar plugin metadata + variables spec: https://github.com/matryer/xbar-plugins/blob/main/CONTRIBUTING.md
- Variables in xbar (`<xbar.var>` types, sidecar JSON): https://xbarapp.com/docs/2021/03/14/variables-in-xbar.html
- Upgrading legacy BitBar plugins (`<bitbar.*>` → `<xbar.*>`, `bash` → `shell`): https://xbarapp.com/docs/2021/03/13/upgrade-legacy-bitbar-plugins.html
