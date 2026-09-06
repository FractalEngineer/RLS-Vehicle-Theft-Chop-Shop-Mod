-- Run from repository root with Lua 5.1+ (or tools/validate_release.py).
local sourcePath = "lua/ge/extensions/career/modules/carjacking.lua"
assert(loadfile(sourcePath))
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
  career_career = {closeAllMenus = function() state.closed = true end}
  career_modules_inventory = {
    getVehicles = function() return state.vehicles end,
    getVehicleIdFromInventoryId = function(id) return state.ids[id] end,
    getInventoryIdFromVehicleId = function(id) return id == state.ids[7] and 7 or nil end,
    updatePartConditions = function(_, _, callback) state.callback = callback end,
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
  if type(value) == "function" and name ~= "message" then
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

-- Identity completion restores normal reputation once, including old saves.
s = fixture(100)
local discount = upvalue(s.mod.onVehicleAdded, "applyStolenMarketDiscount")
local vehicle = s.vehicles[7]
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
print("PASS: strip confirmation/transactions, identity valuation/migration, parking, traffic")
