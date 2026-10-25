const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

// Optionally derive the fixture selector from the installed BeamNG component.
// Its inheritAttrs:false drops the class supplied on RLS's component tag.
const nativeMenuSelector = process.argv[2]
  ? "." + /ref="popoverMenu" class="([^"]+)"/.exec(fs.readFileSync(process.argv[2], "utf8"))[1]
  : ".bng-popover-menu"

let observe
const tiles = []
const menus = []
const calls = []
const checks = []
function tile(text) {
  const classes = new Set()
  const label = {textContent: text}
  const icon = {classList: {toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) }}}
  const item = {
    nodeType: 1, label, classes,
    querySelector: selector => selector === ".label" ? label : icon,
    closest: selector => selector === ".computer-function-tile" ? item : null,
    querySelectorAll: () => [],
  }
  tiles.push(item)
  return item
}
const strip = tile("Strip for Parts (5% value)")
const normal = tile("Repair")
const findAll = selector => selector === ".computer-function-tile" ? tiles : selector === nativeMenuSelector ? menus : []
const body = {nodeType: 1, closest: () => null, querySelectorAll: findAll}
let css
vm.runInNewContext(fs.readFileSync("ui/modModules/rlsCarjacking/rlsCarjacking.js", "utf8"), {
  angular: {module(name, deps) { assert.equal(name, "rlsCarjacking"); return {run: fn => fn()} }},
  document: {head: {appendChild: element => { css = element.textContent }}, body, querySelectorAll: findAll, createElement: () => ({})},
  window: {addEventListener: () => {}, bngApi: {engineLua(code, callback) {
    calls.push(code)
    if (callback) checks.push(callback)
  }}},
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

const setup = {vehSelected: null, vehicleInventoryStore: {vehicleInventoryData: {buttonsActive: {sellEnabled: true}}}}
const menuButtons = []
const template = {cloneNode(deep) {
  assert.equal(deep, false)
  const button = {
    removed: false, classList: {add() {}}, removeAttribute() {},
    addEventListener(event, fn) { assert.equal(event, "click"); this.click = fn },
    remove() { this.removed = true },
  }
  return button
}, parentElement: {appendChild(button) { menuButtons.push(button) }}}
const menu = {
  nodeType: 1, isConnected: true, __vueParentComponent: {parent: {setupState: setup}},
  closest: selector => selector === nativeMenuSelector ? menu : null,
  querySelectorAll: () => [], querySelector: () => template,
}
menus.push(menu)
const renderMenu = () => observe([{type: "childList", target: menu, addedNodes: []}])
setup.vehSelected = {id: 7, owned: true, inStorage: false}
renderMenu()
assert.equal(checks.length, 1)
assert.equal(calls.at(-1), "career_modules_carjacking.canAbandonVehicle(7)")
checks.shift()(true)
assert.equal(menuButtons.at(-1).textContent, "Abandon")
menuButtons.at(-1).click({stopPropagation() {}})
assert.equal(calls.at(-1), "career_modules_carjacking.abandonVehicle(7)")
renderMenu()
assert.equal(menuButtons.length, 1, "mutations must not duplicate the action")

for (const change of [{location: "garage"}, {inStorage: true}, {inGarage: true}, {owned: false}, {timeToAccess: 60}, {listedForAuction: true}]) {
  setup.vehSelected = {id: 7, owned: true, inStorage: false, ...change}
  renderMenu()
  assert(menuButtons.at(-1).removed, "ineligible rows must have no abandon action")
  assert.equal(checks.length, 0)
}
setup.vehSelected = {id: 8, owned: true, inStorage: false}
renderMenu()
setup.vehSelected = {id: 9, owned: true, inStorage: false}
renderMenu()
checks.shift()(true)
assert.equal(menuButtons.length, 1, "a stale Lua response must not act on another car")
checks.shift()(true)
assert.equal(menuButtons.length, 2)
setup.vehicleInventoryStore.vehicleInventoryData.buttonsActive.sellEnabled = false
renderMenu()
assert(menuButtons.at(-1).removed, "other vehicle pickers must not show Abandon")
console.log("PASS: My Vehicles abandon placement, eligibility, Lua callback and stale-selection protection")
