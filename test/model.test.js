// Run with: node test/model.test.js
// Loads Model.js the way QML does (plain script, no exports) and checks the
// parsers against captured CLI output.
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const M = {}
vm.createContext(M)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8"), M)

const connected = '{"state":"connected","details":{"endpoint":{"address":"23.234.123.2:22029","protocol":"udp","quantum_resistant":true,"obfuscation":null,"entry_endpoint":null,"tunnel_interface":"wg0-mullvad","daita":false},"location":{"ipv4":"23.234.123.122","ipv6":null,"country":"Canada","city":"Montreal","latitude":45.5053,"longitude":-73.5525,"mullvad_exit_ip":true,"hostname":"ca-mtr-wg-307","entry_hostname":null},"feature_indicators":["QuantumResistance"]}}'
let s = M.parseStatus(connected)
assert.strictEqual(s.connected, true)
assert.strictEqual(s.city, "Montreal")
assert.strictEqual(s.ipv4, "23.234.123.122")
assert.strictEqual(s.ipv6, "")
assert.strictEqual(s.protocol, "UDP")
assert.deepStrictEqual(Array.from(s.features), ["Quantum resistance"])
assert.strictEqual(M.statusLabel(s), "Connected")

s = M.parseStatus('{"state":"disconnected","details":{"location":null,"locked_down":true}}')
assert.strictEqual(s.connected, false)
assert.strictEqual(s.blocked, true)
assert.strictEqual(M.statusLabel(s), "Blocking traffic")

s = M.parseStatus('{"state":"error","details":{"cause":{"AuthFailed":"InvalidAccount"},"block_failure":null}}')
assert.strictEqual(s.state, "error")
assert.strictEqual(s.errorCause, "Auth Failed: InvalidAccount")

assert.strictEqual(M.parseStatus("garbage").ok, false)

assert.strictEqual(M.parseOnOff("Block traffic when the VPN is disconnected: off"), false)
assert.strictEqual(M.parseOnOff("Autoconnect: on"), true)
assert.strictEqual(M.parseOnOff("Local network sharing setting: block"), false)
assert.strictEqual(M.parseOnOff("Local network sharing setting: allow"), true)

const acct = M.parseAccount("Mullvad account:    1234\nExpires at:         2026-12-12 23:24:57 -05:00\nDevice name:        Happy Merlin\n", Date.parse("2026-09-27T12:00:00Z"))
assert.strictEqual(acct.loggedIn, true)
assert.strictEqual(acct.deviceName, "Happy Merlin")
assert.strictEqual(acct.daysLeft, 76)
assert.ok(!("accountNumber" in acct))

const v = M.parseVersion("Current version       : 2026.4\nIs supported          : true\nSuggested upgrade     : 2026.5\n")
assert.strictEqual(v.upgrade, "2026.5")

const c = M.parseRelayConstraint("Generic constraints\n    Location:               city mtr, ca\n    Provider(s):            any\nWireGuard constraints\n    Multihop state:         disabled\n")
assert.strictEqual(c.kind, "city")
assert.strictEqual(c.cityCode, "mtr")
assert.strictEqual(c.countryCode, "ca")
assert.strictEqual(M.parseRelayConstraint("    Location:               country se\n").countryCode, "se")
assert.strictEqual(M.parseRelayConstraint("    Location:               any\n").kind, "any")

const list = "Albania (al)\n\tTirana (tia) @ 41.32795°N, 19.81902°W\n\t\tal-tia-wg-001 (x) - hosted by y (rented)\n\t\tal-tia-wg-002 (x) - hosted by y (rented)\n\nCanada (ca)\n\tMontreal (mtr) @ 45°N, -73°W\n\t\tca-mtr-wg-307 (x) - hosted by y\n\tToronto (tor) @ 1°N, 2°W\n\t\tca-tor-wg-001 (x) - hosted by y\n"
const locs = M.parseRelayList(list)
assert.strictEqual(locs.length, 5)
assert.strictEqual(locs[0].relays, 2)
assert.strictEqual(locs[2].relays, 2)
assert.strictEqual(M.constraintLabel(c, locs), "Montreal, Canada")
assert.strictEqual(M.filterLocations(locs, "").length, 2)
assert.deepStrictEqual(Array.from(M.filterLocations(locs, "toro"), l => l.id), ["ca-tor"])
assert.deepStrictEqual(Array.from(M.locationCommand(locs[3])), ["mullvad", "relay", "set", "location", "ca", "mtr"])

console.log("model tests passed")
