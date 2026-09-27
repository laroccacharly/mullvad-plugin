import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "mullvad"
  ipcTarget: "mullvad"
  manageIpc: false

  // Keyboard cursor: one id per navigable row, walked in `cursorOrder`.
  property string cursorId: "toggle"
  property bool cursorActive: false
  property bool pickerOpen: false
  property string locationQuery: ""
  property int pickerIndex: 0
  property var rowItems: ({})

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property bool showDetails: mullvad.installed && (mullvad.connected || mullvad.transitioning) && mullvad.status.ipv4 !== ""
  readonly property var recentIds: settings.recentLocations instanceof Array ? settings.recentLocations : []
  readonly property var recentLocations: recentLocationNodes()
  readonly property var filteredLocations: Model.filterLocations(mullvad.locations, locationQuery)

  // Shield glyphs from the Nerd Font Material set.
  readonly property string glyph: {
    if (!mullvad.installed || mullvad.state === "unavailable") return "󰦞"
    if (mullvad.state === "error") return "󰻌"
    if (mullvad.transitioning || (mullvad._desired !== -1)) return "󱆢"
    if (mullvad.connected) return "󰦝"
    return mullvad.lockdown ? "󰻌" : "󰦞"
  }

  readonly property var cursorOrder: {
    var order = []
    if (!mullvad.installed) return order
    order.push("toggle")
    if (showDetails) {
      order.push("ipv4")
      if (mullvad.status.ipv6 !== "") order.push("ipv6")
      if (mullvad.status.hostname !== "") order.push("relay")
      if (mullvad.status.entryHostname !== "") order.push("entry")
      if (mullvad.status.endpoint !== "") order.push("endpoint")
    }
    order.push("location")
    if (pickerOpen) {
      for (var p = 0; p < filteredLocations.length; p++) order.push("pick:" + p)
    } else {
      for (var r = 0; r < recentLocations.length; r++) order.push("recent:" + r)
    }
    if (mullvad.connected) order.push("reconnect")
    order.push("lockdown", "autoconnect", "lan", "account")
    if (mullvad.version.upgrade !== "") order.push("update")
    return order
  }

  function locationTitle(loc) {
    if (!loc) return ""
    return loc.kind === "city" ? loc.city : loc.country
  }

  function locationSubtitle(loc) {
    if (!loc) return ""
    var relays = loc.relays === 1 ? "1 server" : loc.relays + " servers"
    return (loc.kind === "city" ? loc.country + " · " : "") + relays
  }

  function isCurrentLocation(loc) {
    var c = mullvad.constraint
    if (!loc || !c) return false
    if (loc.countryCode !== c.countryCode) return false
    return loc.kind === "city" ? (c.kind === "city" && c.cityCode === loc.cityCode) : c.kind === "country"
  }

  function recentLocationNodes() {
    var nodes = []
    for (var i = 0; i < recentIds.length && nodes.length < 3; i++) {
      var id = String(recentIds[i] || "")
      for (var j = 0; j < mullvad.locations.length; j++) {
        if (mullvad.locations[j].id === id) { nodes.push(mullvad.locations[j]); break }
      }
    }
    return nodes
  }

  // Remember picked locations on this widget's own shell.json entry so the
  // panel can offer them as one-click shortcuts next time.
  function persistRecent(loc) {
    var id = String(loc && loc.id || "")
    if (id === "") return
    var next = [id]
    for (var i = 0; i < recentIds.length && next.length < 3; i++) {
      var existing = String(recentIds[i] || "")
      if (existing !== "" && next.indexOf(existing) === -1) next.push(existing)
    }
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.recentLocations = next
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseLocation(loc) {
    if (!loc) return
    persistRecent(loc)
    mullvad.setLocation(loc)
    closePicker()
  }

  function openPicker() {
    mullvad.loadLocations()
    pickerOpen = true
    pickerIndex = 0
    locationQuery = ""
    Qt.callLater(function() { if (locationSearch) locationSearch.forceActiveFocus() })
  }

  function closePicker() {
    pickerOpen = false
    locationQuery = ""
    if (root.opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function togglePicker() {
    if (pickerOpen) closePicker()
    else openPicker()
  }

  function registerRow(id, item) {
    rowItems[id] = item
  }

  function setCursor(id) {
    cursorActive = true
    cursorId = id
  }

  function ensureCursor() {
    if (cursorOrder.length === 0) return
    if (cursorOrder.indexOf(cursorId) === -1) cursorId = cursorOrder[0]
  }

  function moveCursor(dy) {
    cursorActive = true
    ensureCursor()
    var i = cursorOrder.indexOf(cursorId)
    var next = Math.max(0, Math.min(cursorOrder.length - 1, i + (dy > 0 ? 1 : -1)))
    cursorId = cursorOrder[next]
    scrollItemIntoView(rowItems[cursorId])
  }

  function movePickerCursor(delta) {
    if (filteredLocations.length === 0) return
    pickerIndex = Math.max(0, Math.min(filteredLocations.length - 1, pickerIndex + delta))
    scrollItemIntoView(rowItems["pick:" + pickerIndex])
  }

  function activate(id) {
    if (id === "toggle") mullvad.toggleConnection()
    else if (id === "ipv4") mullvad.copyToClipboard(mullvad.status.ipv4)
    else if (id === "ipv6") mullvad.copyToClipboard(mullvad.status.ipv6)
    else if (id === "relay") mullvad.copyToClipboard(mullvad.status.hostname)
    else if (id === "entry") mullvad.copyToClipboard(mullvad.status.entryHostname)
    else if (id === "endpoint") mullvad.copyToClipboard(mullvad.status.endpoint)
    else if (id === "location") togglePicker()
    else if (id.indexOf("recent:") === 0) chooseLocation(recentLocations[parseInt(id.substring(7), 10)])
    else if (id.indexOf("pick:") === 0) chooseLocation(filteredLocations[parseInt(id.substring(5), 10)])
    else if (id === "reconnect") mullvad.reconnect()
    else if (id === "lockdown") mullvad.setLockdown(!mullvad.lockdown)
    else if (id === "autoconnect") mullvad.setAutoConnect(!mullvad.autoConnect)
    else if (id === "lan") mullvad.setLanSharing(!mullvad.lanSharing)
    else if (id === "account") openUrl("https://mullvad.net/account")
    else if (id === "update") openUrl("https://mullvad.net/download/vpn/linux")
  }

  function openUrl(url) {
    Quickshell.execDetached(["omarchy-launch-browser", url])
    close()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorId = "toggle"
    pickerOpen = false
    if (panelFlick) panelFlick.contentY = 0
    mullvad.refresh(true)
    mullvad.loadLocations()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onCursorOrderChanged: ensureCursor()
  onFilteredLocationsChanged: pickerIndex = 0

  Service {
    id: mullvad
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { mullvad.refresh(true); return "ok" }
    function connect(): string { mullvad.connect(); return "ok" }
    function disconnect(): string { mullvad.disconnect(); return "ok" }
    function reconnect(): string { mullvad.reconnect(); return "ok" }
    function toggleConnection(): string { mullvad.toggleConnection(); return "ok" }
    function locations(): void { root.open(); root.openPicker() }
    function status(): string { return mullvad.statusText + (mullvad.locationText !== "" ? " · " + mullvad.locationText : "") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    dimmed: !mullvad.active && mullvad.state !== "error"
    active: mullvad.state === "error" || mullvad.accountExpiringSoon
    tooltipText: "Mullvad: " + mullvad.statusText + (mullvad.connected && mullvad.locationText !== "" ? "\n" + mullvad.locationText + " · " + mullvad.status.ipv4 : "")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) mullvad.toggleConnection()
      else if (buttonCode === Qt.MiddleButton) mullvad.reconnect()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: locationSearch.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activate(root.cursorId)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "t") mullvad.toggleConnection()
        else if (k === "r") mullvad.reconnect()
        else if (k === "c") mullvad.copyToClipboard(mullvad.status.ipv4)
        else if (k === "s" || k === "/") root.openPicker()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // PanelHero's trailingControl resolves `root` to the hero, so panel
            // state goes through `header`.
            readonly property bool ringVisible: root.cursorActive && root.cursorId === "toggle" && mullvad.installed
            function focusHero() { root.setCursor("toggle") }

            PanelHero {
              id: hero
              width: parent.width
              title: mullvad.connected && mullvad.locationText !== "" ? mullvad.locationText : "Mullvad VPN"
              meta: {
                if (!mullvad.installed) return "Mullvad CLI not found"
                if (mullvad.connected && mullvad.status.hostname !== "") return "Connected · " + mullvad.status.hostname
                return mullvad.statusText
              }
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: mullvad.active ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: root.glyph
                  color: mullvad.state === "error" ? root.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display

                  SequentialAnimation on opacity {
                    running: mullvad.transitioning
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutQuad }
                    onRunningChanged: if (!running) parent.opacity = 1.0
                  }
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: mullvad.installed
                  checked: mullvad.active
                  busy: mullvad.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: mullvad.toggleConnection()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: mullvad.active ? "Disconnect" : "Connect"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: mullvad.actionStatus !== "" || mullvad.lastError !== ""
            width: parent.width
            text: mullvad.actionStatus !== "" ? mullvad.actionStatus : mullvad.lastError
            color: mullvad.lastError !== "" && mullvad.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: !mullvad.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "The mullvad CLI is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          // ── Connection details ──────────────────────────────────────────
          PanelSeparator { visible: root.showDetails; foreground: root.foreground }

          Column {
            visible: root.showDetails
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "CONNECTION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            InfoRow {
              rowId: "ipv4"; icon: "󰩟"; label: "Exit IP"
              value: mullvad.status.ipv4
            }
            InfoRow {
              rowId: "ipv6"; icon: "󰩟"; label: "Exit IPv6"
              value: mullvad.status.ipv6
            }
            InfoRow {
              rowId: "relay"; icon: "󰒍"; label: "Relay"
              value: mullvad.status.hostname
            }
            InfoRow {
              rowId: "entry"; icon: "󰓡"; label: "Entry relay"
              value: mullvad.status.entryHostname
            }
            InfoRow {
              rowId: "endpoint"; icon: "󰖟"; label: "Server"
              value: mullvad.status.endpoint
            }
            InfoRow {
              rowId: ""; icon: "󰖂"; label: "Tunnel"
              value: {
                var parts = []
                if (mullvad.status.protocol !== "") parts.push("WireGuard/" + mullvad.status.protocol)
                if (mullvad.status.obfuscation !== "") parts.push(mullvad.status.obfuscation)
                return parts.join(" · ")
              }
            }
            InfoRow {
              rowId: ""; icon: "󰒃"; label: "Features"
              value: mullvad.status.features.length > 0 ? mullvad.status.features.join(", ") : ""
            }
          }

          // ── Location ────────────────────────────────────────────────────
          PanelSeparator { visible: mullvad.installed; foreground: root.foreground }

          Column {
            visible: mullvad.installed
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "LOCATION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ActionRow {
              rowId: "location"
              icon: "󰍎"
              title: mullvad.constraintText
              subtitle: root.pickerOpen ? "Pick a country, or search for a city" : "Change location"
              current: root.pickerOpen
              trailing: root.pickerOpen ? "󰅖" : "󰅀"
            }

            Repeater {
              model: root.pickerOpen ? [] : root.recentLocations
              LocationRow {
                required property var modelData
                required property int index
                width: parent.width
                loc: modelData
                rowId: "recent:" + index
              }
            }

            Column {
              visible: root.pickerOpen
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: locationSearch
                width: parent.width
                foreground: root.foreground
                placeholderText: "Search countries and cities"
                text: root.locationQuery
                onTextChanged: root.locationQuery = text
                onAccepted: root.chooseLocation(root.filteredLocations[root.pickerIndex])
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier)) {
                    root.movePickerCursor(1); event.accepted = true
                  } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier)) {
                    root.movePickerCursor(-1); event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.chooseLocation(root.filteredLocations[root.pickerIndex]); event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.closePicker(); event.accepted = true
                  }
                }
              }

              Text {
                visible: root.filteredLocations.length === 0
                width: parent.width
                text: mullvad.locations.length === 0 ? "Loading relay list…" : "No locations match."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
              }

              Repeater {
                model: root.pickerOpen ? root.filteredLocations : []
                LocationRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  loc: modelData
                  rowId: "pick:" + index
                  picked: locationSearch.activeFocus && root.pickerIndex === index
                }
              }
            }

            ActionRow {
              visible: mullvad.connected
              rowId: "reconnect"
              icon: "󰑐"
              title: "Reconnect"
              subtitle: "Switch to another server in the same location"
            }
          }

          // ── Settings ────────────────────────────────────────────────────
          PanelSeparator { visible: mullvad.installed; foreground: root.foreground }

          Column {
            visible: mullvad.installed
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "SETTINGS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SettingRow {
              rowId: "lockdown"
              title: "Lockdown mode"
              subtitle: "Block all traffic when the VPN is off"
              checked: mullvad.lockdown
              pending: mullvad.settingKey === "lockdown"
            }
            SettingRow {
              rowId: "autoconnect"
              title: "Auto-connect"
              subtitle: "Connect when the daemon starts"
              checked: mullvad.autoConnect
              pending: mullvad.settingKey === "autoConnect"
            }
            SettingRow {
              rowId: "lan"
              title: "Local network sharing"
              subtitle: "Reach printers and devices on your LAN"
              checked: mullvad.lanSharing
              pending: mullvad.settingKey === "lanSharing"
            }
          }

          // ── Account ─────────────────────────────────────────────────────
          PanelSeparator { visible: mullvad.installed; foreground: root.foreground }

          Column {
            visible: mullvad.installed
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "ACCOUNT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ActionRow {
              rowId: "account"
              icon: "󰃰"
              title: Model.accountExpiryLabel(mullvad.account)
              subtitle: mullvad.account.deviceName !== "" ? "This device: " + mullvad.account.deviceName : "Manage account"
              warn: mullvad.accountExpiringSoon
              trailing: "󰏌"

            }

            ActionRow {
              visible: mullvad.version.upgrade !== ""
              rowId: "update"
              icon: "󰚰"
              title: "Update available: " + mullvad.version.upgrade
              subtitle: "Installed " + mullvad.version.current + (mullvad.version.supported ? "" : " (no longer supported)")
              warn: !mullvad.version.supported
              trailing: "󰏌"
            }
          }
        }
      }
    }
  }

  // ── Row components ────────────────────────────────────────────────────

  // Label/value line; rows with an id can be selected and copy their value.
  component InfoRow: CursorSurface {
    id: infoRow
    property string rowId: ""
    property string icon: ""
    property string label: ""
    property string value: ""

    visible: value !== ""
    width: parent ? parent.width : 0
    hasCursor: rowId !== "" && root.cursorActive && root.cursorId === rowId
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: infoLayout.implicitHeight + Style.spacing.lg
    Component.onCompleted: if (rowId !== "") root.registerRow(rowId, infoRow)

    RowLayout {
      id: infoLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: infoRow.icon
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        text: infoRow.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Style.space(80)
      }

      Text {
        textFormat: Text.PlainText
        text: infoRow.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
        Layout.fillWidth: true
      }

      Text {
        visible: infoRow.rowId !== "" && (infoMouse.containsMouse || infoRow.hasCursor)
        text: "󰆏"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      id: infoMouse
      anchors.fill: parent
      enabled: infoRow.rowId !== ""
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(infoRow.rowId)
      onClicked: root.activate(infoRow.rowId)
    }

    PanelToolTip {
      visible: infoRow.rowId !== "" && infoMouse.containsMouse
      text: "Copy"
      fontFamily: root.fontFamily
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string rowId: ""
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property bool warn: false

    width: parent ? parent.width : 0
    hasCursor: root.cursorActive && root.cursorId === rowId
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: actionLayout.implicitHeight + Style.spacing.xl
    Component.onCompleted: root.registerRow(rowId, actionRow)

    RowLayout {
      id: actionLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: actionRow.icon
        color: actionRow.warn ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.title
          color: actionRow.warn ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== ""
          text: actionRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: actionRow.trailing !== ""
        text: actionRow.trailing
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: mullvad.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: root.setCursor(actionRow.rowId)
      onClicked: root.activate(actionRow.rowId)
    }
  }

  component SettingRow: CursorSurface {
    id: settingRow
    property string rowId: ""
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool pending: false

    width: parent ? parent.width : 0
    hasCursor: root.cursorActive && root.cursorId === rowId
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: settingLayout.implicitHeight + Style.spacing.lg
    Component.onCompleted: root.registerRow(rowId, settingRow)

    RowLayout {
      id: settingLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: settingRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: settingRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        interactive: false
        checked: settingRow.checked
        busy: settingRow.pending
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: mullvad.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: root.setCursor(settingRow.rowId)
      onClicked: if (!mullvad.busy) root.activate(settingRow.rowId)
    }
  }

  component LocationRow: CursorSurface {
    id: locRow
    property var loc: null
    property string rowId: ""
    property bool picked: false
    readonly property bool currentLocation: root.isCurrentLocation(loc)
    readonly property bool switching: loc && mullvad.settingLocationId === String(loc.id || "")

    hasCursor: picked || (root.cursorActive && root.cursorId === rowId)
    current: currentLocation || switching
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: locLayout.implicitHeight + Style.spacing.lg
    Component.onCompleted: root.registerRow(rowId, locRow)

    Row {
      id: locLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: locRow.loc && locRow.loc.kind === "city" ? "󰍎" : "󰇧"
        color: locRow.current ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter

        NumberAnimation on rotation {
          running: locRow.switching
          from: 0; to: 360; duration: 900
          loops: Animation.Infinite
        }
        onRotationChanged: if (!locRow.switching && rotation !== 0) rotation = 0
      }

      Column {
        width: parent.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.locationTitle(locRow.loc)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: locRow.currentLocation
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.locationSubtitle(locRow.loc)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        if (locRow.rowId.indexOf("pick:") === 0) root.pickerIndex = parseInt(locRow.rowId.substring(5), 10)
        else root.setCursor(locRow.rowId)
      }
      onClicked: root.chooseLocation(locRow.loc)
    }
  }
}
