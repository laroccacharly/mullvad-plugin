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

```bash
omarchy-shell clarocca.mullvad toggle
omarchy-shell clarocca.mullvad toggleConnection
omarchy-shell clarocca.mullvad locations          # open the panel on the location search
omarchy-shell clarocca.mullvad connect | disconnect | reconnect | refresh
omarchy-shell clarocca.mullvad status
```

## Settings

These go inline on the widget's entry in `~/.config/omarchy/shell.json`:

| Key                  | Default | Meaning                                          |
|----------------------|---------|--------------------------------------------------|
| `refreshIntervalSec` | `30`    | Poll interval for status and settings            |
| `expiryWarningDays`  | `7`     | Turn the icon urgent this many days before expiry |
| `recentLocations`    | —       | Written by the panel; recently picked locations   |

## Install

```bash
ln -s ~/Work/mullvad-plugin ~/.config/omarchy/plugins/clarocca.mullvad
omarchy-shell shell rescanPlugins
omarchy plugin enable clarocca.mullvad
omarchy bar move clarocca.mullvad --section right   # optional
```

The shell's file watcher doesn't follow symlinks, so edits here don't hot-reload.
Run `omarchy restart shell` to load them. A restart is also the only way to
pick up changes to the IPC functions.

## Tests

The CLI parsers live in `Model.js` and don't depend on QML:

```bash
node test/model.test.js
```
