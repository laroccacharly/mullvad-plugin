#!/usr/bin/env bun
// mullvad-plugin: install, reinstall, uninstall, and drive the Mullvad widget
// in a running omarchy-shell. Everything shells out to the stock `omarchy` /
// `omarchy-shell` commands; the plugin id comes from manifest.json.

import { existsSync, lstatSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, mkdirSync } from "node:fs"
import { homedir } from "node:os"
import { join, resolve } from "node:path"

const ROOT = resolve(import.meta.dir, "..")
const MANIFEST = await Bun.file(join(ROOT, "manifest.json")).json()
const ID: string = MANIFEST.id
const PLUGINS_DIR = join(process.env.XDG_CONFIG_HOME || join(homedir(), ".config"), "omarchy", "plugins")
const LINK = join(PLUGINS_DIR, ID)
const SECTIONS = ["left", "center", "right"]

const USAGE = `Usage: bun mullvad-plugin <command> [args]

Commands:
  install [--section left|center|right]
                      Link this checkout into ${PLUGINS_DIR}, rescan, and enable
                      the widget. Safe to run repeatedly; --section only applies
                      the first time the widget is enabled.
  reinstall           Relink and restart the shell so code and IPC changes load.
                      Keeps the widget's bar position and settings.
  uninstall           Disable the widget and remove the link.
  status              Show link, enabled, and shell state.
  run <method> [args] Call the widget's IPC, e.g. \`run status\` or \`run toggle\`.
                      \`run\` with no method lists the available methods.
  validate            Check manifest.json with \`omarchy plugin validate\`.

Plugin id: ${ID} (from manifest.json)`

class CliError extends Error {}

function fail(message: string): never {
  throw new CliError(message)
}

function log(message: string) {
  console.log(message)
}

function sh(cmd: string[], opts: { quiet?: boolean } = {}) {
  const proc = Bun.spawnSync(cmd, { stdout: "pipe", stderr: "pipe", env: process.env })
  const stdout = proc.stdout.toString().trim()
  const stderr = proc.stderr.toString().trim()
  if (!opts.quiet && proc.exitCode !== 0) {
    fail(`${cmd.join(" ")} failed (exit ${proc.exitCode})${stderr ? `:\n${stderr}` : ""}`)
  }
  return { ok: proc.exitCode === 0, code: proc.exitCode ?? 1, stdout, stderr }
}

function shellRunning() {
  const res = sh(["omarchy-shell", "shell", "ping"], { quiet: true })
  return res.ok && res.stdout === "ok"
}

function requireShell() {
  if (!shellRunning()) fail("omarchy-shell is not running (omarchy-shell shell ping failed)")
}

// Every plugin the running shell knows about, keyed by id.
function listPlugins(): Map<string, { id: string; enabled: boolean; sourceDir?: string }> {
  const res = sh(["omarchy-shell", "shell", "listPlugins"])
  const out = new Map()
  for (const plugin of JSON.parse(res.stdout || "[]")) out.set(plugin.id, plugin)
  return out
}

function isEnabled(id = ID) {
  return listPlugins().get(id)?.enabled === true
}

function linkTarget(path: string): string | null {
  try {
    if (!lstatSync(path).isSymbolicLink()) return null
    return resolve(PLUGINS_DIR, readlinkSync(path))
  } catch {
    return null
  }
}

function pointsHere(path: string) {
  const target = linkTarget(path)
  if (!target) return false
  try {
    return realpathSync(target) === realpathSync(ROOT)
  } catch {
    return false
  }
}

// Links under the plugins dir that point at this checkout under another name,
// e.g. from before the manifest id changed.
function staleLinks() {
  if (!existsSync(PLUGINS_DIR)) return []
  return readdirSync(PLUGINS_DIR)
    .filter(name => name !== ID)
    .map(name => join(PLUGINS_DIR, name))
    .filter(pointsHere)
}

function removeStaleLinks() {
  const stale = staleLinks()
  for (const path of stale) {
    const oldId = path.slice(PLUGINS_DIR.length + 1)
    if (isEnabled(oldId)) {
      sh(["omarchy", "plugin", "disable", oldId])
      log(`Disabled old id ${oldId}`)
    }
    rmSync(path)
    log(`Removed stale link ${path}`)
  }
  return stale.length > 0
}

// Returns true when the link had to be created.
function ensureLink() {
  if (pointsHere(LINK)) return false
  if (existsSync(LINK) || linkTarget(LINK)) {
    fail(`${LINK} already exists and is not a link to ${ROOT}. Move it away first.`)
  }
  mkdirSync(PLUGINS_DIR, { recursive: true })
  symlinkSync(ROOT, LINK)
  log(`Linked ${LINK} -> ${ROOT}`)
  return true
}

function removeLink() {
  if (pointsHere(LINK) || (linkTarget(LINK) && !existsSync(LINK))) {
    rmSync(LINK)
    log(`Removed ${LINK}`)
    return true
  }
  if (existsSync(LINK)) fail(`${LINK} is not a link to ${ROOT}; leaving it alone`)
  return false
}

