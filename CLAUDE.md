# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A personal Debian workstation provisioner. `install.sh` turns a bare console-only Debian sid
install into a full desktop: SDDM, KDE Plasma 6 on Wayland, KWin with Krohnkite dynamic tiling,
hardware support, dev tooling and personal dotfiles.

The contract: clone the repo → `./install.sh` → reboot → log in to a finished desktop. Nothing
may require an already-running graphical session (the one exception is the panel layout, see
below). Network is assumed available throughout.

There is no build, no test suite, no lint step. The deliverable is the shell scripts plus the
config they deploy, and the only real verification is running them on a machine.

## Running the provisioner

```bash
./install.sh                            # full provisioning, from the repo root
source scripts/setup_plasma_de.sh       # re-run one stage (scripts assume repo root as CWD)
bash -n scripts/*.sh install.sh         # syntax check everything
```

`install.sh` is a flat ordered list of `source scripts/<stage>.sh`. Commented-out stages are
opt-in: the liquorix kernel and firmware-from-source.

Scripts use **relative paths** (`configs/*`, `dotfiles/*`), so they must be invoked from the
repository root. They are `source`d rather than executed, sharing one shell, and two stages rely
on that: `install_java.sh` sources sdkman and `install_nodejs.sh` sources nvm into the shell, so
`sdk` and `nvm` are callable by whatever runs after them.

Every stage is **safe to run again**, alone or as a full `./install.sh`, and a new stage must stay
that way: a rerun converges on the same result and brings fetched software up to date. The
patterns that keep it so:

- Vendor keyrings are dearmored with `gpg --batch --yes`. Without it gpg asks before overwriting
  the existing keyring, finds no tty under `sudo` and fails, so the repository loses its key.
- One-off generated secrets are guarded: `ssh-keygen` runs only when `~/.ssh/id_rsa` is missing,
  because overwriting it would orphan the key registered on remote hosts.
- Releases unpacked into `/opt` remove the previous tree first, since stale jars and plugins from an
  older IntelliJ break the new one.
- KWin scripts go through `__install_kwin_script`, which upgrades an installed package:
  `kpackagetool6 --install` fails on an existing one and `--upgrade` on a missing one.
- `setup_dotfiles.sh` deletes and re-appends its `# BEGIN desktop_environment_configuration` …
  `# END desktop_environment_configuration` block in `~/.bashrc`. Preserve that marker pattern.
- Write a deployed file whole, or edit it by key with `kwriteconfig6`, rather than appending to or
  patching it in place: a second run would apply the append or patch twice.

## Repository layout and how the pieces reach the system

| Source | Destination | Applied by |
|---|---|---|
| `dotfiles/*` | `~/.config/*` (recursive copy) | `setup_dotfiles.sh` |
| `configs/kglobalaccel/*` | `~/.local/share/kglobalaccel/` and `~/.local/share/applications/` | `setup_plasma_de.sh` |
| `configs/bin/*` | `~/.local/bin/` | `setup_plasma_de.sh` |
| `configs/konsole/*` | `~/.local/share/konsole/` | `setup_plasma_de.sh` |
| `configs/kwin/osd-top-right` | `~/.local/share/kwin/scripts/osdtopright/` | `setup_kwin_tiling.sh` |
| `configs/autostart/*` | `~/.config/autostart/` | `configure_plasma_session.sh` |
| `configs/plasma/panel-layout.js` | `~/.local/share/plasma-panel/` | `configure_plasma_session.sh` |
| `configs/wallpaper/wall.png` | `~/.local/share/wallpapers/` | `configure_plasma_session.sh` |
| `configs/udev/*` | `/etc/udev/rules.d/` | `setup_hardware_and_cli.sh` |
| `configs/sysctl/60-jetbrains.conf` | `/etc/sysctl.d/` | `install_intellij.sh` |

Because `dotfiles/` is copied wholesale into `~/.config/`, **a new directory under `dotfiles/`
deploys automatically** — no script change needed. Anything that must land outside `~/.config`
needs an explicit copy in a script. New bash modules just need the `dotfiles/bash/.bash_<name>`
naming to be picked up by the `~/.bashrc` sourcing loop.

