# Third-party notices

This project combines and adapts code from two MIT-licensed Omarchy plugins.

## Orbit

- Project: https://github.com/rohan-patnaik/orbit
- Author: Rohan Patnaik
- Vendored revision: `b9115759175be41b71516926037b480f92449e8f`
- License: [licenses/ORBIT-LICENSE](licenses/ORBIT-LICENSE)

The Orbit code is stored under `orbit/`. The plugin ID and shortcut setup were
adapted so Orbit can run as part of this combined plugin without requiring a
`dofile()` entry in the user's Hyprland configuration.

## Overview Workspaces

- Project: https://github.com/iamcheyan/omarchy-overview-workspaces
- Author: HANCORE
- Vendored revision: `733355994c333f8ddf155030fc9f0cb2e07a32cb`
- License: [licenses/OVERVIEW-WORKSPACES-LICENSE](licenses/OVERVIEW-WORKSPACES-LICENSE)

The Overview Workspaces code is stored under `overview/`. It defaults to
system workspace ordering, does not bind standalone Super, and shares the
combined plugin's automatic shortcut service.
