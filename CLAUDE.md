# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Quantum Shell: a Quickshell (QML) desktop shell, imported from `quantum-linux` (`packages/quantum-shell/files/quantum`) and ported to run on **Hyprland** (the upstream is Wayfire-based). This directory is the *live* config of the `dev` profile of the `caelth` profile switcher:

```
~/.config/quickshell/caelestia → ~/.local/share/cael-profiles/dev/src → ~/dev/cael-src (this repo)
```

`/etc/xdg/quickshell/caelestia` is an unrelated stock copy, only used if the `~/.config` symlink is removed. There is no build step and no test suite.

## Running / debugging

- The shell runs as `qs -c caelestia -n -d`. Quickshell watches the files and hot-reloads on save; load errors go to `qs -c caelestia log`.
- Drive features without the mouse via IPC: `qs -c caelestia ipc call shell <fn>` (e.g. `about`, `personalize`, `launcher`, `session`, `lock`), plus the other `IpcHandler` targets (`dock`, `personalize`, …). `services/Shell.qml` lists the `shell` functions.
- Keybinds are not in this repo: they live in `~/.config/hypr/variable.lua` and call `~/.local/bin/caelth ipc-if dev <args>`, which only fires when the `dev` profile is active. Window rules are in `~/.config/hypr/hyprlands/rules.lua` (all windows float at 3/4 of the screen via `size-3-4-all`; per-window overrides go after that rule).
- To try a module in isolation, make a scratch dir with symlinks to `services components modules assets` and a tiny `shell.qml` that imports `qs.services` plus the module, then `qs -p <dir>/shell.qml`. Windows open on the live desktop; verify with `grim` screenshots.

## Architecture

- `shell.qml` is the `ShellRoot`: a `Splash` first, then a `LazyLoader` builds the desktop in the background. It picks the shell *form* with `Serp.on`: Caelestial (`Bar` + `Dock` + `DashboardZone`) or Serpantium (`modules/serpantium/*`, optionally reusing `Dock`). A new top-level module needs its `import "modules/x"` and an instance in this file.
- `services/*.qml` are `pragma Singleton`s reached through `import qs.services` (`qs.` resolves to this directory). They hold all shared state:
  - `Shell`: which panel is open (`launcherOpen`, `aboutOpen`, …), `closeAll()`, and the `shell` IPC handler. Panels are mutually exclusive through `closeAll()`; windows like Personalize and About are not.
  - `Settings`: JSON-backed settings at `~/.config/quantum/settings.json` (sections `appearance`, `layout`, `dock`, `ui`, …). Writes go through `Settings.set(section, key, v)`, which runs `quantum-theme apply` to regenerate colours and config.
  - `Theme`: colours from `~/.local/state/quantum/colors.json` (hot-reloaded) plus radii, animation durations, `glassOpacity()` and `dockScale`.
  - `Wm`: windows and active window through Wayland toplevels plus `Quickshell.Hyprland`. Minimize is emulated by moving windows to `special:minimized` (`Wm.isMinimized`).
  - `SysInfo`: CPU/RAM/disk sampling that only runs while `SysInfo.active` is true; set it when showing stats and clear it on destruction.
  - `I18n`: see below.
- `components/` has the shared widgets (`Card`, `Txt`, `Icon` for Material Symbols, `PillButton`, `AppIcon`, …). Use `Card` / `Theme.glassOpacity(kind)` for translucent surfaces.
- `modules/bar/`: in the docked ("pegada") layout the top bar is `MacBar.qml`, a macOS-style menu bar (logo menu, app menu, Archivo/Edición/Ver/Ventana/Ayuda) built from `BarMenu`/`MacMenu`. Wayland apps export no menus, so items send standard shortcuts to the active window or call the Lua helpers in `~/.config/hypr/hyprlands/minimize.lua` through `hyprctl eval`. `Dock.qml` is a single fixed-height layer window whose input `mask` exposes only the bar, bubble and menu, so the transparent area doesn't eat clicks.
- `styles/*.json` are whole-desktop presets applied from Personalize → Estilos.
- `apps/taskmgr` (Quantum Task Manager; `collector.py` emits one JSON line per second) and `tools/idle` are separate Quickshell configs launched on their own, not part of `shell.qml`. `scripts/keybinds.sh` renders the `variable.lua` keybinds for the Help menu.
- `shaders/*.frag.qsb` are compiled; edit the `.frag` and regenerate the `.qsb` with `qsb`.

## i18n conventions

UI text is written in **Spanish in the QML source** and wrapped as `I18n.t("Texto en español")`; the Spanish string is the lookup key. `i18n/strings.js` holds the `en` and `vi` dictionaries: add every new string to **both**; untranslated keys fall back to the Spanish text. `i18n/i18n_extract.py extract <root>` finds unwrapped strings and `apply <root> keys.json` wraps them. Window titles matched by Hyprland rules (e.g. "Acerca de este equipo") must stay as the plain Spanish title, so don't wrap them in `I18n.t`.

## Gotchas

- Children added inside a `Section` in `Bar.qml` are re-parented into its `RowLayout` (`default property alias content: row.data`); put overlays such as a `MouseArea` outside it.
- A `PanelWindow` mask isn't recalculated when a `transform` changes; use a plain sibling `Item` that mirrors the geometry (see `cardArea` in `Dock.qml`).
- Comments are a mix of Spanish and Vietnamese (the newer ones without diacritics); follow the style of the file you edit.