That wholesale copy hides a second hook worth knowing about:
`dotfiles/plasma-workspace/env/10-ssh-agent.sh` lands in `~/.config/plasma-workspace/env/`, which
**Plasma sources on session start**. It is how `SSH_ASKPASS` and the ssh agent reach graphical
applications, and it is the place for any environment variable the whole session needs — a shell
module under `dotfiles/bash/` only reaches terminals.

`configure_global_settings.sh` repoints the XDG directories: DOCUMENTS at `~/projects`, PICTURES
at `~/screenshots`, DESKTOP at `$HOME`, and `user-dirs.conf` disables recreation so Music, Videos
and friends stop reappearing on login. Later stages depend on this — `setup_plasma_de.sh` writes
Spectacle's save path as `~/screenshots`.

## Plasma configuration model

Plasma is configured **surgically with `kwriteconfig6`**, never by shipping whole `kwinrc` or
`kglobalshortcutsrc` files. Those are laced with machine state (activity UUIDs,
`[Tiling][<uuid>][<uuid>]`, output config) that a wholesale copy would clobber or make
non-portable. Static files are shipped only where the file genuinely is static — the Konsole
profile and colorscheme, `.desktop` files.

`kwriteconfig6` is a plain INI writer, so every configure step works with no session and no DBus.
Two things to respect when adding stages:

- **Write for a clean install or a rerun of this repo, nothing else.** Scripts assume a
  console-only Debian, or one this repo already provisioned. No backing up existing Plasma config,
  no disabling other display managers — no foreign desktop exists on the box, and defensive
  handling for it is noise. Config is read at login, so there is also nothing to reload after
  writing it; a rerun takes effect at the next login.
- **`libkf6config-bin` provides `kwriteconfig6`** and is installed first in `setup_plasma_de.sh`.
  Other tools: `kbuildsycoca6` → `libkf6service-bin`, `kpackagetool6` (own package),
  `qdbus6` → `qdbus-qt6`. No metapackages (`kde-full`, `kde-standard`) — the package list is
  explicit and deliberate.

The login screen is the one piece of Plasma config that does not live under `~/.config`. Sddm
reads it as its own user, so the wallpaper is copied to `/usr/share/wallpapers/` and the
background is written into `/usr/share/sddm/themes/breeze/theme.conf`. That file is not a dpkg
conffile and this sddm build has no `theme.conf.user` override, so an `sddm-theme-breeze` upgrade
silently resets it — re-run the stage. Debian's `debian-theme` is an alternatives symlink onto
`breeze`, so there is no `[Theme] Current` to set.

Dolphin's per folder view (`~/Downloads/.directory`) carries a far future `Timestamp` on purpose.
On its first run Dolphin sets `[General] ViewPropsTimestamp` to the current time, and
`ViewProperties` treats any folder view older than that as stale and replaces it with defaults —
for Downloads, grouped and folders mixed in. Presetting `[General] Version` to skip that first run
is not an option: the same check is what adds the hamburger menu to the toolbar, and with the
menubar off Dolphin would be left with no menu. Dolphin moves the file into the folder's
`user.kde.fm.viewproperties#1` xattr the first time it saves a view there.

The four Plasma stages, in order:

| Script | Responsibility |
|---|---|
| `setup_plasma_de.sh` | Packages, SDDM and its login theme, powerdevil, kwallet and PAM, mime defaults, theme, keyboard, lock screen, Spectacle, Konsole, KRunner |
| `setup_kwin_tiling.sh` | Krohnkite install, 5 Greek-named desktops, KWin window behaviour |
| `configure_plasma_shortcuts.sh` | The full hotkey map into `kglobalshortcutsrc` |
| `configure_plasma_session.sh` | Autostart entries and the deferred panel build |

### Shortcuts

Custom command shortcuts (khotkeys is gone in Plasma 6) need the **same `.desktop` file in two
places**, exactly as the konsole and dolphin packages ship theirs:

- `~/.local/share/kglobalaccel/<id>.desktop` defines the shortcut, via `X-KDE-Shortcuts=<Shortcut>`.
  Without this copy kglobalaccel may not even register the component.
- `~/.local/share/applications/<id>.desktop` provides the service that the shortcut launches.
  Without this copy the key fires and the launch fails.

