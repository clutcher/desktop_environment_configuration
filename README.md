# Description

Set of configs and install scripts to set up a desktop environment. These scripts are designed to be executed on a fresh core
Debian installation (no environments checkboxes during installation).

### What it installs

+ SDDM as login manager
+ KDE Plasma 6 on Wayland, with Krohnkite for dynamic tiling
+ Tags, hotkeys and panel arranged the way the Awesome window manager was configured before
+ Tools to work with hardware (network, bluetooth, sound)
+ Minimal set of KDE based applications
+ Configuration of backlight
+ Installation of various dev tools (IntelliJ IDEA, Java/sdkman, NodeJS/nvm, Docker etc.)
+ Installation of Obsidian and Insync

P.S. Be careful with configure_global_settings.sh - it sets the global git user to my personal email.

### Claude Code profiles

`scripts/setup_claude_profiles.sh` deploys `configs/claude/` to `~/.claude-shared`: `settings.json` as the shared base `settings.base.json`, the status line, the commit hook, and `CLAUDE.md` with a snapshot in `~/.claude-shared/.deployed/` so a later run can tell edits made by Claude from edits made in the repo.
Run `claude-settings-diff` to see drift, or `claude-settings-diff -d` to see the diffs, then fold accepted changes back into the repo.
Claude Code profiles live in `~/.claude-<name>` with their own login and their own `settings.json`; `~/.claude` is retired and `dotfiles/plasma-workspace/env/20-claude.sh` points graphical launchers at `~/.claude-personal`.
Every `claude -pf <name>` launch runs `claude-profile-prepare --check --no-plugins <name>`, which compares the profile's `settings.json` with the base and prints one line when they deviate; `claude-profile-prepare --fix <name>` (with that profile's claude stopped) applies the base and installs missing plugins, and `shared-settings.ignore` in the profile lists JSON Pointers to skip.
A profile directory with a `.no-shared` file is skipped entirely, and nothing is linked for a profile without a marker in `~/.claude-shared/.relink-markers/`.
A new profile is just `claude -pf <name>` followed by `/login`, or Bedrock environment in that profile's own `settings.json` or `profile.env` (the `/setup-bedrock` wizard is fine); `profile.env` is loaded by the `claude -pf <name>` shell function for that launch only.
`install.sh` deploys the files and tooling: `source scripts/setup_claude_profiles.sh [--dry-run] deploy-files install-tooling`.