// rescanPlugins returns before discovery finishes, so poll for the result.
function rescan(until: () => boolean) {
  sh(["omarchy-shell", "shell", "rescanPlugins"])
  for (let i = 0; i < 50 && !until(); i++) Bun.sleepSync(100)
  return until()
}

function validate() {
  sh(["omarchy", "plugin", "validate", ROOT])
}

function install(args: string[]) {
  let section: string | undefined
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--section") section = args[++i]
    else if (args[i].startsWith("--section=")) section = args[i].slice("--section=".length)
    else fail(`unknown install option: ${args[i]}`)
  }
  if (section !== undefined && !SECTIONS.includes(section)) fail("--section must be left, center, or right")

  requireShell()
  validate()
  const cleaned = removeStaleLinks()
  const linked = ensureLink()

  if ((linked || cleaned || !listPlugins().has(ID)) && !rescan(() => listPlugins().has(ID))) {
    fail(`the shell did not pick up ${ID}; check the shell log`)
  }

  if (isEnabled()) {
    log(`${ID} is already enabled`)
  } else {
    sh(["omarchy", "plugin", "enable", ID, ...(section ? ["--section", section] : [])])
    log(`Enabled ${ID}${section ? ` in the ${section} section` : ""}`)
  }
  log(`Installed. Try: bun mullvad-plugin run status`)
}

function uninstall() {
  requireShell()
  if (isEnabled()) {
    sh(["omarchy", "plugin", "disable", ID])
    log(`Disabled ${ID}`)
  }
  const removed = removeLink()
  if (removed) rescan(() => !listPlugins().has(ID))
  if (!removed && !listPlugins().has(ID)) log(`${ID} is not installed`)
  else log("Uninstalled")
}

// The shell's watcher doesn't follow symlinks and IPC handlers are frozen at
// first registration, so a restart is the only reliable way to load changes.
function reinstall() {
  requireShell()
  validate()
  removeStaleLinks()
  if (pointsHere(LINK)) rmSync(LINK)
  ensureLink()
  if (!isEnabled()) {
    if (!rescan(() => listPlugins().has(ID))) fail(`the shell did not pick up ${ID}; check the shell log`)
    sh(["omarchy", "plugin", "enable", ID])
    log(`Enabled ${ID}`)
  }
  log("Restarting the shell to load the new code…")
  sh(["omarchy", "restart", "shell"])
  for (let i = 0; i < 50 && !shellRunning(); i++) Bun.sleepSync(200)
  if (!shellRunning()) fail("the shell did not come back after the restart")
  log("Reinstalled")
}

function status() {
  const target = linkTarget(LINK)
  log(`id:      ${ID}`)
  log(`link:    ${target ? `${LINK} -> ${target}${pointsHere(LINK) ? "" : " (not this checkout)"}` : existsSync(LINK) ? `${LINK} (not a symlink)` : "missing"}`)
  for (const path of staleLinks()) log(`stale:   ${path}`)
  if (!shellRunning()) {
    log("shell:   not running")
    return
  }
  const plugin = listPlugins().get(ID)
  log("shell:   running")
  log(`plugin:  ${plugin ? (plugin.enabled ? "enabled" : "known, disabled") : "not discovered"}`)
}

// IPC methods the running shell has registered for this plugin, from
// `qs ipc show`. Returns null when the listing isn't available.
function ipcMethods(): string[] | null {
  const shellPath = process.env.OMARCHY_PATH ? join(process.env.OMARCHY_PATH, "shell") : null
  if (!shellPath) return null
  const res = sh(["qs", "ipc", "-n", "-p", shellPath, "show"], { quiet: true })
  if (!res.ok) return null
  const methods: string[] = []
  let inTarget = false
  for (const line of res.stdout.split("\n")) {
    if (line.startsWith("target ")) inTarget = line.trim() === `target ${ID}`
    else if (inTarget) {
      const m = line.match(/^\s*function\s+(\S+)/)
      if (m) methods.push(m[1] + line.trim().slice("function ".length + m[1].length))
    }
  }
  return methods
}

function run(args: string[]) {
  requireShell()
  if (!isEnabled()) fail(`${ID} is not enabled. Run: bun mullvad-plugin install`)
  if (args.length === 0) {
    const methods = ipcMethods()
    if (!methods || methods.length === 0) fail(`could not list IPC methods for ${ID}`)
    log(`IPC methods on ${ID}:`)
    for (const m of methods) log(`  ${m}`)
    return
  }
  const proc = Bun.spawnSync(["omarchy-shell", ID, ...args], { stdout: "inherit", stderr: "inherit", env: process.env })
  process.exitCode = proc.exitCode ?? 1
}

const [command, ...rest] = process.argv.slice(2)
try {
  switch (command) {
    case "install": install(rest); break
    case "reinstall": reinstall(); break
    case "uninstall": uninstall(); break
    case "status": status(); break
    case "run": run(rest); break
    case "validate": validate(); log(`${ROOT} is valid`); break
    case undefined: case "help": case "-h": case "--help": log(USAGE); break
    default: fail(`unknown command: ${command}\n\n${USAGE}`)
  }
} catch (err) {
  if (!(err instanceof CliError)) throw err
  console.error(`mullvad-plugin: ${err.message}`)
  process.exitCode = 1
}