A `[services][<id>]` entry that matches the `.desktop`'s own `X-KDE-Shortcuts` is a default, so
kglobalaccel drops it the next time it rewrites `kglobalshortcutsrc` — the key still works. Audit
these against kglobalaccel, not against the file.

Run `kbuildsycoca6` after adding one so the service cache picks it up. KRunner needs no entry of
its own: it ships `/usr/share/kglobalaccel/org.kde.krunner.desktop` and is `DBusActivatable`, so
binding `[services][org.kde.krunner.desktop]` is enough.

**`[services]` groups use a different value format from component groups.** A component group
(`[kwin]`, `[ksmserver]`) stores `shortcut,default,name`. A services group stores a bare
tab-separated key list and nothing else:

    [services][terminal.desktop]
    _launch=Meta+Return

Writing the three-field form there produces `_launch=Meta+Return, ,\s`, which kglobalaccel stores
but never grabs — the key is simply dead, with no error anywhere. This is why
`configure_plasma_shortcuts.sh` has a separate `__set_service_shortcut` helper.

To check what is really bound, ask kglobalaccel by key code (Qt key plus modifier, e.g.
Meta+Return is `0x11000004` = 285212676):
`qdbus6 --literal org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.getGlobalShortcutsByKey <code>`.
An empty result means nothing holds the key, whatever the config file says.

**On Wayland a shift that xkb consumed never reaches the shortcut, but the shifted keysym does.**
`Xkb::modifiersRelevantForGlobalShortcuts` returns `mods & ~consumedMods`, and on the digit row shift
is what selects the second level (`key <AE01> { [ 1, exclam ] }`), so KWin strips it. The keysym is
still `exclam`, and `QXkbCommon::keysymToQtKey` substitutes the unshifted Latin key only
`if (!isLatin1(keysym))` — every shifted digit is Latin-1, so nothing substitutes. `Meta+Shift+1`
therefore arrives as `Meta+!`, which *is* bindable; it does not arrive as `Meta+1`. Letters go the
other way: KWin puts shift back for them (BUG 370341), which is why `Meta+Shift+H/J/K/L/C` work, and
Cyrillic keysyms are not Latin-1 so they do substitute back to the us letter — which is why those
keep working on the ru layout.

`Window to Desktop 1..5` is therefore bound to the shifted symbol of **both** configured layouts,
since us and ru disagree on the digit row (`@ $ %` against `" * :`) and Latin-1 blocks the
substitution that rescues the letters. `Meta+Ctrl+1..5` stays as a layout proof fallback. Keys whose
second level needs alt rather than shift never lose the modifier — `<PRSC>` is `PC_ALT_LEVEL2`, so
`Meta+Shift+Print` works as spelled.

The open report is <https://bugs.kde.org/show_bug.cgi?id=522619>, filed against the numpad but the
same `modifiersRelevantForGlobalShortcuts` line; watch it for a fix, and collapse the per layout
symbols back to plain `Meta+Shift+1..5` when one lands. Do not track 370341 (the letter exception,
fixed in 5.8.2) or 434988 (the KCM showing `Meta+!`), where the WONTFIX argument turns out to be
right: the binding does fire, it is just spelled by keysym and so breaks across layouts, which is
415289.

**Never make mutating DBus calls against a running session.** On Wayland `org.kde.kglobalaccel` is
owned by `kwin_wayland` itself, so `setShortcutKeys`, `doRegister` and similar go straight into the
compositor: they can kill it and take the whole session down. Read-only queries are fine; to change
shortcuts, write the config file and log in again.

This includes `setForeignShortcutKeys`, the call the shortcuts KCM itself uses, and exact `a(ai)`
marshalling through `gdbus` does not save it — it crashed `kwin_wayland` on 6.7.4. The keys did end
up bound, but only because the compositor restarted and re-read the config on the way back up. That
is a crash, not a technique for applying shortcuts without logging out.

`kwriteconfig6` parses a bare `-1` as a command line flag and fails with `Unknown option '1'`,
so a negative value needs the `--` separator before it.

Nested groups must use repeated `--group` flags (`--group services --group terminal.desktop`);
writing `"services][terminal.desktop"` escapes the brackets and silently produces a dead group.

