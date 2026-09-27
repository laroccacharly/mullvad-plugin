# Building an Omarchy shell plugin (bar widget + panel)

Lessons from building a third-party bar widget with a popup panel for
`omarchy-shell` (Quickshell). Read this before starting a new plugin.

## 1. Start from a built-in plugin, don't invent

The first-party plugins are the real documentation. Read them, never edit them:

```
$OMARCHY_PATH/shell/README.md                 # manifest schema, install, shell.json rules
$OMARCHY_PATH/shell/plugins/README.md         # catalogue of first-party plugins
$OMARCHY_PATH/shell/plugins/bar/README.md     # bar layout + widget catalogue
$OMARCHY_PATH/shell/plugins/panels/<name>/    # rich popup widgets: the templates
$OMARCHY_PATH/shell/Ui/                        # shared components (Panel, KeyboardPanel, …)
$OMARCHY_PATH/shell/services/PluginRegistry.qml  # discovery, validation, file watcher
```

(`$OMARCHY_PATH` is `~/.local/share/omarchy`, a copy of `/usr/share/omarchy`.)

Pick the built-in panel that's closest to what you're building. For anything
wrapping a CLI (status, a toggle, a list of items), `panels/tailscale/` is the
best template. `panels/dropbox/` is similar. Copy its layout:

