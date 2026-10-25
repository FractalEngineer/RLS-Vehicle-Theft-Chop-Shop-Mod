-- Run from repository root with Lua 5.1+ (or tools/validate_release.py).
local sourcePath = "lua/ge/extensions/career/modules/carjacking.lua"
assert(loadfile(sourcePath))
local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, item in pairs(value) do copy[key] = deepCopy(item) end
  return copy
end
deepcopy = deepCopy
local function upvalue(fn, name)
  for i = 1, 100 do
    local key, value = debug.getupvalue(fn, i)
    if key == name then return value end
    if not key then break end
  end
  error("Missing upvalue " .. name)
end

local function fixture(value)
  local vehicle = {rlsCarjack = {stolen = true}, partConditions = {body = {integrityValue = 0.4}}}
  local state = {vehicles = {[7] = vehicle}, ids = {[7] = 70}, objects = {}, paid = 0, sales = 0, messages = {}, queued = {}, player = -1}
  local obj = {
    getID = function() return 70 end,
    getRefNodeId = function() return 0 end,
    queueLuaCommand = function(_, cmd) table.insert(state.queued, cmd) end,
    applyClusterVelocityScaleAdd = function(_, ref, scale, x, y, z)
      assert(scale == 0 and x == 0 and y == 0 and z == 0)
      state.stops = (state.stops or 0) + 1
    end,
  }
  state.objects[70] = obj
  getObjectByID = function(id) return state.objects[id] end
  ui_message = function(msg) table.insert(state.messages, msg) end
  log = function() end
  be = {getPlayerVehicleID = function() return state.player end}
  career_career = {isActive = function() return true end, closeAllMenus = function() state.closed = true end}
  career_modules_inventory = {
    getVehicles = function() return state.vehicles end,
    getVehicleIdFromInventoryId = function(id) return state.ids[id] end,
    getInventoryIdFromVehicleId = function(id) return id == state.ids[7] and 7 or nil end,
    updatePartConditions = function(_, _, callback) state.callback = callback end,
    removeVehicle = function(id)
      state.removed = (state.removed or 0) + 1
      state.vehicles[id] = nil
      state.ids[id] = nil
    end,
    sendVehicleUpdatesToUi = function() state.uiUpdates = (state.uiUpdates or 0) + 1 end,
    openMenu = function(buttons, header, active)
      state.menu = {buttons = buttons, header = header, active = active}
    end,
    sellVehicle = function(id, payout)
      state.sales = state.sales + 1
      state.paid = state.paid + payout
      state.vehicles[id] = nil
      return true
    end,
  }
  career_modules_valueCalculator = {getInventoryVehicleValue = function() return value end}
  guihooks = {trigger = function(event, dialog)
    assert(event == "showConfirmationDialog")
    state.dialog = dialog
  end}
  state.mod = dofile(sourcePath)
  career_modules_carjacking = state.mod
  state.confirm = function(accepted)
    assert(state.dialog, "expected a confirmation popup")
    local button = state.dialog.buttons[accepted and 2 or 1]
    return assert((loadstring or load)(button.luaCallback))()
  end
  return state, obj
end

local s = fixture(10000)
assert(s.mod.stripVehicleForParts("7"))
assert(s.closed and s.sales == 0, "wait for current damage before paying")
assert(not s.mod.stripVehicleForParts(7), "duplicate request must be ignored")
s.callback()
s.callback()
assert(s.sales == 0, "condition callback must only show a confirmation")
assert(s.dialog.buttons[1].default and s.dialog.buttons[1].isCancel)
assert(s.dialog.buttons[2].isConfirm and s.dialog.buttons[2].isDestructive)
assert(s.dialog.text:find("$500", 1, true) and s.dialog.text:find("#7", 1, true))
s.confirm(true)
s.confirm(true)
assert(s.sales == 1 and s.paid == 500, "pay exactly once")

s = fixture(0)
s.mod.stripVehicleForParts(7)
s.callback()
s.confirm(true)
assert(s.sales == 1 and s.paid == 1, "totaled cars remain disposable")

s = fixture(100)
s.vehicles[7].niceName = "My <car> & truck"
s.mod.stripVehicleForParts(7)
s.callback()
assert(s.dialog.text:find("My &lt;car&gt; &amp; truck", 1, true))
s.confirm(false)
s.confirm(true)
assert(s.sales == 0, "Cancel and stale confirmation must not sell")
assert(s.mod.stripVehicleForParts(7), "Cancel must allow a new request")
s.callback()
s.confirm(true)
assert(s.sales == 1)

