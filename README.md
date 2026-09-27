# Mullvad VPN Omarchy widget

Bar widget and popup panel for [Mullvad VPN](https://mullvad.net), driven by the `mullvad` CLI.

The panel shows your exit location and an on/off switch, connection details (hidden by
default), a searchable location picker, account expiry, and toggles for lockdown mode,
auto-connect, and LAN sharing.

## Install

Needs [Bun](https://bun.sh) and a running `omarchy-shell`:

```bash
bun mullvad-plugin install     # safe to re-run
bun mullvad-plugin reinstall   # load code changes (restarts the shell)
bun mullvad-plugin uninstall
bun mullvad-plugin status
```

## Usage

Left click opens the panel, right click connects or disconnects, and middle click reconnects.
In the panel, use `j`/`k` to move, `enter` to activate, `s` to search locations, and `i` to
show or hide connection details.

Call the widget from the command line with `run`:

```bash
bun mullvad-plugin run          # list methods
bun mullvad-plugin run status
bun mullvad-plugin run connect | disconnect | reconnect | toggleDetails
```

## Tests

```bash
bun run test
```
