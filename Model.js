// Pure parsing helpers for the Mullvad widget. Kept free of QML so they can be
// exercised with plain node (see test/model.test.js).

var FEATURE_LABELS = {
  QuantumResistance: "Quantum resistance",
  Multihop: "Multihop",
  Daita: "DAITA",
  DaitaMultihop: "DAITA multihop",
  LockdownMode: "Lockdown mode",
  Udp2Tcp: "UDP-over-TCP",
  Shadowsocks: "Shadowsocks",
  Quic: "QUIC",
  Lwo: "LWO",
  LanSharing: "Local network sharing",
  DnsContentBlockers: "DNS content blockers",
  CustomDns: "Custom DNS",
  ServerIpOverride: "Server IP override",
  CustomMtu: "Custom MTU",
  SplitTunneling: "Split tunneling"
}

function featureLabel(name) {
  var key = String(name || "")
  if (FEATURE_LABELS[key]) return FEATURE_LABELS[key]
  // Fall back to splitting CamelCase so unknown future features still read well.
  return key.replace(/([a-z0-9])([A-Z])/g, "$1 $2")
}

function emptyStatus() {
  return {
    ok: true,
    state: "unknown",
    connected: false,
    transitioning: false,
    blocked: false,
    lockedDown: false,
    country: "",
    city: "",
    hostname: "",
    entryHostname: "",
    ipv4: "",
    ipv6: "",
    mullvadExitIp: false,
    endpoint: "",
    protocol: "",
    tunnelInterface: "",
    obfuscation: "",
    features: [],
    errorCause: "",
    message: ""
  }
}

function describeCause(cause) {
  if (!cause) return ""
  if (typeof cause === "string") return featureLabel(cause)
  if (typeof cause === "object") {
    var keys = Object.keys(cause)
    if (keys.length === 0) return ""
    var inner = cause[keys[0]]
    var detail = typeof inner === "string" ? inner : ""
    return featureLabel(keys[0]) + (detail !== "" ? ": " + detail : "")
  }
  return String(cause)
}

// Parse one `mullvad status --json` document (also one line of
// `mullvad status --json listen`).
function parseStatus(raw) {
  var result = emptyStatus()
  var text = String(raw || "").trim()
  if (text === "") {
    result.ok = false
    result.message = "No status"
    return result
  }
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    result.ok = false
    result.message = "Could not parse status"
    return result
  }

  var state = String(data.state || "unknown").toLowerCase()
  var details = data.details || {}
  var endpoint = details.endpoint || {}
  var location = details.location || {}

  result.state = state
  result.connected = state === "connected"
  result.transitioning = state === "connecting" || state === "disconnecting"
  result.blocked = state === "error" || details.locked_down === true
  result.lockedDown = details.locked_down === true

  result.country = String(location.country || "")
  result.city = String(location.city || "")
  result.hostname = String(location.hostname || "")
  result.entryHostname = String(location.entry_hostname || "")
  result.ipv4 = String(location.ipv4 || "")
  result.ipv6 = String(location.ipv6 || "")
  result.mullvadExitIp = location.mullvad_exit_ip === true

  result.endpoint = String(endpoint.address || "")
  result.protocol = String(endpoint.protocol || "").toUpperCase()
  result.tunnelInterface = String(endpoint.tunnel_interface || "")
  var obfuscation = endpoint.obfuscation
  if (obfuscation && typeof obfuscation === "object") {
    result.obfuscation = featureLabel(obfuscation.obfuscation_type || obfuscation.type || "")
  }

  var features = details.feature_indicators || []
  for (var i = 0; i < features.length; i++) result.features.push(featureLabel(features[i]))

  if (state === "error") result.errorCause = describeCause(details.cause || details.error_state || details)
  return result
}

function statusLabel(status) {
  if (!status) return "Checking…"
  switch (status.state) {
  case "connected": return "Connected"
  case "connecting": return "Connecting…"
  case "disconnecting": return "Disconnecting…"
  case "disconnected": return status.lockedDown ? "Blocking traffic" : "Disconnected"
  case "error": return "Blocked: connection error"
  default: return "Checking…"
  }
}

function locationLabel(city, country) {
  var c = String(city || "").trim()
  var n = String(country || "").trim()
  if (c !== "" && n !== "") return c + ", " + n
  return c || n
}

// `mullvad lockdown-mode get`, `auto-connect get`, `lan get` print a single
// "Label: value" line. Returns true/false, or null when it cannot tell.
function parseOnOff(raw) {
  var text = String(raw || "")
  var match = text.match(/:\s*(\S+)\s*$/m)
  if (!match) return null
  var value = match[1].toLowerCase()
  if (value === "on" || value === "allow" || value === "true" || value === "enabled") return true
  if (value === "off" || value === "block" || value === "false" || value === "disabled") return false
  return null
}

// `mullvad account get`. The account number is deliberately dropped: the panel
// never shows it, so it never sits in the shared QML scene.
function parseAccount(raw, nowMs) {
  var text = String(raw || "")
  var result = { loggedIn: false, expiresAt: "", expiresMs: 0, daysLeft: -1, deviceName: "" }
  var expires = text.match(/^\s*Expires at:\s*(.+?)\s*$/m)
  var device = text.match(/^\s*Device name:\s*(.+?)\s*$/m)
  var account = text.match(/^\s*Mullvad account:\s*\S+/m)
  result.loggedIn = !!account
  if (device) result.deviceName = device[1]
  if (expires) {
    result.expiresAt = expires[1]
    // "2026-12-12 23:24:57 -05:00" → ISO 8601 so Date can read it.
    var iso = expires[1].replace(/^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s*([+-]\d{2}:?\d{2})?$/, function(_, d, t, z) {
      return d + "T" + t + (z ? (z.indexOf(":") === -1 ? z.slice(0, 3) + ":" + z.slice(3) : z) : "Z")
    })
    var ms = Date.parse(iso)
    if (isFinite(ms)) {
      result.expiresMs = ms
      var now = typeof nowMs === "number" ? nowMs : Date.now()
      result.daysLeft = Math.max(0, Math.floor((ms - now) / 86400000))
    }
  }
  return result
}

