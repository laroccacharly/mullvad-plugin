# Mullvad VPN Omarchy widget

Bar widget and popup panel for [Mullvad VPN](https://mullvad.net), built the same way as
Omarchy's first-party Tailscale widget. It gets everything from the `mullvad` CLI.

## Features

- Bar shield icon: connected, connecting, disconnected, or blocked/error (urgent color).
  The icon also turns urgent when the account is about to expire.
- Live updates from `mullvad status --json listen`, with a periodic poll as a fallback.
- Hero with the exit city and country, the relay hostname, and an on/off switch.
- **Connection**: exit IPv4/IPv6, relay, entry relay (multihop), tunnel protocol and
  endpoint, and active features such as quantum resistance or DAITA. Click a row to copy it.
- **Location**: the current relay constraint, your last three picks, and a searchable
  country/city picker built from `mullvad relay list`. Picking a location connects to it.
  **Reconnect** switches to a different server in the same location.
- **Settings**: lockdown mode, auto-connect, and local network sharing.
- **Account**: days until expiry, the device name, and a link to the account page. Also
  shows a notice when Mullvad suggests an upgrade. The account number is never read into the panel.

## Mouse

- Left click: open the panel
- Right click: connect / disconnect
- Middle click: reconnect

## Keyboard (inside the panel)

- `j` / `k` or arrows: move the cursor
- `enter` / `space`: activate the row
- `t`: connect / disconnect
- `r`: reconnect
- `c`: copy the exit IP
- `s` or `/`: open the location search (`↑`/`↓` to pick, `enter` to connect, `esc` to close)
- `tab`: switch to the next bar panel
- `esc`: close

## IPC

Call the widget's IPC through the CLI (it checks the shell is up and the widget is enabled first):

```bash
bun mullvad-plugin run                     # list the available methods
bun mullvad-plugin run toggle
bun mullvad-plugin run toggleConnection
bun mullvad-plugin run locations           # open the panel on the location search
bun mullvad-plugin run connect | disconnect | reconnect | refresh
bun mullvad-plugin run status
```

`omarchy-shell mullvad <method>` works too.

## Settings

These go inline on the widget's entry in `~/.config/omarchy/shell.json`:

| Key                  | Default | Meaning                                          |
|----------------------|---------|--------------------------------------------------|
| `refreshIntervalSec` | `30`    | Poll interval for status and settings            |
| `expiryWarningDays`  | `7`     | Turn the icon urgent this many days before expiry |
| `recentLocations`    | —       | Written by the panel; recently picked locations   |

## Install

Needs [Bun](https://bun.sh) and a running `omarchy-shell`. From this checkout:

```bash
bun mullvad-plugin install                  # link, rescan, enable (safe to re-run)
bun mullvad-plugin install --section left   # placement, used only on the first enable
bun mullvad-plugin reinstall                # load code changes (restarts the shell)
bun mullvad-plugin uninstall                # disable and unlink
bun mullvad-plugin status                   # link / enabled / shell state
```

`install` symlinks this checkout to `~/.config/omarchy/plugins/<id>`, where the id comes
from `manifest.json`. It also removes older links to this checkout that use a different
id. Run `bun link` once to get a global `mullvad-plugin` command.

The shell's file watcher doesn't follow symlinks, and IPC functions are fixed when they
first register. So edits don't hot-reload; `reinstall` restarts the shell to load them.
It keeps the widget's bar position and settings.

## Tests

The CLI parsers live in `Model.js` and don't depend on QML:

```bash
bun run test
```