The hotkey map reproduces the AwesomeWM bindings, so `configure_plasma_shortcuts.sh` **clears
every Krohnkite default and the colliding Plasma ones first**. A binding whose previous owner is
not cleared silently loses: the other component keeps the key. Owners found so far are
`[plasmashell]` task manager entries (`Meta+1..9`), `[kwin]` Overview / Quick Tile Left+Right /
Edit Tiles / Walk Through Windows of Current Application / Show Desktop (`Meta+D`),
`[org_kde_powerdevil] powerProfile` (`Meta+B`), and Spectacle's `RecordRegion` (`Meta+R`) and
`_launch` (`Print`).

Two of those owners never appear in `kglobalshortcutsrc` until their component has run, so
grepping the file is not enough — audit against the `X-KDE-Shortcuts` lines in
`/usr/share/kglobalaccel/*.desktop` as well.

The shortcuts settings module rewrites the whole of `kglobalshortcutsrc` from its own state
when it is opened, so edits made to the file while it is open are lost. Same for plasmashell and
`plasma-org.kde.plasma.desktop-appletsrc`. Write config, then check it survived.

On Wayland the global shortcuts server runs **inside `kwin_wayland`** (`plasma-kglobalaccel.service`
is dead), so there is no daemon to restart: shortcut changes take effect at next login.

### The config assumes three monitors

`configure_plasma_shortcuts.sh` binds `Ctrl+1/2/3` to KWin screens `1/0/2`, because KWin gives
**0 to the primary monitor** and numbers the rest by priority, while the bindings run left to
right — with the middle monitor primary, left is 1 and right is 2. `panel-layout.js` builds a
panel per screen but puts the sensors, battery, keyboard indicator and system tray on screen 0
only. Both break quietly on a different monitor count or a different primary.

### Krohnkite comes from Codeberg and needs 0.9.10 or newer

Krohnkite lives at <https://codeberg.org/anametologin/Krohnkite>; the GitHub releases stop at
0.9.9.2. Do not go back below 0.9.10: older releases read only the global `currentDesktop`, which
under `PerOutputVirtualDesktops` is the *active* output's desktop, so every other monitor found no
windows and kept a stale layout. 0.9.10 resolves each output through
`workspace.currentDesktopForScreen` (KWin 6.7 and newer).

Floating rules go in `floatConfig`, one rule per line as `classes[:title]:params`; a bare class
list floats. `floatingClass` and `floatingTitle` are still declared in `main.xml` but the script
no longer reads them, so writing them fails with no error. On a version bump, diff the
`<entry name=...>` keys of `contents/config/main.xml` and the `Krohnkite*` action names in
`contents/ui/shortcuts.qml` against what the scripts write and clear.

### A desktop switch on one monitor could drag another monitor with it

`Workspace::updateWindowVisibilityAndActivateOnDesktopChange` ends in
`activateWindowOnDesktop(newDesktop)` → `findWindowToActivateOnDesktop` →
`FocusChain::getForActivation(desktop)`. That chain is keyed by desktop alone, so with
`SeparateScreenFocus` off it returns the most recently used window on that desktop **on any
output**. `Workspace::activateWindow` then finds `!window->isOnCurrentDesktop()` and, under the
default `[Windows] ActivationDesktopPolicy=SwitchToOtherDesktop`, runs
`setCurrent(window->desktops().constLast(), window->output())` — which switches *that* monitor.

So an application with a window on desktop γ of two monitors was enough: switching the left
monitor to γ activated its window on the right one and pulled the right monitor to γ as well.
`[Windows] SeparateScreenFocus=true` adds the `window->output() == output` test to
`getForActivation` and to `isUsableFocusCandidate`, which covers the window-hidden path
(`activateNextWindow` → `nextForDesktop`) too. Its kcfg default is already `true`; the Window
Behaviour KCM writes the whole group out on exit, so the key is set explicitly rather than left
to the default.

### The active screen is not the screen under the pointer

New Wayland windows are placed on `Workspace::activeOutput()`, which follows the pointer *except*
that `Window::sendToOutput` and `switchToOutput` also set it. So after `Meta+Esc` or `Ctrl+1/2/3`
the active screen is the one just moved or switched to while the pointer sits elsewhere, and the
next launcher opens its window there. KWin 6 dropped the old `ActiveMouseScreen` option; the fix is
`[Windows] Placement=UnderMouse`, because `Placement::placeUnderMouse` resolves its screen area from
`Cursors::self()->mouse()->pos()` and ignores the active output entirely.

