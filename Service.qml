import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool refreshing: false

  // Tunnel state, straight from `mullvad status --json`.
  property var status: Model.emptyStatus()
  readonly property bool connected: status.connected
  readonly property bool transitioning: status.transitioning
  readonly property bool blocked: status.blocked
  readonly property string state: status.state

  // Optimistic on/off so the switch throws the instant you click, rather than
  // waiting for the daemon. -1 follows the real state; 0/1 while a toggle is
  // still catching up (the same pattern as the Tailscale widget).
  property int _desired: -1
  readonly property bool active: _desired === -1 ? (connected || status.state === "connecting") : (_desired === 1)

  // Daemon settings.
  property bool lockdown: false
  property bool autoConnect: false
  property bool lanSharing: false
  property var constraint: Model.parseRelayConstraint("")
  property var version: Model.parseVersion("")
  property var account: Model.parseAccount("")
  property var locations: []
  property string settingKey: ""
  property string settingLocationId: ""

  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: actionProcess.running
  readonly property string statusText: installed ? Model.statusLabel(status) : "Not installed"
  readonly property string locationText: Model.locationLabel(status.city, status.country)
  readonly property string constraintText: Model.constraintLabel(constraint, locations)
  readonly property bool accountExpiringSoon: account.loggedIn && account.daysLeft >= 0 && account.daysLeft <= intSetting("expiryWarningDays", 7, 0, 365)

  property double _lastAccountRefreshMs: 0
  property double _lastRelayListMs: 0
  property int _listenFailures: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["wl-copy", "--", text])
    actionStatus = "Copied " + text
    actionStatusTimer.restart()
  }

  function refresh(forceSlow) {
    if (!installed) {
      if (!whichProcess.running) {
        refreshing = true
        whichProcess.running = true
      }
      return
    }
    var launched = false
    if (!statusProcess.running) {
      refreshing = true
      statusProcess.running = true
      launched = true
    }
    if (!settingsProcess.running) {
      settingsProcess.running = true
      launched = true
    }
    // The account lookup goes out to Mullvad's API, so only ask now and then.
    var now = Date.now()
    if ((forceSlow === true || now - _lastAccountRefreshMs > 600000) && !accountProcess.running) {
      _lastAccountRefreshMs = now
      accountProcess.running = true
      launched = true
    }
    if (!listenProcess.running && !listenRestart.running) listenProcess.running = true
    // Arm once per batch; restarting on every refresh would push the deadline
    // out ahead of a hung process forever.
    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  function loadLocations(force) {
    if (!installed || relayListProcess.running) return
    if (force !== true && locations.length > 0 && Date.now() - _lastRelayListMs < 3600000) return
    relayListProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) return
    status = parsed
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && !parsed.transitioning && parsed.connected === (_desired === 1)) _desired = -1
    if (parsed.state === "error") lastError = parsed.errorCause !== "" ? parsed.errorCause : "Connection error"
    else if (lastError !== "" && actionStatus === "") lastError = ""
  }

  function applySettings(raw) {
    var sections = String(raw || "").split("\n@@")
    for (var i = 0; i < sections.length; i++) {
      var section = sections[i]
      var nl = section.indexOf("\n")
      var name = (nl === -1 ? section : section.substring(0, nl)).replace(/^@@/, "").trim()
      var body = nl === -1 ? "" : section.substring(nl + 1)
      if (name === "lockdown") { var l = Model.parseOnOff(body); if (l !== null && settingKey !== "lockdown") lockdown = l }
      else if (name === "autoconnect") { var a = Model.parseOnOff(body); if (a !== null && settingKey !== "autoConnect") autoConnect = a }
      else if (name === "lan") { var n = Model.parseOnOff(body); if (n !== null && settingKey !== "lanSharing") lanSharing = n }
      else if (name === "relay") constraint = Model.parseRelayConstraint(body)
      else if (name === "version") version = Model.parseVersion(body)
    }
  }

  function toggleConnection() {
    if (!installed) return
    if (active) disconnect()
    else connect()
  }

  function connect() {
    _desired = 1
    runAction(["mullvad", "connect"], "")
  }

  function disconnect() {
    _desired = 0
    runAction(["mullvad", "disconnect"], "")
  }

  function reconnect() {
    if (!connected) return
    runAction(["mullvad", "reconnect"], "Picking a new relay…")
  }

  function setLockdown(on) {
    settingKey = "lockdown"
    lockdown = on
    runAction(["mullvad", "lockdown-mode", "set", on ? "on" : "off"], "")
  }

  function setAutoConnect(on) {
    settingKey = "autoConnect"
    autoConnect = on
    runAction(["mullvad", "auto-connect", "set", on ? "on" : "off"], "")
  }

  function setLanSharing(on) {
    settingKey = "lanSharing"
    lanSharing = on
    runAction(["mullvad", "lan", "set", on ? "allow" : "block"], "")
  }

  // Picking a location means "take me there", so connect too; when already
  // connected the daemon reconnects on its own and `connect` is a no-op.
  function setLocation(loc) {
    var command = Model.locationCommand(loc)
    if (command.length === 0) return
    settingLocationId = String(loc.id || "")
    _desired = 1
    runAction(["bash", "-c", "\"$@\" && mullvad connect", "mullvad-set-location"].concat(command),
      "Switching to " + (loc.kind === "city" ? Model.locationLabel(loc.city, loc.country) : loc.country) + "…")
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Every poll is skipped while its own process is still running, so one that
    // never exits would silently stop the panel refreshing. Reap stragglers.
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (settingsProcess.running) settingsProcess.running = false
      if (accountProcess.running) accountProcess.running = false
    }
  }

  Timer {
    // `status listen` dies when the daemon restarts; back off before retrying
    // so a stopped daemon does not spin a process every few milliseconds.
    id: listenRestart
    interval: Math.min(60000, 2000 * Math.pow(2, Math.min(5, root._listenFailures)))
    repeat: false
    onTriggered: if (root.installed && !listenProcess.running) listenProcess.running = true
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    command: ["which", "mullvad"]
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      root.refreshing = false
      if (root.installed) root.refresh(true)
      else root.status = Model.emptyStatus()
    }
  }

  Process {
    id: statusProcess
    command: ["mullvad", "status", "--json"]
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode === 0) root.applyStatus(statusStdout.text)
      else {
        var s = Model.emptyStatus()
        s.state = "unavailable"
        root.status = s
        root._desired = -1
        root.lastError = root.elideStatus(statusStderr.text || "Mullvad daemon is not running")
      }
    }
  }

  Process {
    // Pushes a JSON line on every tunnel state change, so the icon follows
    // connect/disconnect instantly instead of on the next poll.
    id: listenProcess
    command: ["mullvad", "status", "--json", "listen"]
    stdout: SplitParser {
      onRead: function(line) {
        root._listenFailures = 0
        root.applyStatus(line)
      }
    }
    onExited: function(exitCode) {
      root._listenFailures++
      listenRestart.restart()
    }
  }

  Process {
    id: settingsProcess
    command: ["bash", "-c",
      "printf '@@lockdown\\n'; mullvad lockdown-mode get; "
      + "printf '\\n@@autoconnect\\n'; mullvad auto-connect get; "
      + "printf '\\n@@lan\\n'; mullvad lan get; "
      + "printf '\\n@@relay\\n'; mullvad relay get; "
      + "printf '\\n@@version\\n'; mullvad version"]
    stdout: StdioCollector { id: settingsStdout; waitForEnd: true }
    onExited: function(exitCode) { root.applySettings(settingsStdout.text) }
  }

  Process {
    id: accountProcess
    command: ["mullvad", "account", "get"]
    stdout: StdioCollector { id: accountStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.account = Model.parseAccount(accountStdout.text)
    }
  }

  Process {
    id: relayListProcess
    command: ["mullvad", "relay", "list"]
    stdout: StdioCollector { id: relayListStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.locations = Model.parseRelayList(relayListStdout.text)
      root._lastRelayListMs = Date.now()
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(actionStderr.text || actionStdout.text || "Mullvad command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.actionStatus = ""
      }
      root.settingKey = ""
      root.settingLocationId = ""
      delayedRefresh.restart()
    }
  }
}
