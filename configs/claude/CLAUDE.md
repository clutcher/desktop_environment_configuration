# Global instructions

## Code

- Load laminar:code-style before writing or changing code.
- Write markdown files with each paragraph and each list item on one line and no manual line breaks.

## Commits

- Separate commits by concern.
- Fold a fix of your own earlier commit into that commit instead of adding a fix-the-fix commit.
- Split or rewrite existing commits only after the user approves.
- A repository's own stricter rule, such as a mandatory ticket scope, also applies.
- A title alone is the normal case; a body states a non-obvious why, never what.
- A hook checks the format and attribution trailers on every commit.

## Claude profiles

- Each profile lives under ~/.claude-<name> with its own login and its own real settings.json.
- The shared store is ~/.claude-shared; projects, history, CLAUDE.md, skills, agents, commands, file-history and paste-cache of a shared profile are links into it, but settings.json is not shared.
- configs/claude/settings.json in the desktop_environment_configuration repo is the shared base, deployed to ~/.claude-shared/settings.base.json by scripts/setup_claude_profiles.sh deploy-files; edit this file, the status line and the hooks in the repo under configs/claude and deploy them; claude-settings-diff shows drift.
- Every claude -pf launch runs claude-profile-prepare --check, which prints one line when the profile's settings.json deviates from the base; run claude-profile-prepare --fix PROFILE with that profile's claude stopped to apply the base and install missing plugins.
- The profile may have any extra keys; list base key paths it must not follow as JSON Pointers, one per line, in ~/.claude-<name>/shared-settings.ignore.
- A profile directory with a .no-shared file is left alone by claude-profile-prepare; links are created only for profiles with a marker in ~/.claude-shared/.relink-markers.
- Put environment that belongs to one profile in ~/.claude-<name>/profile.env or in that profile's own settings.json; the claude shell function loads profile.env for that launch only.
- A new profile is just claude -pf NAME followed by /login, or Bedrock environment in its own settings.json or profile.env; the Bedrock wizard (/setup-bedrock) is fine because settings are per profile.
- A profile created later is brought into the shared store with share-profile.sh PROFILE of the migration folder after its first launch, not by the claude function.