### The OSD is positioned by KWin, not by plasmashell

The volume/brightness popup (`org.kde.plasma.workspace.osd`) only declares the Wayland role
`role_onscreendisplay`; it never sets a position. KWin then runs `Placement::placeOnScreenDisplay()`,
which hardcodes centred at two thirds of the screen height, and there is no config key for it.

`configs/kwin/osd-top-right` is a KWin script that moves it instead. A window rule can also do
it (`types=65536` is `NET::OnScreenDisplayMask`, and `placement=PlacementNone` must be forced
too, or placement overwrites the position rule), but the rule's position is absolute: it pins the
OSD to fixed coordinates on one monitor. The script reads `clientArea` and the popup's own size,
so it follows the active screen and needs no hardcoded pixels. `frameGeometryChanged` has to be
hooked as well — the popup is resized after it is shown, once its contents are laid out.

The plugin is enabled under the `Id` from `metadata.json`, not the directory name:
`kpackagetool6` installs `configs/kwin/osd-top-right` as `~/.local/share/kwin/scripts/osdtopright`,
and the switch is `[Plugins] osdtoprightEnabled`.

### The panel is the one deferred step

The panel is built through the plasmashell scripting API
(`qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript`), which needs a
running plasmashell. Hand-editing `plasma-org.kde.plasma.desktop-appletsrc` instead is fragile —
its containments key off an activity UUID that does not exist until first login. So
`configure_plasma_session.sh` writes `~/.local/share/plasma-panel/apply-layout.sh` and a matching
autostart entry, which runs on first login and deletes that entry when it succeeds.

The generated script does three things, and the middle one carries the trap. It applies
`panel-layout.js`, retrying for a minute because plasmashell needs a moment to claim its DBus
name. Then it switches every desktop containment to `org.kde.desktopcontainment`, so the desktop
stops showing folder contents: containment type is **read only in the scripting API**, and
plasmashell rewrites `plasma-org.kde.plasma.desktop-appletsrc` from memory when it exits, so the
key is written **while `plasma-plasmashell.service` is stopped** and the service restarted
afterwards. Finally it applies the wallpaper with `plasma-apply-wallpaperimage`, once plasmashell
is back with the new containment. The desktop ids come from a second `evaluateScript` call, which
concatenates the output of every `print`, so they arrive as one space-separated line.

## Conventions

- Commit messages: `<type>(<scope>): <lowercase summary>`, e.g. `feat(configuration): ...`,
  `fix(configuration): ...`, `feat(software): ...`. Scopes in use: `configuration`, `software`,
  `hotkeys`, `linux`.
- Every shell script starts with `#!/bin/bash`.
- Scripts are grouped by prefix: `setup_*` configures a subsystem, `install_*` installs one
  product, `configure_*` adjusts settings.
- Third-party apt repos use deb822 `.sources` files with keys in `/etc/apt/keyrings/`. Do not
  reintroduce `add-apt-repository` or `/etc/apt/trusted.gpg.d/` — the legacy
  `/etc/apt/sources.list` is deliberately removed, and writing it creates duplicate sources.
  The system tracks sid, but a vendor repo pins to **the newest suite that vendor actually
  publishes**: sid where it exists (insync), otherwise the current Debian stable — `trixie` for
  docker, `debian/13` for microsoft. Check `<repo>/dists/` before assuming a suite is there;
  these two need bumping by hand when Debian releases.
- Comment style differs from the usual no-comments rule: scripts use short comments to say what
  an opaque `apt`/`kwriteconfig6`/`sed` line is for, and to preserve deliberately disabled
  alternatives. **One line each** — say why, not what. When a block needs two explanations, put
  each one next to the statement it explains instead of stacking a paragraph above them all.
- Private shell helpers are prefixed `__` and unset at the end of sourced scripts.
- `.idea/` is gitignored.

## Personal files

`dotfiles/bash/` and several scripts contain hardcoded paths, a personal email, and local
credentials for throwaway dev containers. Match the existing style rather than generalising them.