| File              | Role                                                                 |
|-------------------|----------------------------------------------------------------------|
| `manifest.json`   | id, kinds, entry point, settings schema                              |
| `Panel.qml`       | bar button + popup panel + IPC handler + keyboard cursor             |
| `Service.qml`     | runs the CLI (`Process`), parses, holds state, exposes actions       |
| `Model.js`        | pure parsing/formatting helpers, no QML (so it's testable in node)   |
| `<Name>Icon.qml`  | optional, only when a Nerd Font glyph isn't good enough              |
| `README.md`       | features, mouse/keyboard, IPC, settings                              |

## 2. Manifest and ids

- Third-party ids use the `<username>.<name>` convention (e.g. `alice.foo`), the
  same scheme `omarchy plugin clone` uses. The directory under
  `~/.config/omarchy/plugins/` should be named after the id.
- `kinds: ["bar-widget"]` with `entryPoints.barWidget: "Panel.qml"` gives a bar
  widget that owns its popup.
- Put tunables in `barWidget.defaults` + `barWidget.schema`. The widget reads them
  from the `settings` property, which holds the fields that sit inline on its
  `shell.json` entry.
- Validate before enabling: `omarchy plugin validate <absolute-folder>`. A silent
  exit 0 means it's valid.

## 3. Dev loop: install, enable, reload

Keep the source wherever you like and symlink it in:

```bash
ln -s ~/Work/my-plugin ~/.config/omarchy/plugins/<id>
omarchy-shell shell rescanPlugins      # picks up the new manifest
omarchy plugin enable <id>             # adds it to bar.layout (defaultSection)
omarchy bar move <id> --section right  # optional placement
```

Discovery follows the symlink (`[[ -f $dir/*/manifest.json ]]`). Reloading does **not**:

- **Gotcha: no hot reload through a symlink.** The watcher is
  `inotifywait -m -r ~/.config/omarchy/plugins`, and `-r` doesn't descend into
  symlinked directories, so saving files in the real source dir fires nothing.
- **Gotcha: `rescanPlugins` doesn't reload code.** It only re-reads manifests.
- **Gotcha: recreating the symlink (`ln -sfn`) is not enough either.** It logs
  "Local plugin changed, reloading" but the running component kept the old code.
- **Gotcha: the IPC surface is frozen at first registration.** On reload, the new
  `IpcHandler` loses to the old one for the same target ("Handler was registered
  but will not be used…"), so new or renamed IPC functions only appear after a
  restart.
- **What works:** `omarchy restart shell` loads everything. The bar blinks for a
  second. Use it after every change you want to see.
- To confirm which version is loaded, list the IPC surface:
  `qs ipc -n -p "$OMARCHY_PATH/shell" show | grep -A15 "target <id>"`.
  Also check for a visible UI change you just made.

(If you develop directly inside `~/.config/omarchy/plugins/<id>/` with no symlink,
the watcher sees the saves. The IPC-freeze caveat still applies.)

## 4. Panel.qml patterns

- Root is `Panel { moduleName: "<id>"; ipcTarget: "<id>"; manageIpc: false }`, plus
  your own `IpcHandler` that includes open/close/show/hide/toggle and your actions.
  Plain function signatures with `: string` / `: void` return types.
- Bar button: `BarIconButton { text: <glyph>; dimmed: …; active: …; tooltipText: … }`.
  `active` paints it in the urgent color, `dimmed` greys it out. Convention: left
  click opens the panel, right click does the primary toggle, middle click does a
  secondary action.
- Popup: `KeyboardPanel { anchorItem: button; owner: root; bar: root.bar; open:
  root.opened; focusTarget: keyCatcher }`, with
  `contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(N))`.
  Pick a cap N big enough that the usual content doesn't scroll.
- Content: `PanelKeyCatcher` > `Flickable` > `Column`. Sections are
  `PanelSeparator` + `PanelSectionHeader { text: "UPPERCASE" }` + rows.
- Header: `PanelHero { title; meta; iconComponent; trailingControl }` with a
  `ToggleSwitch` as the trailing control. **Gotcha:** inside `trailingControl`,
  `root` resolves to the PanelHero, not your Panel. Reach panel state through a
  named wrapper item (the Tailscale widget uses `header`).
- Rows: build on `CursorSurface` (`hasCursor`, `current`, `fill`, `currentFill`)
  with a `MouseArea` that sets the cursor on hover and activates on click. For
  toggle rows, put a `ToggleSwitch { interactive: false }` inside so the row owns
  both the click and the cursor.
- Use theme tokens only: `Color.*`, `Style.font.{display,heading,body,bodySmall,caption,icon}`,
  `Style.space(n)`, `Style.spacing.{lg,xl,rowPaddingX}`, `Style.hoverFillFor/selectedFillFor`.
  Take `foreground`/`fontFamily` from `bar` when present.
- `onOpenedChanged: if (opened) { refresh; reset cursor; Qt.callLater(() => keyCatcher.forceActiveFocus()) }`.

### Keyboard cursor

- A simple approach that scales: give every navigable row a string id, compute a
  `cursorOrder` array from what's visible, and have `moveCursor(dy)` step through
  it. Rows register themselves (`Component.onCompleted: root.registerRow(id, this)`)
  so `scrollItemIntoView` can find them.
- **Gotcha: PanelKeyCatcher reserves keys.** `h j k l`, arrows, `enter`, `space`,
  `x`, `tab`, and `esc` never reach `onTextKey`. In particular `l` is "move right"
  and `x` is delete. Pick shortcut letters outside that set (and check the
  file, since the list may grow).
- A `TextField` inside the panel needs `blocked: field.activeFocus` on the key
  catcher, and its own `Keys.onPressed` for up/down/enter/escape.
- `onTabRequested: root.switchPanel(direction)` hops between bar panels, the
  same as the built-ins.

## 5. Service.qml patterns (wrapping a CLI)

- One `Process` per command, each with `StdioCollector { waitForEnd: true }` for
  stdout/stderr, and parsing in `onExited`. Skip a poll if its process is still
  running.
- If the CLI has a streaming/"listen" mode, run it as a long-lived `Process` with
  `stdout: SplitParser { onRead: … }` for instant updates. Keep the periodic poll
  as a fallback. Restart the stream with exponential backoff when it exits
  (daemon restarts).
- **Watchdog:** arm a one-shot timer when you launch a batch of polls and kill
  anything still running when it fires. Don't restart it on every refresh, or a
  hung process never gets reaped.
- Batch several cheap reads into one `bash -c` that prints `@@section` markers
  between command outputs, then split on the markers. Fewer processes per tick.
- Keep slow/network calls (account lookups, big lists) on a longer interval or
  load them lazily when the panel opens.
- **Optimistic toggles:** `_desired` = -1/0/1 and
  `active = _desired === -1 ? real : _desired === 1`. Clear it when reality
  catches up or the command fails. The switch then reacts instantly. For settings
  toggles, set the local value immediately and ignore stale poll results for
  that key while its command is in flight.
- After any action: `delayedRefresh.restart()` (~600 ms), then surface stderr in an
  `actionStatus`/`lastError` line that auto-clears after a couple of seconds.
- Run commands as argument arrays, never string-built shell. For chained commands
  use `["bash","-c","\"$@\" && next", "name", ...args]`. Side effects that need no
  result: `Quickshell.execDetached(["wl-copy","--",text])`,
  `Quickshell.execDetached(["omarchy-launch-browser", url])`.
- Prefer `--json` output when the CLI has it. For text output, anchor regexes on
  `^\s*Label:\s*(.+)$` with the `m` flag.
- **Security:** plugins share one QML scene with everything else. Don't read secrets
  (account numbers, tokens) into properties if the UI doesn't need them.

## 6. Persisting per-widget state

Settings live inline on the widget's `shell.json` entry. To write back (e.g.
"recent items"), copy `settings` into a new entry object and call
`root.bar.shell.updateEntryInline(moduleName, entry)`. Guard it with
`typeof … === "function"`, because third-party plugins get a capability-scoped
facade and the method may not be there.

## 7. Icons

Nerd Font Material glyphs work well in the bar. To find codepoints, pull
`https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json`
and look up names such as `md-shield_check`. Use distinct glyphs for each state
(on / transitioning / off / error) rather than just changing opacity.

## 8. Testing

- **Parsers:** keep them in `Model.js` with no QML dependencies and load it in node
  through `vm` (QML JS files have no exports):
  ```js
  const M = {}; vm.createContext(M); vm.runInContext(fs.readFileSync("Model.js","utf8"), M)
  ```
  **Gotcha:** arrays created inside the vm context fail `assert.deepStrictEqual`
  against outer-context arrays ("same structure but not reference-equal"). Wrap
  them with `Array.from(...)` first.
  Also run the parsers once against the real CLI output, not just fixtures.
- **Live checks:** call your IPC (`omarchy-shell <id> status`), open the panel over
  IPC (`omarchy-shell <id> open`), and screenshot the top-right corner:
  ```bash
  grim -g "$(hyprctl monitors -j | python3 -c 'import json,sys;m=[x for x in json.load(sys.stdin) if x["focused"]][0];w=int(m["width"]/m["scale"]);print(f"{m["x"]+w-700},{m["y"]} 700x1300")')" shot.png
  ```
- **Logs:** `ls -td /run/user/$UID/quickshell/by-id/*/ | head -1` → `log.log`.
  "Handler was registered but will not be used" warnings for the built-ins after
  a reload are pre-existing noise. Look for your id, `ReferenceError`, `TypeError`,
  and binding loops.
- **Gotcha: be careful with synthetic keystrokes (`wtype`).** If the key you expect
  to open something is swallowed (see the reserved keys above), the following
  letters land on the key catcher and can trigger real actions. Typing a search
  word once toggled the service off. Only send keys that have no action binding,
  prefer adding an IPC entry point (e.g. `openSearch()`) over key-driving the UI,
  and re-check the real service state after UI tests.

## 9. Checklist

1. Read the closest built-in panel end to end.
2. Probe the CLI: JSON flags, a listen/stream mode, and every `get` you'll need.
3. Write `Model.js` + node tests against captured and live output.
4. `Service.qml`, then `Panel.qml`, then `manifest.json` and `README.md`.
5. `omarchy plugin validate`, symlink, `rescanPlugins`, `plugin enable`.
6. `omarchy restart shell` after edits. Verify with IPC, screenshots, and logs.
7. `omarchy plugin add` expects a git repo with `manifest.json` at its root, so
   `git init` the plugin folder if you want to share or install it that way.