s = fixture(100)
s.vehicles[7].rlsCarjack = nil
assert(not s.mod.stripVehicleForParts(7) and not s.callback, "ordinary owned vehicles cannot be stripped")
s = fixture(100)
s.vehicles[7].owned = true
local abandonVehicle = s.mod.abandonVehicle
assert(abandonVehicle(7) and s.dialog, "abandon must use a confirmation popup")
assert(s.dialog.buttons[1].default and s.dialog.buttons[1].isCancel)
assert(s.dialog.buttons[2].isConfirm and s.dialog.buttons[2].isDestructive)
assert(not s.dialog.text:find("$", 1, true), "abandon must be free")
assert(s.dialog.buttons[2].label == "Abandon" and not s.dialog.text:find("fee", 1, true))
s.confirm(true)
assert(s.removed == 1 and s.sales == 0 and s.paid == 0, "abandon must remove without a sale")
s = fixture(100)
s.vehicles[7].owned = true
abandonVehicle = s.mod.abandonVehicle
assert(abandonVehicle(7))
s.confirm(false)
assert(not s.removed, "cancelled abandon must keep the vehicle")
s.ids[7] = nil
assert(not abandonVehicle(7), "stored vehicles cannot be abandoned remotely")
s = fixture(100)
s.vehicles[7].owned = true
s.vehicles[7].location = "belascoGarage"
assert(not s.mod.abandonVehicle(7), "live cars assigned to a garage are excluded")
s.vehicles[7].location = nil
assert(s.mod.abandonVehicle(7))
s.vehicles[7].location = "belascoGarage"
s.confirm(true)
assert(not s.removed, "garage assignment must be rechecked at confirmation")
s = fixture(100)
s.vehicles[7].owned = true
career_modules_inventory.getInventoryIdsInClosestGarage = function() return {7} end
assert(not s.mod.abandonVehicle(7), "unassigned cars physically in the garage are excluded")
local computerFunctions = {general = {}, vehicleSpecific = {}}
s.mod.onComputerAddFunctions({vehiclesInGarage = {}}, computerFunctions)
assert(next(computerFunctions.general) == nil, "Abandon must never add a main computer tile")
s = fixture(100)
s.mod.stripVehicleForParts(7)
s.callback()
s.vehicles[7] = {rlsCarjack = {stolen = true}}
s.confirm(true)
assert(s.sales == 0, "confirmation must bind to the exact original vehicle")
s = fixture(100)
s.mod.stripVehicleForParts(7)
s.callback()
career_modules_valueCalculator.getInventoryVehicleValue = function() return 200 end
s.confirm(true)
assert(s.sales == 0, "changed quote needs a new confirmation")
for _, value in ipairs({-1, math.huge, 0/0}) do
  s = fixture(value)
  s.mod.stripVehicleForParts(7)
  s.callback()
  assert(s.sales == 0, "invalid values must not remove a car")
end
s = fixture(100)
s.vehicles[7].listedForAuction = true
assert(not s.mod.stripVehicleForParts(7) and not s.callback)
s.vehicles[7].listedForAuction = nil
s.vehicles[7].timeToAccess = 5
assert(not s.mod.stripVehicleForParts(7) and not s.callback)

s = fixture(100)
s.mod.stripVehicleForParts(7)
local pending = upvalue(s.mod.stripVehicleForParts, "pendingStrips")
-- Isolate the real onUpdate timeout from unrelated pursuit/economy subsystems.
for i = 1, 100 do
  local name, value = debug.getupvalue(s.mod.onUpdate, i)
  if not name then break end
  if type(value) == "function" and name ~= "message" and name ~= "refreshRlsModules" then
    debug.setupvalue(s.mod.onUpdate, i, function() end)
  end
end
s.mod.onUpdate(11, 0, 11)
assert(pending[7] == nil, "condition request must time out")
s.callback()
assert(s.sales == 0, "late callback after cancellation must not sell")
s = fixture(100)
s.mod.stripVehicleForParts(7)
s.vehicles[7] = {rlsCarjack = {stolen = true}}
s.callback()
assert(s.sales == 0, "reused inventory ID must not sell a different car")
s = fixture(100)
career_modules_inventory.updatePartConditions = function() error("bridge failure") end
assert(not s.mod.stripVehicleForParts(7) and s.sales == 0)