function accountExpiryLabel(account) {
  if (!account || !account.loggedIn) return "Not logged in"
  if (account.expiresMs <= 0) return account.expiresAt !== "" ? "Expires " + account.expiresAt : "Logged in"
  var date = new Date(account.expiresMs)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var when = months[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear()
  if (account.daysLeft <= 0) return "Expires today · " + when
  if (account.daysLeft === 1) return "1 day left · " + when
  return account.daysLeft + " days left · " + when
}

// `mullvad version`: surfaces "Suggested upgrade" when there is one.
function parseVersion(raw) {
  var text = String(raw || "")
  var current = text.match(/^\s*Current version\s*:\s*(\S+)/m)
  var upgrade = text.match(/^\s*Suggested upgrade\s*:\s*(\S+)/m)
  var supported = text.match(/^\s*Is supported\s*:\s*(\S+)/m)
  return {
    current: current ? current[1] : "",
    upgrade: upgrade && upgrade[1] !== "none" ? upgrade[1] : "",
    supported: supported ? supported[1] === "true" : true
  }
}

// `mullvad relay get` → the location constraint, e.g. "city mtr, ca",
// "country se", "hostname se got se-got-wg-004", or "any".
function parseRelayConstraint(raw) {
  var text = String(raw || "")
  var result = { kind: "any", countryCode: "", cityCode: "", hostname: "", multihop: false, raw: "" }
  var loc = text.match(/^\s*Location:\s*(.+?)\s*$/m)
  var multihop = text.match(/^\s*Multihop state:\s*(\S+)/m)
  result.multihop = !!multihop && multihop[1] === "enabled"
  if (!loc) return result
  var value = loc[1].trim()
  result.raw = value
  var m
  if ((m = value.match(/^city\s+(\w+),\s*(\w+)/i))) {
    result.kind = "city"
    result.cityCode = m[1]
    result.countryCode = m[2]
  } else if ((m = value.match(/^country\s+(\w+)/i))) {
    result.kind = "country"
    result.countryCode = m[1]
  } else if ((m = value.match(/^hostname\s+(\w+)\s+(\w+)\s+(\S+)/i))) {
    result.kind = "hostname"
    result.countryCode = m[1]
    result.cityCode = m[2]
    result.hostname = m[3]
  } else if (/^any$/i.test(value)) {
    result.kind = "any"
  } else {
    result.kind = "other"
  }
  return result
}

// `mullvad relay list` → flat list of selectable locations: one entry per
// country followed by its cities.
//
//   Canada (ca)
//   \tMontreal (mtr) @ 45.50°N, -73.55°W
//   \t\tca-mtr-wg-001 (…) - hosted by … (rented)
function parseRelayList(raw) {
  var lines = String(raw || "").split("\n")
  var result = []
  var country = null
  var city = null
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue
    var m
    if (line.charAt(0) !== "\t" && (m = line.match(/^(.+?)\s+\((\w+)\)\s*$/))) {
      country = { id: m[2], kind: "country", country: m[1], countryCode: m[2], city: "", cityCode: "", relays: 0 }
      result.push(country)
      city = null
    } else if (/^\t[^\t]/.test(line) && country && (m = line.match(/^\t(.+?)\s+\((\w+)\)/))) {
      city = { id: country.countryCode + "-" + m[2], kind: "city", country: country.country, countryCode: country.countryCode, city: m[1], cityCode: m[2], relays: 0 }
      result.push(city)
    } else if (/^\t\t/.test(line) && country) {
      country.relays++
      if (city) city.relays++
    }
  }
  return result
}

function locationKey(loc) {
  if (!loc) return ""
  return loc.kind === "city" ? loc.countryCode + "-" + loc.cityCode : String(loc.countryCode || "")
}

function findLocation(locations, countryCode, cityCode) {
  var cc = String(countryCode || "").toLowerCase()
  var city = String(cityCode || "").toLowerCase()
  if (cc === "") return null
  for (var i = 0; i < locations.length; i++) {
    var loc = locations[i]
    if (loc.countryCode !== cc) continue
    if (city === "" && loc.kind === "country") return loc
    if (city !== "" && loc.kind === "city" && loc.cityCode === city) return loc
  }
  return null
}

function constraintLabel(constraint, locations) {
  if (!constraint || constraint.kind === "any") return "Any location"
  var loc = findLocation(locations || [], constraint.countryCode, constraint.cityCode)
  if (constraint.kind === "hostname") return constraint.hostname
  if (loc) return loc.kind === "city" ? locationLabel(loc.city, loc.country) : loc.country
  return constraint.raw
}

function filterLocations(locations, query) {
  var q = String(query || "").trim().toLowerCase()
  var result = []
  for (var i = 0; i < locations.length; i++) {
    var loc = locations[i]
    if (q === "") {
      // Without a query, list countries only; cities appear once you search.
      if (loc.kind === "country") result.push(loc)
      continue
    }
    var hay = (loc.city + " " + loc.country + " " + loc.countryCode + " " + loc.cityCode).toLowerCase()
    if (hay.indexOf(q) !== -1) result.push(loc)
  }
  return result
}

function locationCommand(loc) {
  if (!loc) return []
  if (loc.kind === "city") return ["mullvad", "relay", "set", "location", loc.countryCode, loc.cityCode]
  return ["mullvad", "relay", "set", "location", loc.countryCode]
}
