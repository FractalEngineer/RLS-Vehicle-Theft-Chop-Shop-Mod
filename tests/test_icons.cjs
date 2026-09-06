const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

let observe
const tiles = []
function tile(text) {
  const classes = new Set()
  const label = {textContent: text}
  const icon = {classList: {toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) }}}
  const item = {
    nodeType: 1, label, classes,
    querySelector: selector => selector === ".label" ? label : icon,
    closest: () => item,
    querySelectorAll: () => [],
  }
  tiles.push(item)
  return item
}
const strip = tile("Strip for Parts (5% value)")
const normal = tile("Repair")
const body = {nodeType: 1, closest: () => null, querySelectorAll: () => tiles}
let css
vm.runInNewContext(fs.readFileSync("ui/modModules/rlsCarjacking/rlsCarjacking.js", "utf8"), {
  angular: {module(name, deps) { assert.equal(name, "rlsCarjacking"); return {run: fn => fn()} }},
  document: {head: {appendChild: element => { css = element.textContent }}, body, createElement: () => ({})},
  window: {addEventListener: () => {}},
  MutationObserver: class { constructor(fn) { observe = fn } observe() {} disconnect() {} },
})
assert(strip.classes.has("rls-carjacking-strip-icon"))
assert.equal(normal.classes.size, 0)
assert(css.includes("/ui/modModules/rlsCarjacking/icons/strip_for_parts.svg"))
strip.label.textContent = "Tuning"
observe([{type: "characterData", target: {nodeType: 3, parentElement: strip}}])
assert.equal(strip.classes.size, 0, "reused tile must lose the strip icon")
const added = tile("Strip for Parts (12.5% value)")
observe([{type: "childList", target: body, addedNodes: [added]}])
assert(added.classes.has("rls-carjacking-strip-icon"))
console.log("PASS: custom strip icon, ordinary tiles unchanged, reused and newly rendered tiles")