-- Retrieve the SAME live object after the old spawn monitor has seen it.
local obj
s, obj = fixture(100)
s.mod.onTeleportedToGarage("garage", obj)
assert(#s.queued == 1 and s.stops == 1)
local monitor = upvalue(s.mod.onUpdate, "monitorRetrievedStolenVehicles")
for i = 1, 100 do monitor(0) end
assert(#s.queued == 1, "paused frames must not exhaust/queue the guard")
monitor(0.1)
assert(#s.queued == 2)
for i = 1, 20 do monitor(0.2) end
local count = #s.queued
monitor(1)
assert(#s.queued == count, "parking guard must stop")
s.mod.onTeleportedToGarage("garage", obj)
assert(#s.queued == count + 1, "same-ID retrieval must restart guard")
s.player = 70
monitor(0.2)
assert(#s.queued == count + 1, "player entry must release guard")
s.mod.onTeleportedToGarage("garage", obj)
assert(#s.queued == count + 1)
s.player = -1
s.vehicles[7].rlsCarjack = nil
s.mod.onTeleportedToGarage("garage", obj)
assert(#s.queued == count + 1, "ordinary cars must be untouched")

-- Execute the actual queued vehicle-Lua payload; no damage/reset API is provided.
local payload = assert((loadstring or load)(s.queued[1]))
local controls = {}
FILTER_DIRECT = 0
playerInfo = {anyPlayerSeated = false}
ai = {setMode = function(mode) controls.ai = mode end}
input = {event = function(name, value) controls[name] = value end}
controller = {mainController = {
  shiftToGearIndex = function(gear) controls.gear = gear end,
  setStarter = function(on) controls.starter = on end,
  setEngineIgnition = function(on) controls.engine = on end,
}}
powertrain = {getDevice = function() return nil end, reset = function() error("damage reset forbidden") end}
electrics = {setIgnitionLevel = function(level) controls.ignition = level end}
payload()
assert(controls.ai == "disabled" and controls.gear == 0 and controls.parkingbrake == 1)
assert(controls.throttle == 0 and controls.clutch == 0 and controls.brake == 0)
assert(controls.starter == false and controls.engine == false and controls.ignition == 0)
controls = {}
playerInfo.anyPlayerSeated = true
payload()
assert(next(controls) == nil, "queued command must recheck player entry")

-- Native pool replacement retires old debts instead of expanding a new pool.
s = fixture(100)
local backfill = upvalue(s.mod.onUpdate, "processTrafficBackfill")
local debts = upvalue(backfill, "trafficReplacementDebts")
local firstReady = upvalue(backfill, "firstReadyTrafficDebt")
local pool = {}
core_vehicleActivePooling = {getPool = function() return pool end}
debts[70] = {pool = pool, ready = true, model = "test", config = "test"}
assert(firstReady() == 70)
pool = {}
assert(firstReady() == nil and next(debts) == nil)

-- Restore exactly one current-pool debt; insertion needs no global activation.
local spawned = 0
local traffic = {}
local replacement = {getID = function() return 71 end, getActive = function() return false end}
core_vehicles = {spawnNewVehicle = function(model, options)
  assert(model == "test" and options.config == "original")
  assert(options.autoEnterVehicle == false)
  spawned = spawned + 1
  return replacement
end}
gameplay_traffic = {
  getState = function() return "on" end,
  insertTraffic = function(id, ignoreAi) assert(id == 71 and ignoreAi == false); traffic[id] = {} end,
  getTrafficData = function() return traffic end,
}
debts[70] = {pool = pool, ready = true, model = "test", config = "original"}
backfill(1)
backfill(1)
assert(spawned == 1 and next(debts) == nil and not pool._updateFlag)

-- BeamNG 0.40 reserved/claimed provider traffic is not carjackable.
gameplay_walk = {
  toggleWalkingMode = function() end,
  isWalking = function() return false end,
  getVehicleInFront = function() return nil end,
}
s.mod.onExtensionLoaded()
local installWalkingMode = upvalue(s.mod.onUpdate, "installWalkingModeWrapper")
local walkingWrapper = upvalue(installWalkingMode, "wrappedToggleWalkingMode")
local findTarget = upvalue(walkingWrapper, "findJackTarget")
local isJackableTraffic = upvalue(findTarget, "isJackableTrafficVehicle")
local reservedTraffic = upvalue(isJackableTraffic, "isReservedTrafficVehicle")
assert(reservedTraffic({isAi = true, reserved = "taxi"}))
assert(reservedTraffic({isAi = true, claimed = "taxi"}))
assert(not reservedTraffic({isAi = true}))
gameplay_walk.isVehicleBlacklisted = function() return true end
s.objects[81] = {
  getActive = function() return true end,
  getJBeamFilename = function() return "simple_traffic" end,
}
assert(not isJackableTraffic(81, {isAi = true}, true), "shell traffic cannot become inventory")
s.objects[81].getJBeamFilename = function() return "etk800" end
assert(isJackableTraffic(81, {isAi = true}, true))
settings = {
  value = true,
  getValue = function(name)
    assert(name == "trafficSimpleVehicles")
    return settings.value
  end,
  setValue = function(name, value)
    assert(name == "trafficSimpleVehicles")
    settings.value = value
  end,
}
local ensureFullDetail = upvalue(s.mod.onUpdate, "ensureFullDetailTrafficVehicles")
local restoreFullDetail = upvalue(s.mod.onExtensionUnloaded, "restoreFullDetailTrafficVehicleSetting")
assert(ensureFullDetail() and settings.value == false)
assert(restoreFullDetail() and settings.value == true)

-- Street vehicle identity is restored after RLS's later part-inventory hook.
s = fixture(100)
s.vehicles[7].rlsCarjack.source = "streetTraffic"
s.vehicles[7].rlsCarjack.streetGeneratedYear = 1987
s.vehicles[7].rlsCarjack.streetGeneratedMileage = 123456789
s.vehicles[7].year = 2026
s.vehicles[7].mileage = 0
s.mod.onAddedVehiclePartsToInventory(7, {})
local restoreStreet = upvalue(s.mod.onUpdate, "pendingStreetIdentityRestore")
assert(restoreStreet[7])
s.vehicles[7].year = 2026
s.mod.onUpdate(0.1, 0.1)
assert(s.vehicles[7].year == 1987 and s.vehicles[7].mileage == 123456789)
assert(restoreStreet[7] == nil)

-- A recovered laundered car keeps the new identity unless the player has
-- deliberately repainted it to a different legitimate colour.
s = fixture(100)
local vehicle = s.vehicles[7]
local prePaint = {baseColor = {0.1, 0.2, 0.3, 1}}
local newPaint = {baseColor = {0.7, 0.8, 0.9, 1}}
local laterPaint = {baseColor = {0.2, 0.6, 0.4, 1}}
vehicle.config = {}
vehicle.config.paints = {prePaint, prePaint, prePaint}
vehicle.rlsCarjack = {
  stolen = true,
  identityChanged = true,
  identityPaintRecoveryInitialized = true,
  changedIdentityPlate = "NEW-123",
  preIdentityPaints = {prePaint, prePaint, prePaint},
  changedIdentityPaints = {newPaint, newPaint, newPaint},
}
career_modules_inventory.setVehicleDirty = function() end
s.mod.onVehiclePartConditionsChanged(7)
assert(vehicle.config.licenseName == "NEW-123")
assert(vehicle.config.paints[1].baseColor[1] == 0.7)
vehicle.config.paints = {laterPaint, laterPaint, laterPaint}
s.mod.onVehiclePartConditionsChanged(7)
assert(vehicle.config.paints[1].baseColor[1] == 0.2, "later legitimate repaint must survive")
s.mod.onTeleportedToGarage("garage", s.objects[70])
local restoreLaundered = upvalue(s.mod.onUpdate, "pendingLaunderedIdentityRestore")
assert(restoreLaundered[7], "garage recovery must restart identity reconciliation")

-- Identity completion restores normal reputation once, including old saves.
s = fixture(100)
local discount = upvalue(s.mod.onVehicleAdded, "applyStolenMarketDiscount")
vehicle = s.vehicles[7]
local data = vehicle.rlsCarjack
local dirty = 0
career_modules_inventory.setVehicleDirty = function() dirty = dirty + 1 end
vehicle.meetReputation = 20
discount(7)
assert(vehicle.meetReputation < 0 and data.marketOriginalMeetReputation == 20)
data.identityChanged = true
assert(discount(7))
assert(vehicle.meetReputation == 20 and data.marketValueMultiplier == 1 and data.marketDiscountMeetReputation == nil)
vehicle.meetReputation = 25
local previousDirty = dirty
assert(not discount(7) and vehicle.meetReputation == 25 and dirty == previousDirty)
data.identityChanged = nil
data.vinChanged = true
data.marketValueMultiplier = 0.35
data.marketDiscountMeetReputation = -58
vehicle.meetReputation = -58
assert(discount(7) and vehicle.meetReputation == 20, "migrate legacy identity change")

s = fixture(100)
vehicle = s.vehicles[7]
vehicle.meetReputation = 10
discount = upvalue(s.mod.onVehicleAdded, "applyStolenMarketDiscount")
discount(7)
local processIdentity = upvalue(s.mod.onUpdate, "processPendingIdentityChanges")
local finalize = upvalue(processIdentity, "finalizeVehicleIdentityChange")
for i = 1, 100 do
  local name = debug.getupvalue(finalize, i)
  if not name then break end
  if name == "applyRandomIdentityPaint" or name == "applyRandomIdentityPlate" then
    debug.setupvalue(finalize, i, function() return "test" end)
  end
end
assert(finalize(7, 100))
assert(vehicle.rlsCarjack.identityChanged and vehicle.meetReputation == 10, "restore value immediately on completion")

-- RLS 2.8 moved career modules to the overhaul_* namespace. Prefer those over
-- any stock/legacy globals and join RLS's walking patch chain.
career_career = {isActive = function() return false end}
career_modules_inventory = {
  getVehicles = function() return {[7] = {rlsCarjack = {stolen = false}}} end,
}
overhaul_career_career = {isActive = function() return true end}
overhaul_career_saveSystem = {}
overhaul_career_garage_inventory = {
  getVehicles = function() return {[7] = {rlsCarjack = {stolen = true}}} end,
}
overhaul_career_repair_insurance = {}
overhaul_career_market_valueCalculator = {}
overhaul_career_market_inspectVehicle = {}
overhaul_career_market_vehicleShopping = {}
overhaul_career_market_testDrive = {}
overhaul_career_economy_playerAttributes = {}
overhaul_career_progression_reputation = {}
overhaul_career_economy_payment = {}
overhaul_career_police_speedTraps = {}
overhaul_integration_services_police = {}
local overhaulMod = dofile(sourcePath)
career_modules_carjacking = overhaulMod
assert(overhaulMod.isStolenInventoryVehicle(7), "RLS 2.8 inventory namespace must take precedence")
assert(type(overhaulMod.onOverhaulVehicleAdded) == "function")
assert(type(overhaulMod.onOverhaulAddedVehiclePartsToInventory) == "function")
assert(type(overhaulMod.onOverhaulVehiclePartConditionsChanged) == "function")
assert(type(overhaulMod.onOverhaulRepairInGarage) == "function")
assert(type(overhaulMod.onOverhaulComputerAddFunctions) == "function")
assert(type(overhaulMod.onOverhaulModulesActivated) == "function")

local patchRegistered, patchUnregistered
overhaul_shell_patches = {
  registerFields = function(id, _, wrappers)
    assert(id == "rlsCarjackingWalkingEntry")
    assert(type(wrappers.toggleWalkingMode) == "function")
    patchRegistered = true
    return true
  end,
  unregister = function(id)
    assert(id == "rlsCarjackingWalkingEntry")
    patchUnregistered = true
    return true
  end,
}
local originalToggle = function() end
gameplay_walk = {
  toggleWalkingMode = originalToggle,
  isWalking = function() return true end,
}
local installOverhaulWalking = upvalue(overhaulMod.onUpdate, "installWalkingModeWrapper")
assert(installOverhaulWalking() and patchRegistered)
assert(gameplay_walk.toggleWalkingMode == originalToggle, "must not overwrite RLS's walking patch chain")
overhaulMod.onOverhaulActive(false)
assert(patchUnregistered)

local sourceText = assert(io.open(sourcePath, "r")):read("*a")
assert(not sourceText:find("setPursuitMode(cfg.policeCarjackLevel, vehId, {})", 1, true),
  "police heat must never be assigned with an empty responder list")
assert(sourceText:find('getPool("autoTraffic")', 1, true),
  "native traffic pool lookup must use the 0.40 pool name")
assert(not sourceText:find("spawnPoliceResponder", 1, true),
  "RLS 2.8 must own police spawning instead of the legacy fallback responder")
assert(not sourceText:find("pool._updateFlag = true", 1, true),
  "removeTraffic already owns active-pool reconciliation")
assert(not sourceText:find("police.setupPursuitGameplay(", 1, true),
  "starting theft heat must not recreate roles or reset existing pursuit state")
assert(sourceText:find("ensureReservedVehicles", 1, true)
  and sourceText:find("useReservedVehicle", 1, true),
  "police heat must refill and claim a native reserved police vehicle")
local nativeTraffic = {
  [10] = {
    role = {name = "standard"},
    pursuit = {mode = 0, score = 0},
  },
}
gameplay_traffic.getTrafficData = function() return nativeTraffic end
local nativeSetModeCalled = false
local policyRegistered, policyRemoved
package.preload['overhaul/lib/vehicles/policy'] = function()
  return {register = function(owner, domains, lifetime)
    assert(owner == 'rlsCarjackingPursuitHandoff' and type(domains.roleLocked) == 'function' and lifetime == 'loaded')
    policyRegistered = true
    return function() policyRemoved = true end
  end}
end
local nativePolice = {
  setPursuitMode = function(mode, suspectId, policeIds)
    assert(mode == 3 and suspectId == 10 and policeIds[1] == 20)
    nativeSetModeCalled = true
    nativeTraffic[10].role.name = "suspect"
    nativeTraffic[10].pursuit.mode = mode
  end,
  getPursuitVars = function() return {scoreLevels = {150, 900, 2800}} end,
}
local beginNativePursuit = upvalue(upvalue(overhaulMod.onUpdate, "processImmediateAlert"),
  "beginStolenPolicePursuit")
assert(beginNativePursuit(nativePolice, 10, {20}, "test", 3))
assert(nativeTraffic[10].role.name == "suspect" and nativeTraffic[10].pursuit.mode == 3)
assert(nativeSetModeCalled, "native pursuit setup must start the seeded level explicitly")
assert(policyRegistered and policyRemoved, "RLS role protection must be scoped to native startup")
local reserveEnsured, reserveUseAttempts = 0, 0
gameplay_traffic.ensureReservedVehicles = function(provider, count)
  assert(provider == "rlsCarjackingPolice" and count == 1)
  reserveEnsured = reserveEnsured + 1
  return true
end
gameplay_traffic.useReservedVehicle = function(provider, count)
  assert(provider == "rlsCarjackingPolice" and count == 1)
  reserveUseAttempts = reserveUseAttempts + 1
  return {20}
end
local processMaximumHeat = upvalue(overhaulMod.onUpdate, "processMaximumHeat")
local requestReserve = upvalue(processMaximumHeat, "requestNativePoliceReserve")
local pendingReserve = upvalue(requestReserve, "pendingPoliceReserve")
s.objects[10] = {getActive = function() return true end}
be.getPlayerVehicleID = function() return 10 end
overhaul_career_garage_inventory.getInventoryIdFromVehicleId = function(id) return id == 10 and 7 or nil end
assert(requestReserve(10, 7) and reserveEnsured == 1)
overhaulMod.onTrafficReservedVehiclesReady("police")
assert(reserveUseAttempts == 0, "must not claim RLS's own service reserve")
overhaulMod.onTrafficReservedVehiclesReady("rlsCarjackingPolice")
pendingReserve = upvalue(requestReserve, "pendingPoliceReserve")
assert(reserveUseAttempts == 1 and pendingReserve.reserveId == 20 and pendingReserve.settleTimer == 0.75,
  "native police reserve must be claimed after its ready hook and settled before pursuit setup")
nativeTraffic[20] = {state = "active"}
s.objects[20] = {getActive = function() return true end}
local processPendingReserve = upvalue(overhaulMod.onUpdate, "processPendingPoliceReserve")
processPendingReserve(0.25)
processPendingReserve(0.25)
pendingReserve = upvalue(requestReserve, "pendingPoliceReserve")
assert(math.abs(pendingReserve.settleTimer - 0.25) < 1e-9,
  "native police reserve settle time must advance every frame")
assert(sourceText:find('provider = "rlsCarjackingPolice"', 1, true),
  "fallback must use its own native provider without replacing ambient police")
local filterMarked = upvalue(overhaulMod.onTrafficSpecialVehiclesProviders, "filterMarkedPoliceSpecs")
local markedGroup = filterMarked({
  {model = "fullsize", config = "bcpd"},
  {model = "bastion", config = "police_unmarked_v8_awd_A"},
  {model = "roamer", config = "police"},
  {model = "roamer", config = "undercover"},
}, 2)
assert(#markedGroup == 2)
assert(markedGroup[1].config == "bcpd" and markedGroup[2].config == "police")
local fallbackGroup = filterMarked({
  {model = "bastion", config = "police_unmarked_v8_awd_A"},
  {model = "roamer", config = "undercover"},
}, 2)
assert(#fallbackGroup == 2)
assert(fallbackGroup[1].config == "bcpd" and fallbackGroup[2].config == "police",
  "marked police fallback must never leak undercover configurations")
assert(#filterMarked({}, 1) == 1, "an empty native sample must still produce a marked fallback")

local registeredProvider, returnedReserves = nil, 0
gameplay_traffic.registerSpecialVehicleProvider = function(provider) registeredProvider = provider end
gameplay_traffic_trafficUtils = {createPoliceGroup = function() return {} end}
overhaulMod.onTrafficSpecialVehiclesProviders()
assert(registeredProvider.name == "rlsCarjackingPolice" and registeredProvider.getDesiredCount(100, {police = true}) == 0)
assert(not registeredProvider.reserved, "must not add a standing reserve to normal traffic")
assert(#registeredProvider.buildGroup(1) == 1, "must supply a marked fallback even for an empty sample")
gameplay_traffic.returnReservedVehicle = function(ids)
  assert(ids[1] == 20)
  returnedReserves = returnedReserves + 1
end
overhaul_integration_services_police = nativePolice
upvalue(overhaulMod.onUpdate, "refreshRlsModules")()
processPendingReserve(0.25)
assert(upvalue(requestReserve, "pendingPoliceReserve") == nil)
assert(returnedReserves == 0, "an engaged reserve must stay claimed until pursuit completion")
overhaulMod.onPursuitAction(99, "evade")
assert(returnedReserves == 0, "another pursuit must not release this responder")
overhaulMod.onPursuitAction(10, "evade")
overhaulMod.onPursuitAction(10, "release")
assert(returnedReserves == 1, "native completion must return the reserve exactly once")

-- A native idle police object should be woken before creating a fallback.
local poolWakes = 0
local position = {distance = function() return 100 end}
s.objects[10].getPosition = function() return position end
s.objects[20].getPosition = function() return position end
be.getObjectActive = function() return false end
nativeTraffic[20].role = {name = "police", state = "none", flags = {}}
nativePolice.getPoliceVehicles = function() return {[20] = nativeTraffic[20]} end
core_vehicleActivePooling = {getPool = function(name)
  assert(name == "autoTraffic")
  return {setVeh = function(_, id, active)
    assert(id == 20 and active == true)
    poolWakes = poolWakes + 1
    return true
  end}
end}
local previousEnsureCount = reserveEnsured
assert(requestReserve(10, 7))
assert(poolWakes == 1 and reserveEnsured == previousEnsureCount,
  "existing native pool police must get the first activation attempt")
pendingReserve = upvalue(requestReserve, "pendingPoliceReserve")
assert(pendingReserve.reserveId == 20 and not pendingReserve.isNative)
processPendingReserve(1)
assert(returnedReserves == 1, "an ordinary pool member must not be returned as a reserve")
nativeTraffic[20].role = {name = "police", state = "chase", targetId = 99, targetPursuitMode = 3, flags = {busy = 1}}
assert(requestReserve(10, 7))
assert(poolWakes == 1 and reserveEnsured == previousEnsureCount + 1,
  "a responder busy in another pursuit must not be woken or retargeted")

-- On-foot pursuit handoff: RLS 2.8 leaves the pursuit on the abandoned car.
-- The opt-out is enabled by default and must move the pursuit to the player.
s = fixture(100)
local handoffTraffic = {
  [10] = {
    role = {name = "suspect"},
    pursuit = {mode = 2, score = 500, policeVisible = true, timers = {}},
  },
}
handoffTraffic[10].setRole = function(self, name) self.role.name = name end
local handoffCalls = {}
local handoffResponders = {[20] = {role = {targetId = 10}}, [21] = {role = {targetId = 99}}}
local handoffPolice = {
  getPoliceVehicles = function() return handoffResponders end,
  setPursuitMode = function(mode, id, ids)
    table.insert(handoffCalls, {mode = mode, id = id, responders = ids})
    if handoffTraffic[id] then handoffTraffic[id].pursuit.mode = mode end
    for _, policeId in ipairs(ids or {}) do
      handoffResponders[policeId].role.targetId = id
    end
  end,
  arrestVehicle = function(id) handoffCalls.arrestId = id end,
}
overhaul_integration_services_police = handoffPolice
gameplay_traffic = {
  showMessages = false,
  getTrafficData = function() return handoffTraffic end,
  insertTraffic = function(id)
    if handoffTraffic[id] then handoffTraffic[id].registered = true return end
    if s.objects[id].jbeam == "unicycle" then return end -- real 0.40 isVehicle gate
    handoffTraffic[id] = {role = {name = "standard"}, pursuit = {mode = 0}, queuedFuncs = {}}
    handoffTraffic[id].setRole = function(self, name) self.role.name = name end
  end,
  removeTraffic = function(id) handoffTraffic[id] = nil end,
}
package.preload['gameplay/traffic/vehicle'] = function()
  return function(options)
    return {id = options.id, model = "unicycle", isPerson = true, isVehicle = false,
      role = {name = "empty"}, pursuit = {mode = 0}, queuedFuncs = {},
      postInit = function() end, setRole = function(self, name) self.role.name = name end}
  end
end
s.objects[10] = {jbeam = "fullsize", isPlayerControlled = function() return false end}
s.objects[11] = {jbeam = "unicycle", isPlayerControlled = function() return true end}
s.objects[12] = {jbeam = "fullsize", isPlayerControlled = function() return true end}

assert(s.mod.getConfig().restoreOnFootPursuitHandoff)
s.player = 11
s.mod.onVehicleSwitched(10, 11, 0)
assert(handoffTraffic[11], "bailing out must insert the player walker into traffic")
assert(handoffTraffic[11].role.name == "suspect" and handoffTraffic[11].pursuit.mode == 2,
  "the pursuit must follow the player on foot")
assert(handoffCalls[1].mode == 0 and handoffCalls[1].id == 10,
  "the abandoned car must no longer be the pursuit target")
assert(handoffTraffic[11].registered and handoffTraffic[11].isPerson and not handoffTraffic[11].isVehicle,
  "native registration must retain the person's classification and update lifecycle")
assert(handoffResponders[20].role.targetId == 11 and handoffResponders[21].role.targetId == 99,
  "only the existing chasing officer must follow the walker")
assert(not handoffTraffic[11].queuedFuncs.autoArrest,
  "leaving the car on foot must not force an arrest")

handoffCalls = {}
handoffTraffic[12] = {role = {name = "standard"}, pursuit = {mode = 0}, queuedFuncs = {}}
handoffTraffic[12].setRole = function(self, name) self.role.name = name end
s.player = 12
s.mod.onVehicleSwitched(11, 12, 0)
assert(handoffTraffic[12].role.name == "suspect" and handoffTraffic[12].pursuit.mode == 2,
  "entering another vehicle must take over the on-foot pursuit")
assert(handoffCalls[1].mode == 0 and handoffCalls[1].id == 11)
assert(not handoffTraffic[11], "retired player-only walker records must be removed natively")
assert(handoffTraffic[12].queuedFuncs.autoArrest
  and handoffTraffic[12].queuedFuncs.autoArrest.args[1] == 12,
  "re-entering a vehicle while visible must keep the native forced-arrest handoff")

s.mod.getConfig().restoreOnFootPursuitHandoff = false
handoffTraffic[10].pursuit.mode = 2
handoffCalls = {}
s.mod.onVehicleSwitched(10, 11, 0)
assert(#handoffCalls == 0, "disabling the option must keep RLS 2.8's car-bound pursuit")

-- Bailing out before the asynchronous reserve is ready must carry its target
-- onto the walker even if Abandon deletes the source car and inventory binding.
s.mod.getConfig().restoreOnFootPursuitHandoff = true
s.player = 10
s.objects[10].getPosition = function() return position end
handoffTraffic[10].pursuit.mode = 0
core_vehicleActivePooling = nil
handoffResponders[20].role.targetId = nil
handoffResponders[21].role.targetId = 99
handoffResponders[21].role.targetPursuitMode = 3
handoffResponders[21].role.flags = {busy = 1}
local pendingRequests = 0
gameplay_traffic.ensureReservedVehicles = function() pendingRequests = pendingRequests + 1 return true end
gameplay_traffic.useReservedVehicle = function() return {20} end
local pendingRequest = upvalue(upvalue(s.mod.onUpdate,'processMaximumHeat'),'requestNativePoliceReserve')
assert(pendingRequest(10,7) and pendingRequests == 1)
s.player = 11
s.mod.onVehicleSwitched(10,11,0)
local transferredPending = upvalue(pendingRequest,'pendingPoliceReserve')
assert(transferredPending.vehId == 11 and transferredPending.followPlayer)
s.objects[10], handoffTraffic[10] = nil, nil
s.mod.onVehicleDestroyed(10)
handoffTraffic[20] = {state='active',role={name='police',state='none',flags={}}}
s.objects[20] = {getActive=function() return true end}
s.mod.onTrafficReservedVehiclesReady('rlsCarjackingPolice')
upvalue(s.mod.onUpdate,'processPendingPoliceReserve')(1)
assert(handoffTraffic[11].pursuit.mode == 3 and handoffResponders[20].role.targetId == 11)
assert(not upvalue(pendingRequest,'pendingPoliceReserve'),
  'deleting the stolen car must not strand the on-foot reserve request')

print("PASS: strip confirmation/transactions, identity valuation/migration, parking, traffic")
