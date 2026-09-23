# Omarchy Window Switcher

https://github.com/user-attachments/assets/9a04ea39-e196-45a8-99f9-1de1ed632013

A zero-configuration Omarchy Quattro plugin that combines visual window
switching from Orbit with live workspace previews from Overview Workspaces.

## Features

- `Alt+Tab` — open Orbit and move to the next window.
- `Alt+Shift+Tab` — move to the previous window.
- `Super+Tab` — open the live workspace overview across all monitors, prioritizing occupied current and previous workspaces and placing empty workspaces last.
- `Super+Shift+Tab` — move backward through workspaces.
- Release `Alt` or `Super` to activate the selected window or workspace.
- Live workspace thumbnails, workspace drag-and-drop, and the Overview
  Workspaces bar widget.
- System-native `Super+1` through `Super+0` workspace bindings remain intact.
- Pressing and releasing `Super` by itself does not open the overview.

No edits to `~/.config/hypr/bindings.lua` or
`~/.config/omarchy/shell.json` are required.

## Install

```bash
omarchy plugin add https://github.com/manateelazycat/omarchy-window-switcher.git --enable --yes
```

The plugin replaces Omarchy's built-in workspace bar widget while enabled. It
registers its shortcuts at runtime and reinstalls them after a Hyprland config
reload.

If Orbit or Overview Workspaces is already installed separately, disable or
remove those copies first so two plugins do not compete for the same global
shortcuts and workspace widget.

## Update

```bash
omarchy plugin update io.github.manateelazycat.window-switcher
omarchy restart shell
```

The shell restart replaces the plugin's keep-loaded shortcut service with the
updated version.

## Remove

```bash
omarchy plugin remove io.github.manateelazycat.window-switcher
```

Disabling or removing the plugin restores Omarchy's native `Alt+Tab`,
`Alt+Shift+Tab`, `Super+Tab`, and `Super+Shift+Tab` behavior.

## Development

```bash
omarchy plugin validate .
node --test tests/*.test.cjs
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
  orbit/Overlay.qml overview/Overview.qml \
  overview/KeybindingService.qml overview/bar/widget.qml
```

Plugin files hot-reload during development. Because the shortcut service uses
`keepLoaded`, restart Omarchy Shell after changing its code:

```bash
omarchy restart shell
```

## Thanks

This project exists thanks to two excellent upstream projects:

- [Orbit](https://github.com/rohan-patnaik/orbit) by Rohan Patnaik provides
  the visual `Alt+Tab` window switcher, live previews, and interaction design.
- [Overview Workspaces](https://github.com/iamcheyan/omarchy-overview-workspaces)
  by HANCORE provides live workspace previews, navigation, drag-and-drop, and
  the workspace bar widget.

Both projects are distributed under the MIT License. Their original license
texts and pinned source revisions are preserved in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
