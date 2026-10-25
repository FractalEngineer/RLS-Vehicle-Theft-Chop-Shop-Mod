-- Run with the installed RLS and BeamNG source roots as arguments. No vendored game code.
local rlsRoot, beamRoot = ...
assert(rlsRoot and beamRoot, "RLS extension root and BeamNG Lua root required")
package.path = rlsRoot .. "/?.lua;" .. package.path
local function loadGame(relative) return assert(loadfile(beamRoot .. "/" .. relative))() end
package.preload['/lua/ge/extensions/gameplay/traffic/baseRole'] = function()
  return loadGame('ge/extensions/gameplay/traffic/baseRole.lua')
end
local function copy(v)
  if type(v) ~= 'table' then return v end
  local out = {} for k, item in pairs(v) do out[k] = copy(item) end return out
end
deepcopy = copy
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
tableMerge = function(a, b) for k, v in pairs(b) do a[k] = v end return a end
tableKeys = function(t) local keys = {} for k in pairs(t) do keys[#keys + 1] = k end return keys end
clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
square = function(v) return v*v end
vec3 = function() return {} end
randomGauss3 = function() return 0.5 end
log = function() end
ui_message = function() end
local traffic, starts, evades, depth = {}, 0, 0, 0
local objects = setmetatable({}, {__index = function(t, id)
  local obj = {queueLuaCommand = function() end}
  t[id] = obj return obj
end})
getObjectByID = function(id) return objects[id] end
be = {getPlayerVehicleID = function() return 10 end, getObjectActive = function() return true end}
gameplay_walk = {isWalking = function() return false end}
gameplay_traffic = {
  getTrafficData = function() return traffic end,
  getTrafficVars = function() return {baseAggression = 0.35} end,
  setTrafficVars = function() end,
}
overhaul_shell_gameMode = {isActive = function() return true end}
overhaul_career_garage_inventory = {
  getVehicles = function() return {[7] = {owned = true, role = 'standard'}} end,
  getInventoryIdFromVehicleId = function(id) return id == 10 and 7 end,
  getVehicleRole = function() return 'standard' end,
}
overhaul_integration_services_parking = {disableTracking = function() end, enableTracking = function() end}
overhaul_shell_extensionManager = {applyOverrideAI = function() end}
local policy = require('overhaul/lib/vehicles/policy')
local methods = require('overhaul/integration/ownedServices/trafficVehicle')
local service = require('overhaul/integration/services/police')
local police = setmetatable({}, {__index = function(_, key) return service.getDirect(key) end})
overhaul_integration_services_police = police
gameplay_police = police -- RLS's stock-service forwarding used by the native suspect role
local driving = require('overhaul/career/police/playerDriving')
local suspect = loadGame('ge/extensions/gameplay/traffic/roles/suspect.lua')
gameplay_traffic_trafficUtils = {getRoleConstructor = function(name)
  if name == 'suspect' then return suspect end
  return function(options)
    return require('/lua/ge/extensions/gameplay/traffic/baseRole')({init = function() end}, options)
  end
end}
extensions = {hook = function(event, id, action, data)
  if event ~= 'onPursuitAction' then return end
  depth = depth + 1
  assert(depth < 12, 'REPRODUCED: synchronous start/evade role recursion')
  if action == 'start' then starts = starts + 1 end
  if action == 'evade' then evades = evades + 1 end
  -- enforcement and policeTasklist both query this during onPursuitAction.
  assert(driving.getPlayerIsCop() == false)
  depth = depth - 1
end}
local function fixture()
  starts, evades, depth = 0, 0, 0
  policy._reset()
  local target = {
    id = 10, isAi = false, autoRole = 'standard', speed = 0,
    getTrafficVars = gameplay_traffic.getTrafficVars,
    modifyRespawnValues = function() end,
    setRole = methods.setRole,
    resetAll = function(self) self.pursuit = {mode = 0, score = 0} end,
  }
  target:resetAll()
  target.pursuit.offensesList = {}
  target.pursuit.timers = {main = 0, arrest = 0}
  traffic[10] = target
  target:setRole('standard')
  -- Use the real RLS responder role too: verifies target assignment and AI chase.
  local responder = {
    id = 20, isAi = true, getTrafficVars = gameplay_traffic.getTrafficVars,
    getTraffic = function() return traffic end,
    modifyRespawnValues = function() end, setAiMode = function(self, mode) self.aiMode = mode end,
    setAiParameters = function() end, resetElectrics = function() end,
  }
  responder.role = require('overhaul/integration/ownedServices/trafficPoliceRole')({veh = responder, name = 'police'})
  traffic[20] = responder
  police.getPoliceVehicles()[20] = responder
  return target, responder
end
fixture()
local ok, err = pcall(police.setPursuitMode, 3, 10, {20})
assert(not ok and tostring(err):find('REPRODUCED', 1, true), tostring(err))
assert(starts == 1 and evades > 1, 'must reproduce the actual recursive evade callback')
print('PASS: unprotected installed RLS 2.8 reproduces start/evade recursion')

local mod = dofile('lua/ge/extensions/career/modules/carjacking.lua')
local function upvalue(fn, name)
  for i = 1, 100 do local k, v = debug.getupvalue(fn, i) if k == name then return v end end
  error('Missing upvalue ' .. name)
end
local begin = upvalue(upvalue(mod.onUpdate, 'processImmediateAlert'), 'beginStolenPolicePursuit')
local target, responder = fixture()
assert(begin(police, 10, {20}, 'integration', 3))
assert(target.pursuit.mode == 3 and target.role.name == 'suspect')
assert(starts == 1 and evades == 0)
assert(responder.role.targetId == 10 and responder.role.targetPursuitMode == 3 and responder.aiMode == 'chase')
assert(#policy.owners() == 0, 'handoff policy must be withdrawn after native startup')
assert(begin(police, 10, {20}, 'existing pursuit', 2))
assert(starts == 1 and evades == 0 and target.pursuit.mode == 3, 'must preserve an existing chase')
police.evadeVehicle(10, false)
assert(evades == 1 and target.pursuit.mode == 0 and target.role.name == 'standard')
print('PASS: installed RLS start, marked responder chase, active pursuit preservation and normal evade')

fixture()
local savedStart = police.setPursuitMode
police.setPursuitMode = function() error('injected startup failure') end
assert(not begin(police, 10, {20}, 'failure', 3))
assert(#policy.owners() == 0, 'failed startup must also withdraw its policy')
police.setPursuitMode = savedStart
assert(begin(police, 10, {20}, 'retry', 3))
print('PASS: failed native call cleans up and permits a later start')

-- Exercise the actual 0.40 insertion gate and update-list registration, using
-- native traffic/vehicle with the same class methods RLS installs at runtime.
local V = {}
V.__index = V
function V:set(x, y, z)
  if type(x) == 'table' then self.x, self.y, self.z = x.x, x.y, x.z
  else self.x, self.y, self.z = x or 0, y or 0, z or 0 end
  return self
end
function V:squaredDistance(b) return (self.x-b.x)^2+(self.y-b.y)^2+(self.z-b.z)^2 end
function V:distance(b) return math.sqrt(self:squaredDistance(b)) end
function V:length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function V:z0() return vec3(self.x,self.y,0) end
function V:setScaled2(v, factor) return self:set(v.x*factor,v.y*factor,v.z*factor) end
function V:setAdd2(a,b) return self:set(a.x+b.x,a.y+b.y,a.z+b.z) end
vec3 = function(x,y,z) return setmetatable({},V):set(x,y,z) end
ColorF, ColorI = function() return {} end, function() return {} end
core_camera = {getPositionXYZ = function() return 0,0,0 end, getForwardXYZ = function() return 0,1,0 end}
arrayFindValueIndex = function(t, item) for i,v in ipairs(t) do if v == item then return i end end end
string.endswith = function(s, suffix) return s:sub(-#suffix) == suffix end
path = {splitWithoutExt = function(p) return '', p:match('([^/]+)%.pc$') end}
core_vehicles = {getModel = function(model)
  return {model = {Type = model == 'unicycle' and 'Prop' or 'Car'},
    configs = {police = {['Config Type'] = 'Police'}, base = {['Config Type'] = 'Factory'}}}
end}
settings = {getValue = function() return false end}
local playerId = 10
be.getPlayerVehicleID = function() return playerId end
package.preload['gameplay/traffic/roadTracking'] = function()
  return function() return {refresh = function() end} end
end
package.preload['gameplay/traffic/vehicle'] = function()
  local constructor = loadGame('ge/extensions/gameplay/traffic/vehicle.lua')
  local class = upvalue(constructor, 'C')
  for name, fn in pairs(methods) do class[name] = fn end
  return constructor
end
map = {objects = {}}
local queuedTargets = {}
local function engineObject(id, model, config)
  local obj = {
    jbeam = model, partConfig = 'vehicles/'..model..'/'..config..'.pc',
    initialNodePosBB = {getExtents = function() return {x=2,y=4} end},
    getJBeamFilename = function() return model end, setMeshAlpha = function() end,
    getDynDataFieldbyName = function() return nil end,
    getPosition = function() return map.objects[id].pos end,
    getID = function() return id end,
    getActive = function() return false end,
    setDynDataFieldbyName = function() end,
    isPlayerControlled = function() return id == playerId end,
    queueLuaCommand = function(_, cmd) queuedTargets[id] = cmd end,
  }
  objects[id] = obj
  map.objects[id] = {pos=vec3(),dirVec=vec3(0,1,0),vel=vec3(),damage=0}
  return obj
end
engineObject(10,'fullsize','base')
engineObject(11,'unicycle','base')
engineObject(12,'fullsize','base')
engineObject(20,'fullsize','police')
engineObject(21,'fullsize','police')
local stockRole = gameplay_traffic_trafficUtils.getRoleConstructor
gameplay_traffic_trafficUtils.getRoleConstructor = function(name)
  if name == 'police' then return require('overhaul/integration/ownedServices/trafficPoliceRole') end
  return stockRole(name)
end
local nativeTraffic = loadGame('ge/extensions/gameplay/traffic.lua')
gameplay_traffic = nativeTraffic
gameplay_traffic.showMessages = false
traffic = nativeTraffic.getTrafficData()
local previousHook = extensions.hook
extensions.hook = function(event, ...)
  if event == 'onTrafficAction' then police.onTrafficAction(...) end
  if event == 'onTrafficVehicleAdded' then police.onTrafficVehicleAdded(...) end
  if event == 'onTrafficVehicleRemoved' then police.onTrafficVehicleRemoved(...) end
  if event == 'onPursuitModeUpdate' then mod.onPursuitModeUpdate(...) end
  return previousHook(event, ...)
end
table.clear(police.getPoliceVehicles())
nativeTraffic.insertTraffic(10,true,true)
nativeTraffic.insertTraffic(20,true,true)
nativeTraffic.insertTraffic(21,true,true)
traffic[20].isAi, traffic[21].isAi = true, true
assert(begin(police,10,{20},'walking integration',3))
traffic[21].role.targetId = 99
traffic[21].role.targetPursuitMode = 3
traffic[21].role.flags.busy = 1
local startCount, evadeCount = starts, evades
playerId = 11
nativeTraffic.insertTraffic(11,true,true)
assert(not traffic[11], 'REPRODUCED: real 0.40 insertTraffic rejects the walker')
career_career = {isActive = function() return true end}
mod.onVehicleSwitched(10,11,0)
assert(traffic[11] and traffic[11].isPerson and not traffic[11].isVehicle)
assert(traffic[11].pursuit.mode == 3 and traffic[10].pursuit.mode == 0)
assert(traffic[20].role.targetId == 11 and traffic[20].role.targetPursuitMode == 3)
assert(traffic[21].role.targetId == 99, 'other ongoing pursuits must stay untouched')
assert(starts == startCount and evades == evadeCount, 'transfer must not emit a second outcome/start')
local sorted = upvalue(nativeTraffic.removeTraffic,'trafficIdsSorted')
assert(arrayFindValueIndex(sorted,11), 'walker must join the native update list')
traffic[11].enableTracking = false -- collision engine is outside this fixture
traffic[11].pursuit.timers.roadblock = 100
map.objects[11].pos = vec3(45,12,0)
traffic[11]:onUpdate(0.01,0.01)
assert(traffic[11].pos.x == 45 and traffic[11].pos.y == 12, 'native position updates must follow the walker')

-- Native RLS can run before our hook when entering another car. It clears the
-- old responders and queues an unfiltered pursuitChange; our continuation must
-- use the cached original responders and leave its autoArrest behavior intact.
for i=1,100 do
  local key = debug.getupvalue(nativeTraffic.getState,i)
  if key == 'state' then debug.setupvalue(nativeTraffic.getState,i,'on') break end
end
nativeTraffic.insertTraffic(12,true,true)
assert(upvalue(mod.onPursuitModeUpdate,'policeHandoff').responders[11][1] == 20, 'must cache the walking responder')
playerId = 12
police.onVehicleSwitched(11,12)
assert(upvalue(mod.onPursuitModeUpdate,'policeHandoff').responders[11][1] == 20, 'native clear must retain the transfer cache')
mod.onVehicleSwitched(11,12,0)
assert(traffic[12].pursuit.mode == 3 and not traffic[11])
assert(traffic[20].role.targetId == 12 and traffic[21].role.targetId == 99,
  'targets after native-first entry: '..tostring(traffic[20].role.targetId)..','..tostring(traffic[21].role.targetId))
assert(not traffic[12].queuedFuncs.pursuitChange, 'must replace the all-police deferred retarget')
assert(not arrayFindValueIndex(sorted,11), 'retired person leaves the native update list')
assert(starts == startCount and evades == evadeCount)
print('PASS: native walker insertion gate, moving target, responder-only handoff and either RLS hook order')

-- Reuse the actual native provider reserve after RLS pursuitEnd. The old code
-- repeatedly claimed/rejected this same disabled unit instead of dispatching it.
local maxHeat = upvalue(mod.onUpdate,'processMaximumHeat')
local requestReserve = upvalue(maxHeat,'requestNativePoliceReserve')
local processReserve = upvalue(mod.onUpdate,'processPendingPoliceReserve')
local handoffState = upvalue(mod.onPursuitModeUpdate,'policeHandoff')
local eventHook = extensions.hook
extensions.hook = function(event,...)
  if event == 'onTrafficReservedVehiclesReady' then mod.onTrafficReservedVehiclesReady(...) end
  return eventHook(event,...)
end
traffic[20].reserved = 'rlsCarjackingPolice'
traffic[20].role:setAction('pursuitEnd')
traffic[20].state = 'active'
objects[20].getActive = function() return true end
assert(traffic[20].role.state == 'disabled')
assert(requestReserve(12,nil))
assert(traffic[20].claimed == 'rlsCarjackingPolice' and traffic[20].role.state ~= 'disabled')
processReserve(1)
assert(traffic[20].role.targetId == 12 and not upvalue(requestReserve,'pendingPoliceReserve'))
assert(handoffState.reserveId == 20)
mod.onPursuitAction(12,'evade')
assert(not traffic[20].claimed and not handoffState.reserveId)
traffic[20].role:setAction('pursuitEnd')
assert(requestReserve(12,nil))
processReserve(1)
assert(traffic[20].role.targetId == 12 and handoffState.reserveId == 20)
-- Deletion without an evade event must release the responder and clear its
-- stale target; the next request must claim the same single native reserve.
mod.onVehicleDestroyed(12)
assert(not traffic[20].claimed and not traffic[20].role.targetId and not handoffState.reserveId)
assert(requestReserve(12,nil))
processReserve(1)
assert(traffic[20].role.targetId == 12 and handoffState.reserveId == 20)
assert(traffic[21].role.targetId == 99)
print('PASS: native disabled reserve reset, repeated claiming, and cleanup when a target is deleted')

-- Execute the add-on's real theft -> Abandon -> exact native traffic replacement
-- transaction; only inventory/physics acquisition helpers are stubbed here.
local pool = {allVehs = {}, insertVeh = function(self,id) self.allVehs[id] = true end,
  removeVeh = function(self,id) self.allVehs[id] = nil end}
core_vehicleActivePooling = {getPool = function() return pool end, createPool = function() return pool end}
gameplay_walk.toggleWalkingMode = function() end
gameplay_walk.addVehicleToBlacklist = function() end
gameplay_walk.removeVehicleFromBlacklist = function() end
gameplay_walk.getInVehicle = function(obj) playerId = obj:getID() end
local installWalking = upvalue(mod.onUpdate,'installWalkingModeWrapper')
assert(installWalking())
local steal = upvalue(gameplay_walk.toggleWalkingMode,'completeCarjack')
local function replaceUpvalue(fn,name,value)
  for i=1,100 do
    local key = debug.getupvalue(fn,i)
    if key == name then debug.setupvalue(fn,i,value) return end
  end
  error('Missing fixture seam '..name)
end
replaceUpvalue(steal,'isJackableTrafficVehicle',function() return true end)
replaceUpvalue(steal,'captureVehicleSnapshot',function()
  return {config = {model='fullsize',partConfigFilename='vehicles/fullsize/police.pc'}}
end)
replaceUpvalue(steal,'getNativeVehicleDisplayName',function() return 'Police' end)
replaceUpvalue(steal,'getStreetVehicleAgeData',function() return 2020,1000 end)
for _, name in ipairs({'seedStreetVehicleMileage','restoreVehiclePaintSnapshot','ensureInventoryBaseValue',
  'persistStolenPaints','applyStolenMarketDiscount','ensureStolenInsuranceState','markVehicleDirty',
  'beginCarjackArrestGrace','scheduleImmediateAlert','requestCareerSave'}) do
  replaceUpvalue(steal,name,function() end)
end
local inventory = {}
overhaul_career_garage_inventory.getVehicles = function() return inventory end
overhaul_career_garage_inventory.hasFreeSlot = function() return true end
overhaul_career_garage_inventory.addVehicle = function(id)
  assert(id == 30)
  inventory[8] = {owned=true,config={}}
  return 8
end
overhaul_career_garage_inventory.setVehicleRole = function(id, role) inventory[id].role = role end
overhaul_career_garage_inventory.getVehicleIdFromInventoryId = function(id) return inventory[id] and 30 end
overhaul_career_garage_inventory.getInventoryIdFromVehicleId = function(id) return id == 30 and inventory[8] and 8 end
overhaul_career_garage_inventory.removeVehicle = function(id)
  nativeTraffic.removeTraffic(30)
  objects[30] = nil
  inventory[id] = nil
  mod.onVehicleDestroyed(30)
end
engineObject(30,'fullsize','police')
objects[30].getActive = function() return true end
nativeTraffic.insertTraffic(30,false)
assert(pool.allVehs[30] and traffic[30].role.name == 'police')
assert(steal(30,true))
assert(inventory[8].rlsCarjack.policeVehicleTheft and traffic[30].role.name == 'standard')
local backfill = upvalue(mod.onUpdate,'processTrafficBackfill')
local replacements = 0
core_vehicles.spawnNewVehicle = function(model,options)
  assert(model == 'fullsize' and options.config == 'police')
  replacements = replacements + 1
  return engineObject(31,'fullsize','police')
end
backfill(1)
assert(replacements == 0, 'do not replace the police entry before the stolen object leaves the world')
local dialog
guihooks = {trigger = function(_,data) dialog = data end}
playerId = 12
assert(mod.abandonVehicle(8) and dialog.buttons[1].isCancel and dialog.buttons[2].isDestructive)
career_modules_carjacking = mod
assert((loadstring or load)(dialog.buttons[2].luaCallback))()
assert(not inventory[8] and not traffic[30])
backfill(1)
backfill(1)
assert(replacements == 1 and pool.allVehs[31] and traffic[31].role.name == 'police')
assert(traffic[21].role.targetId == 99)
print('PASS: steal police, confirmed Abandon, and exactly one native police pool replacement')
