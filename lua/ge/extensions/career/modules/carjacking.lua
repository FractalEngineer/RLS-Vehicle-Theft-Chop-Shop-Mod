-- RLS Career Carjacking
-- BeamNG.drive + RLS Career Overhaul carjacking extension.
-- Version 0.2.4.

local M = {}

-- Keep hard dependencies to the minimum needed for the core interaction.
-- Police, insurance and valuation modules are accessed defensively at runtime.
M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_inventory",
  "career_modules_inspectVehicle",
  "career_modules_vehicleShopping",
  "career_modules_payment",
  "gameplay_walk",
  "gameplay_traffic"
}

local logTag = "rlsCarjacking"

local cfg = {
  interactDistance = 3.25,
  maxTargetSpeedMps = 12.0,

  immediateAlertRadius = 220.0,
  immediateAlertLevel = 2,
  policeCarjackLevel = 3,

  identityFlagDelaySeconds = 120,
  identityScanRadius = 55.0,
  identityScanInterval = 0.40,
  identityPursuitLevel = 2,

  stolenValueMultiplier = 0.35,
  stripPartsMultiplier = 0.05,
  allowPoliceVehicles = true,

  -- Sale-vehicle hotwiring. The action only appears while the player is
  -- sitting in an inspected-for-sale vehicle outside an active test drive.
  allowSaleVehicleHotwire = true,
  allowPrivateSellerHotwire = true,

  -- Reputation points deducted from a dealership's associated RLS
  -- organization when one of its cars is hotwired. Set to 0 to disable.
  -- Private marketplace sellers do not currently share an organization
  -- reputation in RLS, so this applies only to dealerships with an org.
  dealerHotwireReputationPenalty = 500,

  -- Cost to alter the identifying markings/registration identity of a stolen
  -- vehicle, expressed as a fraction of its current RLS market value.
  -- BeamNG/RLS does not expose a native per-vehicle VIN field; this is the
  -- gameplay abstraction that makes the vehicle insurable and no longer
  -- identifiable as stolen. 0.35 means 35%.
  identityChangeCostMultiplier = 0.35,

  -- Time in real-world seconds before an identity change completes after it is
  -- purchased. 0 keeps the service instant. The completion timestamp is saved
  -- on the vehicle, so non-zero delays survive save/reload.
  identityChangeDurationSeconds = 0,

  -- Prevent an inherited/nearby pursuit from arresting the player during the
  -- ownership + player-control handoff. Heat/pursuit may already be active,
  -- but the arrest timer is held at zero for this short grace period.
  carjackArrestGraceSeconds = 4.0,

  -- A police-car theft needs at least one real responder. RLS normally keeps
  -- its own police pool; we wake that first and spawn at most one marked
  -- fallback unit if no police responder remains after the theft.
  desiredPoliceResponders = 1
}

-- The only core function this mod replaces at runtime. It is required so the
-- existing BeamNG Enter/Exit Vehicle action can also enter unowned AI traffic.
local originalToggleWalkingMode
local wrappedToggleWalkingMode

-- Narrow wrappers for RLS camera enforcement. These only bypass automated
-- camera fines while the player is driving a stolen inventory vehicle.
local originalSpeedTrapHandler
local wrappedSpeedTrapHandler
local originalRedLightHandler
local wrappedRedLightHandler
local speedTrapInstallRetry = 0

-- My Vehicles context-menu injection is performed only while the menu is
-- opening. We never leave guihooks.trigger replaced after that call returns.

-- Tracks stolen vehicles that are removed/spawned by RLS storage/retrieval.
-- A newly spawned stolen car is put into a safe parked state so a remembered
-- throttle/gear state cannot make it drive away from the garage.
local observedSpawnedVehicles = {}
local pendingSafePark = {}
local pendingSpawnSafePark = {}
local spawnedPoliceResponderIds = {}

-- Sale-vehicle hotwire / radial-menu state.
local quickAccessInitialized = false
local pendingHotwire
local pendingHotwireRelease = {}

local pendingImmediateAlert
local carjackArrestGrace = {}
local pendingPaintRestore
local pendingInventoryPaintSnapshots = {}
local pendingCareerSaveTimer
local identityScanTimer = 0
local insuranceCleanupTimer = 0
local maximumHeatTimer = 0
local identityChangeProcessTimer = 0

-- Each live AI traffic car that becomes an inventory vehicle permanently leaves
-- BeamNG's AI traffic list. Replenish those slots asynchronously, one at a time,
-- using BeamNG's normal random traffic generator so repeated carjackings do not
-- slowly empty the map or reduce traffic variety.
local pendingTrafficReplacementCount = 0
local trafficReplacementRetryTimer = 0
local retrievalMonitorTimer = 0

-- RLS reserves -1 for ordinary uninsured vehicles and exposes those directly
-- through its Add Coverage UI. Keep identity-locked stolen cars on a separate
-- negative state so they cannot enter the normal insurance workflow until the
-- vehicle identity has been changed.
local identityLockedInsuranceId = -2

local function message(text, seconds, category)
  if ui_message then
    ui_message(text, seconds or 2.5, category or "rlsCarjacking")
  end
end

local function isCareerActive()
  return career_career and career_career.isActive and career_career.isActive()
end

local function nowPersistentTime()
  return os.time()
end

local function getPoliceModule()
  return rawget(_G, "gameplay_police")
end

local function getInsuranceModule()
  return rawget(_G, "career_modules_insurance_insurance")
end

local function getValueCalculator()
  return rawget(_G, "career_modules_valueCalculator")
end

local function getInspectVehicleModule()
  return rawget(_G, "career_modules_inspectVehicle")
end

local function getVehicleShoppingModule()
  return rawget(_G, "career_modules_vehicleShopping")
end

local function getTestDriveModule()
  return rawget(_G, "career_modules_testDrive")
end

local function getPlayerAttributesModule()
  return rawget(_G, "career_modules_playerAttributes")
end

local function getReputationModule()
  return rawget(_G, "career_modules_reputation")
end

local function getPaymentModule()
  return rawget(_G, "career_modules_payment")
end

local function getVehicleRoleName(trafficData)
  if type(trafficData) ~= "table" then return nil end
  if trafficData.roleName then return trafficData.roleName end
  if type(trafficData.role) == "table" then return trafficData.role.name end
  return nil
end

local function isPoliceTrafficVehicle(trafficData)
  return getVehicleRoleName(trafficData) == "police"
end

local function getVehicleSpeed(obj)
  if not obj then return math.huge end
  local ok, velocity = pcall(function() return obj:getVelocity() end)
  if not ok or not velocity then return 0 end
  local okLen, speed = pcall(function() return velocity:length() end)
  return (okLen and speed) or 0
end

local function getInventoryVehicle(inventoryId)
  local vehicles = career_modules_inventory and career_modules_inventory.getVehicles and career_modules_inventory.getVehicles()
  return vehicles and inventoryId and vehicles[inventoryId] or nil
end

local function getCarjackData(inventoryId)
  local vehicle = getInventoryVehicle(inventoryId)
  return vehicle and vehicle.rlsCarjack or nil, vehicle
end

local function isStolenInventoryVehicle(inventoryId)
  local data = getCarjackData(inventoryId)
  return data and data.stolen == true or false
end

local function markVehicleDirty(inventoryId)
  if career_modules_inventory and career_modules_inventory.setVehicleDirty then
    career_modules_inventory.setVehicleDirty(inventoryId)
  end
end

local function saveCareer()
  if career_saveSystem and career_saveSystem.saveCurrent then
    career_saveSystem.saveCurrent()
  end
end

local function requestCareerSave(delay)
  delay = tonumber(delay) or 0.5
  if pendingCareerSaveTimer == nil or delay < pendingCareerSaveTimer then
    pendingCareerSaveTimer = delay
  end
end

local function queueTrafficReplacement()
  pendingTrafficReplacementCount = pendingTrafficReplacementCount + 1
  if trafficReplacementRetryTimer <= 0 then
    -- Do not spawn a replacement during the ownership/control handoff. Vehicle
    -- creation is one of the heavier BeamNG operations, especially the first
    -- time a model/material is loaded in a session.
    trafficReplacementRetryTimer = 1.50
  end
end

local function processTrafficReplacements(dtReal)
  if pendingTrafficReplacementCount <= 0 then return end

  trafficReplacementRetryTimer = trafficReplacementRetryTimer - dtReal
  if trafficReplacementRetryTimer > 0 then return end

  if not gameplay_traffic or type(gameplay_traffic.spawnTraffic) ~= "function" then
    trafficReplacementRetryTimer = 1.5
    return
  end

  -- Do not start another asynchronous traffic spawn while BeamNG is already
  -- building a traffic group. This also serializes several rapid carjackings.
  if gameplay_traffic.getState then
    local okState, state = pcall(function() return gameplay_traffic.getState() end)
    if okState and state and state ~= "on" then
      trafficReplacementRetryTimer = 1.0
      return
    end
  end

  -- Most importantly, only create another physical vehicle when BeamNG itself
  -- reports that the current world is below the configured traffic population.
  -- The stolen car remains an active world vehicle while the player is driving
  -- it, so blindly spawning one replacement per theft can push the simulation
  -- above its intended vehicle count and cause CPU/GPU spikes. Once the stolen
  -- car is stored, sold, stripped or otherwise leaves the active world, the
  -- ideal spawn amount becomes positive and the queued slot is replenished.
  if gameplay_traffic.getIdealSpawnAmount then
    local okIdeal, ideal = pcall(function() return gameplay_traffic.getIdealSpawnAmount(-1, false) end)
    if okIdeal and tonumber(ideal) and tonumber(ideal) <= 0 then
      trafficReplacementRetryTimer = 1.50
      return
    end
  end

  local ok, err = pcall(function()
    -- Build the same civilian traffic group BeamNG normally uses instead of a
    -- raw random multiSpawn group. This respects level traffic selections and
    -- avoids accidentally replenishing a civilian slot with a police config.
    local trafficUtils = rawget(_G, "gameplay_traffic_trafficUtils")
    local group
    if trafficUtils then
      local simpleVehs = settings and settings.getValue and settings.getValue("trafficSimpleVehicles") or false
      local smartSelections = settings and settings.getValue and settings.getValue("trafficSmartSelections") or false
      if smartSelections and not simpleVehs and trafficUtils.getTrafficGroupFromFile then
        local fileData = trafficUtils.getTrafficGroupFromFile({name = "traffic"})
        if fileData and core_multiSpawn and core_multiSpawn.fitGroup then
          group = core_multiSpawn.fitGroup(fileData, 1)
        end
      end
      if not group and trafficUtils.createTrafficGroup then
        group = trafficUtils.createTrafficGroup(1, false, false, simpleVehs)
      end
    end
    gameplay_traffic.spawnTraffic(1, group)
  end)
  if ok then
    pendingTrafficReplacementCount = math.max(0, pendingTrafficReplacementCount - 1)
    -- Space out additional queued replacements. Apart from reducing spikes,
    -- this gives BeamNG's traffic pool time to register the newly spawned car
    -- before we ask whether another slot is still missing.
    trafficReplacementRetryTimer = pendingTrafficReplacementCount > 0 and 2.0 or 0
  else
    log("W", logTag, "Unable to replenish stolen traffic slot: " .. tostring(err))
    trafficReplacementRetryTimer = 1.5
  end
end

local function walkerDistanceToVehicle(vehId)
  local walker = getPlayerVehicle(0)
  local target = vehId and getObjectByID(vehId) or nil
  if not walker or not target then return math.huge end

  local ok, distance = pcall(function()
    return walker:getPosition():distance(target:getPosition())
  end)
  return (ok and distance) or math.huge
end

local function getCabModule()
  local cab = rawget(_G, "gameplay_cab")
  if type(cab) == "table" then return cab end

  if type(extensions) == "table" then
    local extCab = rawget(extensions, "gameplay_cab")
    if type(extCab) == "table" then return extCab end
  end
end

-- RLS's player-called cab is spawned from vehicles/midsize/taxi.pc. While the
-- cab service owns that taxi, Enter/Exit must remain a normal taxi interaction
-- rather than being intercepted by carjacking. This intentionally does not
-- blanket-exempt every taxi-looking traffic vehicle.
local function isPlayerCalledTaxi(vehId)
  local cab = getCabModule()
  if not cab or type(cab.cabState) ~= "function" then return false end

  local okState, cabState = pcall(cab.cabState)
  if not okState or not cabState or cabState == "none" or cabState == "cleanup" then
    return false
  end

  local obj = vehId and getObjectByID(vehId) or nil
  if not obj then return false end

  local model = obj.JBeam
  if (not model or model == "") and obj.getJBeamFilename then
    local okModel, value = pcall(function() return obj:getJBeamFilename() end)
    if okModel then model = value end
  end
  if model ~= "midsize" then return false end

  local partConfig = tostring(obj.partConfig or ""):gsub("\\", "/")
  return partConfig:match("vehicles/midsize/taxi%.pc$") ~= nil
end

local function isJackableTrafficVehicle(vehId, trafficData, ignoreSpeed)
  if not vehId or type(trafficData) ~= "table" or not trafficData.isAi then return false end
  if career_modules_inventory.getInventoryIdFromVehicleId and career_modules_inventory.getInventoryIdFromVehicleId(vehId) then
    return false
  end

  local obj = getObjectByID(vehId)
  if not obj then return false end
  if isPlayerCalledTaxi(vehId) then return false end

  local okActive, active = pcall(function() return obj:getActive() end)
  if okActive and not active then return false end

  local okJBeam, jbeam = pcall(function() return obj:getJBeamFilename() end)
  if okJBeam and jbeam == "unicycle" then return false end

  if not cfg.allowPoliceVehicles and isPoliceTrafficVehicle(trafficData) then return false end
  if not ignoreSpeed and getVehicleSpeed(obj) > cfg.maxTargetSpeedMps then return false end
  return true
end

local function findJackTarget(ignoreSpeed)
  if not gameplay_walk or not gameplay_walk.isWalking or not gameplay_walk.isWalking() then return nil end
  if not gameplay_traffic or not gameplay_traffic.getTrafficData then return nil end

  local traffic = gameplay_traffic.getTrafficData() or {}
  local bestId
  local bestDist = cfg.interactDistance
  local bestIsPolice = false

  for vehId, trafficData in pairs(traffic) do
    if isJackableTrafficVehicle(vehId, trafficData, ignoreSpeed) then
      local dist = walkerDistanceToVehicle(vehId)
      if dist < bestDist then
        bestId = vehId
        bestDist = dist
        bestIsPolice = isPoliceTrafficVehicle(trafficData)
      end
    end
  end

  return bestId, bestDist, bestIsPolice
end

-- Snapshot the live traffic configuration before removing the vehicle from
-- BeamNG traffic. Traffic teardown can alter transient paint/config state, so
-- the snapshot is restored into the RLS inventory record after ownership is
-- transferred.
local function captureVehicleSnapshot(vehId, obj)
  local snapshot = {config = nil, objectFields = {}, paints = nil}

  if core_vehicle_manager and core_vehicle_manager.getVehicleData then
    local ok, vehicleData = pcall(function() return core_vehicle_manager.getVehicleData(vehId) end)
    if ok and vehicleData and type(vehicleData.config) == "table" then
      local okCopy, configCopy = pcall(function() return deepcopy(vehicleData.config) end)
      if okCopy then snapshot.config = configCopy end
    end
  end

  -- Capture the rendered/live paints rather than trusting config.paints. BeamNG
  -- itself clones vehicles this way: object colors + getMetallicPaintData().
  if obj and obj.getMetallicPaintData and createVehiclePaint then
    local ok, metallic = pcall(function() return obj:getMetallicPaintData() end)
    if ok and type(metallic) == "table" then
      local paintSources = {
        {obj.color, metallic[1]},
        {obj.colorPalette0, metallic[2]},
        {obj.colorPalette1, metallic[3]}
      }
      local paints = {}
      for i = 1, 3 do
        local color, metal = paintSources[i][1], paintSources[i][2]
        if color and metal then
          local okPaint, paint = pcall(function() return createVehiclePaint(color, metal) end)
          if okPaint and type(paint) == "table" then paints[i] = paint end
        end
      end
      if paints[1] then
        paints[2] = paints[2] or deepcopy(paints[1])
        paints[3] = paints[3] or deepcopy(paints[2])
        snapshot.paints = paints
        snapshot.config = snapshot.config or {}
        snapshot.config.paints = deepcopy(paints)
      end
    end
  end

  -- Keep raw fields as a visual fallback for unusual/modded vehicles.
  if obj and obj.getField then
    for _, fieldName in ipairs({
      "color", "colorPalette0", "colorPalette1",
      "metallicPaintData", "metallicPaintDataPalette0", "metallicPaintDataPalette1"
    }) do
      local ok, value = pcall(function() return obj:getField(fieldName, 0) end)
      if ok and value ~= nil and tostring(value) ~= "" then
        snapshot.objectFields[fieldName] = value
      end
    end
  end

  return snapshot
end

local function restoreVehiclePaintSnapshot(vehId, snapshot)
  if not vehId or not snapshot then return end
  local obj = getObjectByID(vehId)
  if not obj then return end

  local paints = snapshot.paints or (snapshot.config and snapshot.config.paints)
  local colors = extensions and extensions.core_vehicle_colors
  if type(paints) == "table" and colors and colors.setVehiclePaint then
    for paintIndex = 1, 3 do
      local paint = paints[paintIndex] or paints[1]
      if paint then
        pcall(function() colors.setVehiclePaint(paintIndex, deepcopy(paint), vehId) end)
      end
    end
  end

  if obj.setField and type(snapshot.objectFields) == "table" then
    for fieldName, value in pairs(snapshot.objectFields) do
      pcall(function() obj:setField(fieldName, 0, value) end)
    end
  end
end

-- Persist the captured live paints into both the inventory config and RLS's
-- part-condition paint state. This runs again after addVehicle finishes its
-- asynchronous partCondition initialization, which is the point that used to
-- overwrite random traffic colors with a config/default color.
local function persistStolenPaints(inventoryId, vehId, snapshot)
  local vehicle = getInventoryVehicle(inventoryId)
  if not vehicle or not snapshot then return end
  local paints = snapshot.paints or (snapshot.config and snapshot.config.paints)
  if type(paints) ~= "table" or not paints[1] then return end

  paints[2] = paints[2] or paints[1]
  paints[3] = paints[3] or paints[2]
  vehicle.config = vehicle.config or {}
  vehicle.config.paints = deepcopy(paints)

  if type(vehicle.partConditions) == "table" then
    for _, condition in pairs(vehicle.partConditions) do
      if type(condition) == "table" and condition.visualState and condition.visualState.paint then
        condition.visualState.paint.originalPaints = deepcopy(paints)
      end
    end
  end

  local liveId = vehId or (career_modules_inventory.getVehicleIdFromInventoryId and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId))
  if liveId and getObjectByID(liveId) then
    restoreVehiclePaintSnapshot(liveId, snapshot)
    local liveObj = getObjectByID(liveId)
    if liveObj and liveObj.queueLuaCommand then
      local serialized = serialize and serialize(paints) or nil
      if serialized then
        pcall(function()
          liveObj:queueLuaCommand(string.format("if partCondition and partCondition.setAllPartPaints then partCondition.setAllPartPaints(%s, 0) end", serialized))
        end)
      end
    end
  end

  markVehicleDirty(inventoryId)
end

local function positiveNumber(value)
  value = tonumber(value)
  if value and value > 0 and value < math.huge then return value end
  return nil
end

local function deriveBaseConfigValue(vehicle, snapshot)
  if not vehicle then return nil end

  local existing = positiveNumber(vehicle.configBaseValue)
  if existing then return existing end

  local config = (snapshot and snapshot.config) or vehicle.config
  local model = vehicle.model
  if config and config.partConfigFilename and model and core_vehicles and core_vehicles.getConfig then
    local ok, value = pcall(function()
      local _, configName = path.splitWithoutExt(config.partConfigFilename)
      local baseConfig = core_vehicles.getConfig(model, configName)
      return baseConfig and baseConfig.Value
    end)
    if ok then
      value = positiveNumber(value)
      if value then return value end
    end
  end

  return nil
end

-- RLS insurance falls back to `configBaseValue / 3` for inventory vehicles
-- that were not bought through vehicleShopping. A live traffic vehicle can be
-- missing that field, which causes a fatal Lua error. Always seed a valid value
-- before any asynchronous RLS inventory/insurance hooks can inspect the car.
local function ensureInventoryBaseValue(inventoryId, snapshot)
  local vehicle = getInventoryVehicle(inventoryId)
  if not vehicle then return nil end

  local baseValue = deriveBaseConfigValue(vehicle, snapshot)
  if not baseValue then
    local calculator = getValueCalculator()
    if calculator and calculator.getInventoryVehicleValue then
      local ok, currentValue = pcall(function()
        return calculator.getInventoryVehicleValue(inventoryId)
      end)
      currentValue = ok and positiveNumber(currentValue) or nil
      if currentValue then
        -- Match RLS's non-purchase insurance fallback so initialValue resolves
        -- to approximately the current vehicle value.
        baseValue = currentValue * 3
      end
    end
  end

  -- This is only a crash-prevention fallback. It is used only if RLS cannot
  -- derive any real value from the configuration yet.
  baseValue = baseValue or 3000
  vehicle.configBaseValue = baseValue
  return baseValue
end

local function safeInventoryValue(inventoryId)
  local calculator = getValueCalculator()
  if calculator and calculator.getInventoryVehicleValue then
    local ok, value = pcall(function() return calculator.getInventoryVehicleValue(inventoryId) end)
    if ok then
      value = positiveNumber(value)
      if value then return value end
    end
  end

  local vehicle = getInventoryVehicle(inventoryId)
  local baseValue = vehicle and positiveNumber(vehicle.configBaseValue)
  return baseValue and (baseValue / 3) or 1000
end

local function trimString(value)
  if type(value) ~= "string" then return nil end
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value or nil
end

local function plainLabel(value)
  if type(value) == "table" then
    -- BeamNG may expose localized names as context objects. They are valid for
    -- translation-aware UI components but RLS's insurance vehicle tile expects
    -- a concrete string, so only accept an already-resolved string here.
    value = value.name or value.Name
  end
  value = trimString(value)
  if not value then return nil end
  local lower = value:lower()
  if value:sub(1, 1) == "{"
    or lower:find('"ctx"', 1, true)
    or lower:find('"txt"', 1, true)
    or lower:find("ui.vehicleconfig.", 1, true)
    or lower:match("^ui%.") then
    return nil
  end
  return value
end

local function humanizeModelKey(model)
  model = plainLabel(model)
  if not model then return nil end
  model = model:gsub("[_%-]+", " ")
  model = model:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end)
  return model
end

local function configKeyFromPath(filename)
  if type(filename) ~= "string" then return nil end
  filename = filename:gsub("\\", "/")
  return filename:match("/([^/]+)%.pc$") or filename:match("^([^/]+)%.pc$")
end

-- Resolve the same full configuration name BeamNG uses for vehicle selection,
-- such as "D-Series D15 V8 4WD (A)". Prefer the live vehicle because its exact
-- .pc configuration is authoritative; fall back to the saved inventory config
-- so stored stolen vehicles retain the same native-style name.
local function getNativeVehicleDisplayName(inventoryId, vehicle, vehId)
  vehicle = vehicle or (inventoryId and getInventoryVehicle(inventoryId)) or nil
  vehId = vehId or (inventoryId and career_modules_inventory.getVehicleIdFromInventoryId
    and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)) or nil

  if vehId and core_vehicles and core_vehicles.getVehicleDetails then
    local ok, details = pcall(function() return core_vehicles.getVehicleDetails(vehId) end)
    if ok and type(details) == "table" then
      local config = details.configs
      local nativeName = type(config) == "table" and plainLabel(config.Name) or nil
      if nativeName then return nativeName end

      local configuration = type(config) == "table" and plainLabel(config.Configuration) or nil
      local modelName = type(details.model) == "table" and plainLabel(details.model.Name) or nil
      if configuration then
        return modelName and (modelName .. " " .. configuration) or configuration
      end
    end
  end

  if vehicle and core_vehicles and core_vehicles.getConfig then
    local configPath = vehicle.config and vehicle.config.partConfigFilename or nil
    local configKey = configKeyFromPath(configPath)
    if configKey and vehicle.model then
      local ok, config = pcall(function() return core_vehicles.getConfig(vehicle.model, configKey) end)
      if ok and type(config) == "table" then
        local nativeName = plainLabel(config.Name)
        if nativeName then return nativeName end

        local configuration = plainLabel(config.Configuration)
        if configuration then
          local modelName
          if core_vehicles.getModel then
            local okModel, model = pcall(function() return core_vehicles.getModel(vehicle.model) end)
            if okModel and type(model) == "table" and type(model.model) == "table" then
              modelName = plainLabel(model.model.Name)
            end
          end
          return modelName and (modelName .. " " .. configuration) or configuration
        end
      end
    end
  end

  return nil
end

local function plainVehicleName(vehicle, inventoryId, vehId)
  if not vehicle then return "Stolen Vehicle" end

  -- Respect a valid inventory name first. Fresh/migrated stolen vehicles are
  -- assigned BeamNG's native full config name, while this also allows a user
  -- rename to remain visible instead of being overwritten by our metadata.
  local name = plainLabel(vehicle.niceName)
  if name then return name end

  name = getNativeVehicleDisplayName(inventoryId, vehicle, vehId)
  if name then return name end

  local carjack = vehicle.rlsCarjack
  name = carjack and plainLabel(carjack.displayName) or nil
  name = name or humanizeModelKey(vehicle.model)
  return name or "Stolen Vehicle"
end

local function saleVehicleDisplayName(vehicleInfo, vehicle, inventoryId, vehId)
  -- Prefer BeamNG's canonical configuration name (model + trim/drivetrain/
  -- transmission suffix). RLS shopping's Name is the next-best equivalent.
  local nativeName = getNativeVehicleDisplayName(inventoryId, vehicle, vehId)
  if nativeName then return nativeName end

  vehicleInfo = type(vehicleInfo) == "table" and vehicleInfo or {}
  local name = plainLabel(vehicleInfo.Name or vehicleInfo.name)
  return name or plainVehicleName(vehicle, inventoryId, vehId)
end

local function syncStolenVehicleDisplayName(inventoryId, vehicle, vehId)
  if not inventoryId or not vehicle then return nil end
  local data = vehicle.rlsCarjack
  if not data or not data.stolen then return nil end

  local nativeName = getNativeVehicleDisplayName(inventoryId, vehicle, vehId)
  if not nativeName then return plainVehicleName(vehicle, inventoryId, vehId) end

  local currentName = plainLabel(vehicle.niceName)
  local previousManaged = plainLabel(data.lastManagedDisplayName) or plainLabel(data.displayName)

  -- Repair localization-context/empty names and migrate names previously set by
  -- this mod. If the player has manually renamed the car to some other string,
  -- leave that custom name alone.
  if not currentName or (previousManaged and currentName == previousManaged) then
    if currentName ~= nativeName then
      vehicle.niceName = nativeName
      markVehicleDirty(inventoryId)
    end
  end

  data.displayName = nativeName
  data.lastManagedDisplayName = nativeName
  return plainVehicleName(vehicle, inventoryId, vehId)
end

-- Keep a normal, structurally valid RLS insurance record. Identity-locked
-- stolen vehicles use a private negative policy state until their identity is
-- changed; deleting the record would break RLS insurance/inventory assumptions.
-- Apply the stolen-market discount using the individual vehicle's existing
-- meet-reputation multiplier. RLS applies `(1 + meetReputation * 0.01)` to
-- the final inventory value, after base vehicle and installed parts are valued.
-- This gives us a per-vehicle discount without replacing the global value
-- calculator or modifying legitimate vehicles.
local function applyStolenMarketDiscount(inventoryId)
  local data, vehicle = getCarjackData(inventoryId)
  if not data or not data.stolen or not vehicle then return false end

  if data.marketOriginalMeetReputation == nil then
    data.marketOriginalMeetReputation = tonumber(vehicle.meetReputation) or 0
  end

  local originalFactor = math.max(0.01, 1 + (tonumber(data.marketOriginalMeetReputation) or 0) * 0.01)
  local targetFactor = originalFactor * cfg.stolenValueMultiplier
  local targetMeetReputation = (targetFactor - 1) * 100
  local currentMeetReputation = tonumber(vehicle.meetReputation) or 0

  data.marketValueMultiplier = cfg.stolenValueMultiplier
  data.marketDiscountMeetReputation = targetMeetReputation

  if math.abs(currentMeetReputation - targetMeetReputation) > 0.001 then
    vehicle.meetReputation = targetMeetReputation
    markVehicleDirty(inventoryId)
    return true
  end
  return false
end

local function stolenInsuranceLocked(inventoryId)
  local data = getCarjackData(inventoryId)
  return data and data.stolen == true and data.identityChanged ~= true and data.vinChanged ~= true or false
end

local function ensureStolenInsuranceState(inventoryId)
  if not inventoryId then return false end

  local carjack, vehicle = getCarjackData(inventoryId)
  if not carjack or not carjack.stolen or not vehicle then return false end

  local insurance = getInsuranceModule()
  if not insurance or not insurance.getInvVehs then return false end

  local ok, invVehs = pcall(function() return insurance.getInvVehs() end)
  if not ok or type(invVehs) ~= "table" then return false end

  local spawnedId = career_modules_inventory.getVehicleIdFromInventoryId
    and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId) or nil
  local safeName = syncStolenVehicleDisplayName(inventoryId, vehicle, spawnedId)
    or plainVehicleName(vehicle, inventoryId, spawnedId)
  local entry = invVehs[inventoryId] or invVehs[tostring(inventoryId)]
  if not entry and insurance.onVehicleAddedToInventory then
    ensureInventoryBaseValue(inventoryId)
    local safeValue = safeInventoryValue(inventoryId)
    local data = {
      inventoryId = inventoryId,
      vehicleInfo = {
        Name = safeName,
        Value = safeValue,
        aggregates = {}
      },
      purchaseData = {insuranceId = -1}
    }
    pcall(function() insurance.onVehicleAddedToInventory(data) end)
    entry = invVehs[inventoryId] or invVehs[tostring(inventoryId)]
  end

  if entry then
    -- RLS inventory can preserve BeamNG localization-context objects as a
    -- vehicle niceName. The insurance screen expects a normal string and will
    -- otherwise render the context object as JSON. Keep the insurance-specific
    -- display name plain without changing legitimate vehicle metadata.
    entry.name = safeName
    if stolenInsuranceLocked(inventoryId) then
      -- -1 is RLS's normal uninsured state and is immediately eligible for
      -- Add Coverage. Use our private negative sentinel until identity change.
      entry.insuranceId = identityLockedInsuranceId
    elseif entry.insuranceId == identityLockedInsuranceId then
      -- Identity has been changed: return the vehicle to RLS's ordinary
      -- uninsured pool, where the player may choose coverage normally.
      entry.insuranceId = -1
    end
    return true
  end
  return false
end

local sanitizeStolenPoliceTraffic

local function enforceStolenVehicleState()
  local vehicles = career_modules_inventory.getVehicles and career_modules_inventory.getVehicles() or {}
  for inventoryId, vehicle in pairs(vehicles or {}) do
    if vehicle and vehicle.rlsCarjack and vehicle.rlsCarjack.stolen then
      local data = vehicle.rlsCarjack
      local migrated = false
      if data.vinChanged == true and data.identityChanged ~= true then
        data.identityChanged = true
        migrated = true
      end
      if not data.identityFlagAt then
        data.identityFlagAt = data.plateFlagAt or ((tonumber(data.stolenAt) or nowPersistentTime()) + cfg.identityFlagDelaySeconds)
        migrated = true
      end
      if migrated then markVehicleDirty(inventoryId) end

      ensureInventoryBaseValue(inventoryId)
      if vehicle.rlsCarjack.maximumHeat then
        if vehicle.role == "police" then
          if career_modules_inventory.setVehicleRole then
            career_modules_inventory.setVehicleRole(inventoryId, "standard")
          else
            vehicle.role = "standard"
          end
          markVehicleDirty(inventoryId)
        end

        -- Keep spawned stolen police vehicles permanently out of the police
        -- responder registry, even after the player exits or traffic refreshes.
        local spawnedId = career_modules_inventory.getVehicleIdFromInventoryId
          and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId) or nil
        if spawnedId then sanitizeStolenPoliceTraffic(spawnedId) end
      end
      local spawnedId = career_modules_inventory.getVehicleIdFromInventoryId
        and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId) or nil
      syncStolenVehicleDisplayName(inventoryId, vehicle, spawnedId)
      applyStolenMarketDiscount(inventoryId)
      ensureStolenInsuranceState(inventoryId)
    end
  end
end

local function policeCommittedToOtherPursuit(policeVeh, targetId)
  if not policeVeh or not policeVeh.role then return false end
  local role = policeVeh.role
  local pursuitMode = tonumber(role.targetPursuitMode) or 0
  local otherTarget = role.targetId
  return pursuitMode > 0 and otherTarget ~= nil and otherTarget ~= targetId
end

local function resetPursuitTimers(trafficData, clearMode)
  if not trafficData or type(trafficData.pursuit) ~= "table" then return end
  local pursuit = trafficData.pursuit
  if clearMode then
    pursuit.mode = 0
    pursuit.score = 0
  end
  if type(pursuit.timers) == "table" then
    pursuit.timers.arrest = 0
    pursuit.timers.main = clearMode and 0 or (pursuit.timers.main or 0)
    pursuit.timers.evade = clearMode and 0 or (pursuit.timers.evade or 0)
    pursuit.timers.arrestValue = 0
  end
end

-- Once the stolen vehicle is inserted back into traffic as the player car,
-- scrub any pursuit state inherited from the AI/police object. This is done
-- before our own theft pursuit is started so a police vehicle that was already
-- in a chase cannot carry a stale arrest state across the ownership handoff.
local function removeFromPoliceRegistry(vehId)
  local police = getPoliceModule()
  if not police then return end

  -- Use the public lifecycle hook first. Then also clear the exported registry
  -- directly as a fail-safe: getNearestPoliceVehicle() iterates this exact
  -- table when deciding arrest distance, so a stolen police car must never
  -- remain in it even if another traffic refresh re-registered the id.
  if police.onTrafficVehicleRemoved then
    pcall(function() police.onTrafficVehicleRemoved(vehId) end)
  end
  if police.getPoliceVehicles then
    local ok, registry = pcall(function() return police.getPoliceVehicles() end)
    if ok and type(registry) == "table" then
      registry[vehId] = nil
    end
  end
end

sanitizeStolenPoliceTraffic = function(vehId)
  local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  local targetTraffic = traffic and traffic[vehId] or nil
  if targetTraffic then
    -- Police configurations carry autoRole='police'. Merely calling
    -- setRole('standard') is not persistent: a refresh or pursuit clear can
    -- restore autoRole and turn the stolen car back into a police responder.
    -- Make the ownership conversion permanent for this traffic object.
    targetTraffic.autoRole = "standard"
    if getVehicleRoleName(targetTraffic) == "police" and targetTraffic.setRole then
      pcall(function() targetTraffic:setRole("standard") end)
      targetTraffic.autoRole = "standard"
    end
  end
  removeFromPoliceRegistry(vehId)
  return targetTraffic ~= nil
end

local function prepareCarjackPlayerTraffic(vehId)
  local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  local targetTraffic = traffic and traffic[vehId] or nil
  if not targetTraffic then return false end

  local police = getPoliceModule()
  local oldMode = targetTraffic.pursuit and tonumber(targetTraffic.pursuit.mode) or 0
  if oldMode ~= 0 and police and police.setPursuitMode then
    pcall(function() police.setPursuitMode(0, vehId, {}) end)
    targetTraffic = (gameplay_traffic.getTrafficData() or {})[vehId] or targetTraffic
  end

  -- A stolen police configuration auto-registers itself as a police traffic
  -- vehicle when inserted. Demote it explicitly and remove only that id from
  -- gameplay_police's responder registry while keeping it in traffic as the
  -- player/suspect target.
  sanitizeStolenPoliceTraffic(vehId)
  targetTraffic = (gameplay_traffic.getTrafficData() or {})[vehId] or targetTraffic
  resetPursuitTimers(targetTraffic, true)
  return true
end

local function beginCarjackArrestGrace(vehId, inventoryId)
  if not inventoryId then return end
  carjackArrestGrace[inventoryId] = {
    vehId = vehId,
    timer = cfg.carjackArrestGraceSeconds,
    initialized = false
  }
  if prepareCarjackPlayerTraffic(vehId) then
    carjackArrestGrace[inventoryId].initialized = true
  end
end

local function processCarjackArrestGrace(dtReal)
  for inventoryId, grace in pairs(carjackArrestGrace) do
    grace.timer = (tonumber(grace.timer) or 0) - dtReal
    local vehId = grace.vehId
    local currentInv = vehId and career_modules_inventory.getInventoryIdFromVehicleId
      and career_modules_inventory.getInventoryIdFromVehicleId(vehId) or nil

    if not vehId or not getObjectByID(vehId) or currentInv ~= inventoryId then
      carjackArrestGrace[inventoryId] = nil
    else
      if not grace.initialized and prepareCarjackPlayerTraffic(vehId) then
        grace.initialized = true
      end

      local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
      local targetTraffic = traffic and traffic[vehId] or nil
      if targetTraffic then
        -- Do not cancel the theft pursuit once it starts. Only prevent the
        -- arrest countdown from accumulating during the control handoff.
        resetPursuitTimers(targetTraffic, false)
      end

      if grace.timer <= 0 then
        carjackArrestGrace[inventoryId] = nil
      end
    end
  end
end

local function nearbyPoliceIds(targetObj, radius)
  local result = {}
  local police = getPoliceModule()
  if not targetObj or not police or not police.getPoliceVehicles then return result end

  local targetPos = targetObj:getPosition()
  for policeId, policeVeh in pairs(police.getPoliceVehicles() or {}) do
    local policeObj = getObjectByID(policeId)
    if policeObj and policeId ~= targetObj:getID() and not policeCommittedToOtherPursuit(policeVeh, targetObj:getID()) then
      local ok, distance = pcall(function() return targetPos:distance(policeObj:getPosition()) end)
      if ok and distance and distance <= radius then
        result[#result + 1] = policeId
      end
    end
  end
  return result
end

local function wakePoliceResponders(targetId)
  local result = {}
  local police = getPoliceModule()
  if not police or not police.getPoliceVehicles then return result end

  local pool = gameplay_traffic and gameplay_traffic.getTrafficPool and gameplay_traffic.getTrafficPool() or nil

  for policeId, policeVeh in pairs(police.getPoliceVehicles() or {}) do
    if policeId ~= targetId and not policeCommittedToOtherPursuit(policeVeh, targetId) then
      local policeObj = getObjectByID(policeId)
      if policeObj then
        local wasInactive = false

        -- RLS keeps extra police cars in the traffic pool with a low activation
        -- probability. Maximum heat should wake those units immediately.
        if pool and pool.allVehs and pool.allVehs[policeId] == 0 and pool.setVeh then
          local ok = pcall(function() pool:setVeh(policeId, true) end)
          wasInactive = ok or wasInactive
        end

        local okActive, active = pcall(function() return policeObj:getActive() end)
        if okActive and not active then
          pcall(function() policeObj:setActive(1) end)
          wasInactive = true
        end

        -- If we just woke a pooled unit, bring it back into the active traffic
        -- area rather than leaving it dormant on the far side of the map.
        if wasInactive and gameplay_traffic.forceTeleport then
          pcall(function() gameplay_traffic.forceTeleport(policeId) end)
        end

        result[#result + 1] = policeId
      end
    end
  end
  return result
end

local function countAvailablePoliceResponders(targetId)
  local police = getPoliceModule()
  if not police or not police.getPoliceVehicles then return 0 end
  local count = 0
  for policeId, _ in pairs(police.getPoliceVehicles() or {}) do
    if policeId ~= targetId and getObjectByID(policeId) then count = count + 1 end
  end
  return count
end

local function spawnPoliceResponder(targetId)
  if not core_vehicles or not core_vehicles.spawnNewVehicle then return nil end
  if not gameplay_traffic or not gameplay_traffic.insertTraffic then return nil end

  -- Do not use createPoliceGroup() here. RLS's full police catalogue includes
  -- unmarked/undercover configurations at higher unlock levels. For a forced
  -- replacement responder, use an explicitly marked Grand Marshal patrol car.
  -- BCPD is preferred on the RLS Belasco career map; the standard marked
  -- Police Package is a compatibility fallback.
  local markedSpecs = {
    {model = "fullsize", config = "bcpd"},
    {model = "fullsize", config = "police"}
  }

  local targetObj = targetId and getObjectByID(targetId) or nil
  local pos = targetObj and targetObj:getPosition() + vec3(0, 0, 500) or nil
  local obj
  local lastErr
  for _, policeSpec in ipairs(markedSpecs) do
    local options = {
      config = policeSpec.config,
      autoEnterVehicle = false,
      vehicleName = "rlsCarjackMarkedPoliceResponder"
    }
    if pos then options.pos = pos end

    local okSpawn, spawned = pcall(function()
      return core_vehicles.spawnNewVehicle(policeSpec.model, options)
    end)
    if okSpawn and spawned then
      obj = spawned
      break
    end
    lastErr = spawned
  end

  if not obj then
    log("E", logTag, "Failed to spawn marked replacement police responder: " .. tostring(lastErr))
    return nil
  end

  local policeId = obj:getID()
  spawnedPoliceResponderIds[policeId] = true
  pcall(function() gameplay_traffic.insertTraffic(policeId, false, true) end)

  local traffic = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  local trafficData = traffic[policeId]
  if trafficData and trafficData.setRole and getVehicleRoleName(trafficData) ~= "police" then
    pcall(function() trafficData:setRole("police") end)
  end

  local police = getPoliceModule()
  if police and police.onTrafficVehicleAdded then
    -- insertTraffic normally fires this itself, but run it once more after role
    -- assignment in case the traffic object was initially registered as standard.
    pcall(function() police.onTrafficVehicleAdded(policeId) end)
  end

  if gameplay_traffic.forceTeleport then
    pcall(function() gameplay_traffic.forceTeleport(policeId, nil, nil, 120, 350, 180) end)
  end
  return policeId
end

local function ensurePoliceResponderCount(targetId, desired)
  desired = math.max(0, tonumber(desired) or 0)

  -- This is called only for the initial police-car theft alert. Never run a
  -- spawn loop: if police registration is delayed by a frame, a loop can create
  -- a whole convoy of replacements before the first unit appears in policeVehs.
  -- Wake RLS's existing pool first, and create at most one marked fallback.
  local responders = wakePoliceResponders(targetId)
  if #responders < desired and countAvailablePoliceResponders(targetId) < desired then
    spawnPoliceResponder(targetId)
    responders = wakePoliceResponders(targetId)
  end
  return responders
end

local function scheduleImmediateAlert(vehId, inventoryId, maximumHeat)
  pendingImmediateAlert = {
    vehId = vehId,
    inventoryId = inventoryId,
    maximumHeat = maximumHeat == true,
    delay = 0.20,
    ttl = 3.0
  }
end

local function completeCarjack(vehId, wasPoliceVehicle)
  local obj = getObjectByID(vehId)
  if not obj then return false end

  -- If the player steals one of our replacement responders, it becomes a real
  -- inventory vehicle and must no longer be treated as disposable response AI.
  spawnedPoliceResponderIds[vehId] = nil

  if not career_modules_inventory.hasFreeSlot or not career_modules_inventory.hasFreeSlot() then
    message("No free career vehicle slot.", 4)
    return false
  end

  local traffic = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  local trafficData = traffic[vehId]
  if not isJackableTrafficVehicle(vehId, trafficData, true) then return false end
  wasPoliceVehicle = wasPoliceVehicle or isPoliceTrafficVehicle(trafficData)

  local originalPlate = ""
  if core_vehicles and core_vehicles.getVehicleLicenseText then
    local ok, plate = pcall(function() return core_vehicles.getVehicleLicenseText(obj) end)
    if ok and plate then originalPlate = plate end
  end

  -- Capture the exact live traffic config/paint and BeamNG-native full config
  -- name before traffic teardown.
  local snapshot = captureVehicleSnapshot(vehId, obj)
  local nativeDisplayName = getNativeVehicleDisplayName(nil, nil, vehId)

  if gameplay_traffic.removeTraffic then
    pcall(function() gameplay_traffic.removeTraffic(vehId, true) end)
    queueTrafficReplacement()
  end
  if gameplay_walk.removeVehicleFromBlacklist then
    pcall(function() gameplay_walk.removeVehicleFromBlacklist(vehId) end)
  end
  pcall(function() obj:setDynDataFieldbyName("isTraffic", 0, "false") end)
  pcall(function() obj:queueLuaCommand('ai.setMode("disabled")') end)

  -- Traffic teardown can touch color fields. Restore them before and after the
  -- inventory handoff so the stolen car visually stays the same car.
  restoreVehiclePaintSnapshot(vehId, snapshot)

  local inventoryId = career_modules_inventory.addVehicle(vehId, nil, {owned = true})
  if not inventoryId then
    message("Carjacking failed: RLS inventory rejected the vehicle.", 4)
    return false
  end

  local vehicle = getInventoryVehicle(inventoryId)
  if not vehicle then return false end

  -- RLS addVehicle keeps a live config reference. Replace it with our pre-
  -- traffic-removal snapshot so random traffic paints/parts survive ownership.
  if snapshot and type(snapshot.config) == "table" then
    local okCopy, configCopy = pcall(function() return deepcopy(snapshot.config) end)
    if okCopy and type(configCopy) == "table" then
      vehicle.config = configCopy
    end
  end
  vehicle.config = vehicle.config or {}
  if originalPlate ~= "" then vehicle.config.licenseName = originalPlate end

  -- MUST happen before any RLS async inventory hook can initialize insurance.
  ensureInventoryBaseValue(inventoryId, snapshot)

  local stolenAt = nowPersistentTime()
  vehicle.rlsCarjack = {
    stolen = true,
    stolenAt = stolenAt,
    originalPlate = originalPlate ~= "" and originalPlate or vehicle.config.licenseName or "",
    identityFlagAt = stolenAt + cfg.identityFlagDelaySeconds,
    identityChanged = false,
    displayName = nativeDisplayName or plainVehicleName(vehicle, inventoryId, vehId),
    lastManagedDisplayName = nativeDisplayName,
    immediateAlertSent = false,
    policeVehicleTheft = wasPoliceVehicle == true,
    maximumHeat = wasPoliceVehicle == true,
    marketValueMultiplier = cfg.stolenValueMultiplier
  }
  if nativeDisplayName then
    vehicle.niceName = nativeDisplayName
  end

  -- Mark this live object as already observed so the retrieval safety logic
  -- does not park the car during the initial theft.
  observedSpawnedVehicles[inventoryId] = vehId

  -- A police configuration naturally resolves to the police traffic role. RLS
  -- playerDriving checks that role immediately on vehicle switch and otherwise
  -- treats the thief as an on-duty cop. Force the inventory role to standard
  -- before entering; the pursuit system will turn it into a suspect next.
  if wasPoliceVehicle then
    if career_modules_inventory.setVehicleRole then
      career_modules_inventory.setVehicleRole(inventoryId, "standard")
    else
      vehicle.role = "standard"
    end

    -- Insert the stolen police car back into traffic *before* player control is
    -- transferred, but as a non-AI vehicle. This lets us demote/remove it from
    -- the police registry before RLS playerDriving sees the vehicle switch.
    if gameplay_traffic.insertTraffic then
      pcall(function() gameplay_traffic.insertTraffic(vehId, true, true) end)
      prepareCarjackPlayerTraffic(vehId)
    end
  end

  pendingInventoryPaintSnapshots[inventoryId] = snapshot
  persistStolenPaints(inventoryId, vehId, snapshot)

  applyStolenMarketDiscount(inventoryId)
  markVehicleDirty(inventoryId)

  -- Initialize/repair the RLS insurance structure with a valid vehicle value,
  -- then keep the stolen vehicle explicitly uninsured.
  ensureStolenInsuranceState(inventoryId)

  restoreVehiclePaintSnapshot(vehId, snapshot)
  pendingPaintRestore = {vehId = vehId, snapshot = snapshot, timer = 0.10, attempts = 8}

  if gameplay_walk.getInVehicle then
    local ok = pcall(function() gameplay_walk.getInVehicle(obj) end)
    if not ok then pcall(function() be:enterVehicle(0, obj) end) end
  else
    pcall(function() be:enterVehicle(0, obj) end)
  end

  -- Clean any old AI/police pursuit state as soon as the object becomes the
  -- player vehicle, then protect only the arrest countdown during handoff.
  beginCarjackArrestGrace(vehId, inventoryId)

  scheduleImmediateAlert(vehId, inventoryId, wasPoliceVehicle)
  requestCareerSave(0.75)

  if wasPoliceVehicle then
    message("POLICE VEHICLE STOLEN — MAXIMUM HEAT!", 6)
  else
    message(string.format("Vehicle reported stolen in %ds.", cfg.identityFlagDelaySeconds), 5)
  end
  return true
end


local function isPoliceShopVehicle(vehicleInfo)
  if type(vehicleInfo) ~= "table" then return false end
  local configType = vehicleInfo["Config Type"] or vehicleInfo.configType or vehicleInfo.ConfigType
  return string.lower(tostring(configType or "")) == "police"
end

local function getHotwireCandidate(expectedVehId, expectedShopId)
  if not cfg.allowSaleVehicleHotwire or not isCareerActive() then return nil end

  local inspect = getInspectVehicleModule()
  local shopping = getVehicleShoppingModule()
  if not inspect or not inspect.getSpawnedVehicleInfo or not shopping or not shopping.getVehicleInfoByShopId then
    return nil
  end

  local spawned = inspect.getSpawnedVehicleInfo()
  if type(spawned) ~= "table" or not spawned.vehId or not spawned.shopId then return nil end
  if expectedVehId and spawned.vehId ~= expectedVehId then return nil end
  if expectedShopId and spawned.shopId ~= expectedShopId then return nil end

  local playerId = be:getPlayerVehicleID(0)
  if playerId ~= spawned.vehId then return nil end

  local testDrive = getTestDriveModule()
  if testDrive and testDrive.isActive then
    local ok, active = pcall(function() return testDrive.isActive() end)
    if ok and active then return nil end
  end

  if career_modules_inventory.getInventoryIdFromVehicleId
    and career_modules_inventory.getInventoryIdFromVehicleId(spawned.vehId) then
    return nil
  end

  local vehicleInfo = shopping.getVehicleInfoByShopId(spawned.shopId)
  if type(vehicleInfo) ~= "table" then return nil end
  if vehicleInfo.sellerId == "private" and not cfg.allowPrivateSellerHotwire then return nil end

  local policeVehicle = isPoliceShopVehicle(vehicleInfo)
  if policeVehicle and not cfg.allowPoliceVehicles then return nil end

  return {
    vehId = spawned.vehId,
    shopId = spawned.shopId,
    spawnedInfo = spawned,
    vehicleInfo = vehicleInfo,
    policeVehicle = policeVehicle
  }
end

local function removeHotwiredVehicleFromShop(shopId)
  local shopping = getVehicleShoppingModule()
  if not shopping or not shopping.getVehiclesInShop then return false end

  local ok, vehiclesInShop = pcall(function() return shopping.getVehiclesInShop() end)
  if not ok or type(vehiclesInShop) ~= "table" then return false end

  local target = tonumber(shopId) or shopId
  for i = #vehiclesInShop, 1, -1 do
    local info = vehiclesInShop[i]
    local candidate = info and (tonumber(info.shopId) or info.shopId)
    if candidate == target then
      info.markedSold = true
      info.soldViewCounter = math.max(1, tonumber(info.soldViewCounter) or 0)
      table.remove(vehiclesInShop, i)
      if shopping.invalidateVehicleCache then
        pcall(function() shopping.invalidateVehicleCache() end)
      end
      return true
    end
  end
  return false
end

local function applyDealerHotwireReputationPenalty(vehicleInfo)
  local penalty = math.max(0, tonumber(cfg.dealerHotwireReputationPenalty) or 0)
  if penalty <= 0 or type(vehicleInfo) ~= "table" or vehicleInfo.sellerId == "private" then return nil end

  local facilities = rawget(_G, "freeroam_facilities")
  local organizations = rawget(_G, "freeroam_organizations")
  local playerAttributes = getPlayerAttributesModule()
  if not facilities or not facilities.getDealership or not playerAttributes or not playerAttributes.addAttributes then
    return nil
  end

  local okDealer, dealership = pcall(function() return facilities.getDealership(vehicleInfo.sellerId) end)
  if not okDealer or not dealership or not dealership.associatedOrganization then return nil end

  local orgId = dealership.associatedOrganization
  local okAdd = pcall(function()
    playerAttributes.addAttributes({
      [orgId .. "Reputation"] = -penalty
    }, {
      tags = {"vehicleTheft"},
      label = string.format("Hotwired vehicle from %s", dealership.name or vehicleInfo.sellerName or vehicleInfo.sellerId)
    })
  end)
  if not okAdd then return nil end

  local reputation = getReputationModule()
  if reputation and reputation.addReputationToOrg and organizations and organizations.getOrganization then
    local okOrg, org = pcall(function() return organizations.getOrganization(orgId) end)
    if okOrg and org then
      pcall(function() reputation.addReputationToOrg(org) end)
    end
  end

  return orgId, penalty
end

local function ensureHotwiredVehicleStarted(vehId)
  local obj = vehId and getObjectByID(vehId) or nil
  if not obj then return false end

  -- Run this in vehicle Lua so we can check whether an ICE engine is already
  -- running before requesting the starter. For vehicles without an
  -- engineRunning signal (for example many EVs), ignition level 2 is enough.
  pcall(function()
    obj:queueLuaCommand([[
      local ignitionLevel = electrics and electrics.values and tonumber(electrics.values.ignitionLevel) or 0
      local engineRunning = electrics and electrics.values and electrics.values.engineRunning

      if engineRunning ~= nil then
        local running = tonumber(engineRunning) and tonumber(engineRunning) > 0.5
        if not running then
          if controller and controller.mainController and controller.mainController.setEngineIgnition then
            controller.mainController.setEngineIgnition(true)
          end
          if electrics and electrics.setIgnitionLevel then
            electrics.setIgnitionLevel(3)
          end
        elseif ignitionLevel < 2 and electrics and electrics.setIgnitionLevel then
          electrics.setIgnitionLevel(2)
        end
      elseif ignitionLevel < 2 and electrics and electrics.setIgnitionLevel then
        electrics.setIgnitionLevel(2)
      end
    ]])
  end)
  return true
end

local function scheduleHotwireRelease(vehId)
  if not vehId then return end
  pendingHotwireRelease[vehId] = {timer = 0.18, attempts = 8}
end

local function processHotwireRelease(dtReal)
  for vehId, pending in pairs(pendingHotwireRelease) do
    pending.timer = pending.timer - dtReal
    if pending.timer <= 0 then
      local obj = getObjectByID(vehId)
      if not obj then
        pendingHotwireRelease[vehId] = nil
      else
        if core_vehicleBridge and core_vehicleBridge.executeAction then
          pcall(function() core_vehicleBridge.executeAction(obj, "setFreeze", false) end)
        end
        ensureHotwiredVehicleStarted(vehId)
        pending.attempts = pending.attempts - 1
        if pending.attempts <= 0 then
          pendingHotwireRelease[vehId] = nil
        else
          pending.timer = 0.12
        end
      end
    end
  end
end

local function completeSaleVehicleHotwire(candidate)
  candidate = candidate or getHotwireCandidate()
  if not candidate then return false end

  local current = getHotwireCandidate(candidate.vehId, candidate.shopId)
  if not current then return false end
  candidate = current

  if not career_modules_inventory.hasFreeSlot or not career_modules_inventory.hasFreeSlot() then
    message("No free career vehicle slot.", 4)
    return false
  end

  local vehId = candidate.vehId
  local obj = getObjectByID(vehId)
  if not obj then return false end

  local originalPlate = ""
  if core_vehicles and core_vehicles.getVehicleLicenseText then
    local ok, plate = pcall(function() return core_vehicles.getVehicleLicenseText(obj) end)
    if ok and plate then originalPlate = plate end
  end

  local snapshot = captureVehicleSnapshot(vehId, obj)
  local nativeDisplayName = getNativeVehicleDisplayName(nil, nil, vehId)
  local inventoryId = career_modules_inventory.addVehicle(vehId, nil, {owned = true})
  if not inventoryId then
    message("Hotwire failed: RLS inventory rejected the vehicle.", 4)
    return false
  end

  local vehicle = getInventoryVehicle(inventoryId)
  if not vehicle then return false end

  if snapshot and type(snapshot.config) == "table" then
    local okCopy, configCopy = pcall(function() return deepcopy(snapshot.config) end)
    if okCopy and type(configCopy) == "table" then vehicle.config = configCopy end
  end
  vehicle.config = vehicle.config or {}
  if originalPlate ~= "" then vehicle.config.licenseName = originalPlate end

  ensureInventoryBaseValue(inventoryId, snapshot)

  local stolenAt = nowPersistentTime()
  vehicle.rlsCarjack = {
    stolen = true,
    hotwired = true,
    source = "saleVehicle",
    stolenAt = stolenAt,
    originalPlate = originalPlate ~= "" and originalPlate or vehicle.config.licenseName or "",
    identityFlagAt = stolenAt + cfg.identityFlagDelaySeconds,
    identityChanged = false,
    displayName = nativeDisplayName or saleVehicleDisplayName(candidate.vehicleInfo, vehicle, inventoryId, vehId),
    lastManagedDisplayName = nativeDisplayName,
    immediateAlertSent = false,
    policeVehicleTheft = candidate.policeVehicle == true,
    maximumHeat = candidate.policeVehicle == true,
    marketValueMultiplier = cfg.stolenValueMultiplier,
    shopId = candidate.shopId,
    sellerId = candidate.vehicleInfo.sellerId,
    sellerName = candidate.vehicleInfo.sellerName
  }
  if nativeDisplayName then
    vehicle.niceName = nativeDisplayName
  end

  observedSpawnedVehicles[inventoryId] = vehId

  -- The player was already sitting in the inspection vehicle before it became
  -- an inventory car, so no vehicle-switch event will update RLS's
  -- currentVehicle pointer. Load option 1 only updates that pointer and does
  -- not reload or move the live vehicle.
  if career_modules_inventory.enterVehicle then
    pcall(function() career_modules_inventory.enterVehicle(inventoryId, 1) end)
  end

  if candidate.policeVehicle then
    if career_modules_inventory.setVehicleRole then
      career_modules_inventory.setVehicleRole(inventoryId, "standard")
    else
      vehicle.role = "standard"
    end
  end

  -- Inspection vehicles are frozen and are not normal traffic. Insert the now
  -- stolen player vehicle as a non-AI traffic target so RLS police can pursue
  -- it and later perform stolen-identity detection.
  if gameplay_traffic and gameplay_traffic.insertTraffic then
    pcall(function() gameplay_traffic.insertTraffic(vehId, true, true) end)
    local traffic = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
    local targetTraffic = traffic[vehId]
    if targetTraffic then
      targetTraffic.autoRole = "standard"
      if getVehicleRoleName(targetTraffic) == "police" and targetTraffic.setRole then
        pcall(function() targetTraffic:setRole("standard") end)
      end
      resetPursuitTimers(targetTraffic, true)
    end
    if candidate.policeVehicle then sanitizeStolenPoliceTraffic(vehId) end
  end

  pendingInventoryPaintSnapshots[inventoryId] = snapshot
  persistStolenPaints(inventoryId, vehId, snapshot)
  applyStolenMarketDiscount(inventoryId)
  ensureStolenInsuranceState(inventoryId)
  markVehicleDirty(inventoryId)

  -- Close the RLS inspection without deleting the object. Keep it frozen until
  -- RLS has cleared its sale tether/state, then release it below.
  local inspect = getInspectVehicleModule()
  if inspect and inspect.leaveSaleCallback then
    pcall(function()
      inspect.leaveSaleCallback("dontDespawn", true, false, "The sale has been cancelled.")
    end)
  end

  removeHotwiredVehicleFromShop(candidate.shopId)
  local shopping = getVehicleShoppingModule()
  if shopping and shopping.onShoppingMenuClosed then
    pcall(function() shopping.onShoppingMenuClosed() end)
  end
  local orgId, repPenalty = applyDealerHotwireReputationPenalty(candidate.vehicleInfo)

  restoreVehiclePaintSnapshot(vehId, snapshot)
  pendingPaintRestore = {vehId = vehId, snapshot = snapshot, timer = 0.10, attempts = 8}

  beginCarjackArrestGrace(vehId, inventoryId)
  scheduleImmediateAlert(vehId, inventoryId, candidate.policeVehicle)
  scheduleHotwireRelease(vehId)
  requestCareerSave(0.75)

  if candidate.policeVehicle then
    if orgId and repPenalty then
      message(string.format("POLICE VEHICLE HOTWIRED — MAXIMUM HEAT! Dealer reputation -%d.", repPenalty), 6)
    else
      message("POLICE VEHICLE HOTWIRED — MAXIMUM HEAT!", 6)
    end
  elseif orgId and repPenalty then
    message(string.format("Vehicle hotwired. Dealer reputation -%d.", repPenalty), 5)
  else
    message(string.format("Vehicle hotwired. Reported stolen in %ds.", cfg.identityFlagDelaySeconds), 5)
  end
  return true
end

local function processPendingHotwire()
  if not pendingHotwire then return end
  local request = pendingHotwire
  pendingHotwire = nil
  completeSaleVehicleHotwire(getHotwireCandidate(request.vehId, request.shopId))
end

local function registerHotwireQuickAccessEntry()
  if quickAccessInitialized then return end
  local quickAccess = rawget(_G, "core_quickAccess")
  if not quickAccess or not quickAccess.addEntry then return end
  quickAccessInitialized = true

  quickAccess.addEntry({
    level = "/root/sandbox/career/",
    generator = function(entries)
      local candidate = getHotwireCandidate()
      if not candidate then return end
      table.insert(entries, {
        title = "Hotwire",
        icon = "lockOpened",
        priority = 52,
        subtitle = "Steal this vehicle",
        onSelect = function()
          pendingHotwire = {vehId = candidate.vehId, shopId = candidate.shopId}
          return {"hide"}
        end
      })
    end
  })
end

local function onBeforeRadialOpened()
  registerHotwireQuickAccessEntry()
end

local function onQuickAccessLoaded()
  quickAccessInitialized = false
end

local function installWalkingModeWrapper()
  if originalToggleWalkingMode then return true end
  if not gameplay_walk or type(gameplay_walk.toggleWalkingMode) ~= "function" then return false end

  originalToggleWalkingMode = gameplay_walk.toggleWalkingMode
  wrappedToggleWalkingMode = function(...)
    -- Never interfere outside career, or when the player is currently in a car.
    if not isCareerActive() or not gameplay_walk.isWalking or not gameplay_walk.isWalking() then
      return originalToggleWalkingMode(...)
    end

    local traffic = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}

    -- If BeamNG itself selected a vehicle, preserve vanilla behavior unless it
    -- is specifically an unowned AI traffic vehicle.
    local normalTarget = gameplay_walk.getVehicleInFront and gameplay_walk.getVehicleInFront() or nil
    if normalTarget then
      local normalId = normalTarget:getID()
      local trafficData = traffic[normalId]
      if trafficData and isJackableTrafficVehicle(normalId, trafficData, true) then
        return completeCarjack(normalId, isPoliceTrafficVehicle(trafficData))
      end
      return originalToggleWalkingMode(...)
    end

    -- AI traffic is often blacklisted by gameplay_walk, so use a simple nearby
    -- center-distance fallback rather than modifying BeamNG's blacklist rules.
    local targetId, _, isPolice = findJackTarget(false)
    if targetId then
      return completeCarjack(targetId, isPolice)
    end

    return originalToggleWalkingMode(...)
  end

  gameplay_walk.toggleWalkingMode = wrappedToggleWalkingMode
  return true
end

local function restoreWalkingModeWrapper()
  if gameplay_walk and wrappedToggleWalkingMode and originalToggleWalkingMode and gameplay_walk.toggleWalkingMode == wrappedToggleWalkingMode then
    gameplay_walk.toggleWalkingMode = originalToggleWalkingMode
  end
  originalToggleWalkingMode = nil
  wrappedToggleWalkingMode = nil
end

local function processImmediateAlert(dtReal)
  if not pendingImmediateAlert then return end

  pendingImmediateAlert.delay = pendingImmediateAlert.delay - dtReal
  pendingImmediateAlert.ttl = pendingImmediateAlert.ttl - dtReal
  if pendingImmediateAlert.delay > 0 then return end

  local police = getPoliceModule()
  if not police or not police.setPursuitMode then
    if pendingImmediateAlert.ttl <= 0 then pendingImmediateAlert = nil end
    return
  end

  local vehId = pendingImmediateAlert.vehId
  local targetObj = getObjectByID(vehId)
  local traffic = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}

  -- RLS police pursuit expects the player vehicle to exist in traffic data.
  if targetObj and traffic[vehId] then
    -- The traffic object may have been a pursuing police unit or may have been
    -- inserted beside another active pursuit. Start this theft from a clean
    -- arrest timer before assigning responders.
    resetPursuitTimers(traffic[vehId], false)

    if pendingImmediateAlert.maximumHeat then
      sanitizeStolenPoliceTraffic(vehId)
      -- Always mark the stolen police car as a level-3 suspect, even if the
      -- stolen unit was the only currently active police car. An empty police
      -- list still sets the target pursuit mode in RLS.
      pcall(function() police.setPursuitMode(cfg.policeCarjackLevel, vehId, {}) end)

      local ids = ensurePoliceResponderCount(vehId, cfg.desiredPoliceResponders)
      if #ids > 0 then
        pcall(function() police.setPursuitMode(cfg.policeCarjackLevel, vehId, ids) end)
      end
      log("I", logTag, string.format("Police vehicle theft: maximum heat set, responders=%d", #ids))
    else
      local ids = nearbyPoliceIds(targetObj, cfg.immediateAlertRadius)
      if #ids > 0 then
        pcall(function() police.setPursuitMode(cfg.immediateAlertLevel, vehId, ids) end)
      end
    end

    local data = getCarjackData(pendingImmediateAlert.inventoryId)
    if data then
      data.immediateAlertSent = true
      markVehicleDirty(pendingImmediateAlert.inventoryId)
    end
    pendingImmediateAlert = nil
    return
  end

  if pendingImmediateAlert.ttl <= 0 then
    log("W", logTag, "Police alert timed out waiting for player traffic insertion")
    pendingImmediateAlert = nil
  end
end

local function processMaximumHeat(dtReal)
  maximumHeatTimer = maximumHeatTimer - dtReal
  if maximumHeatTimer > 0 then return end
  maximumHeatTimer = 1.0

  if gameplay_walk and gameplay_walk.isWalking and gameplay_walk.isWalking() then return end

  local playerId = be:getPlayerVehicleID(0)
  if not playerId or playerId < 0 then return end
  local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId and career_modules_inventory.getInventoryIdFromVehicleId(playerId) or nil
  if not inventoryId then return end

  local data = getCarjackData(inventoryId)
  if not data or not data.stolen or not data.maximumHeat then return end

  local police = getPoliceModule()
  if not police or not police.setPursuitMode then return end
  local traffic = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  local targetTraffic = traffic[playerId]
  if not targetTraffic then return end

  -- RLS police resets its internal suspect-active flag whenever no police are
  -- active. Preserve the actual target pursuit level independently.
  local pursuitMode = targetTraffic.pursuit and tonumber(targetTraffic.pursuit.mode) or 0
  local roleName = targetTraffic.role and targetTraffic.role.name or targetTraffic.roleName
  if pursuitMode < cfg.policeCarjackLevel or roleName ~= "suspect" then
    pcall(function() police.setPursuitMode(cfg.policeCarjackLevel, playerId, {}) end)
  end

  -- Never allow the stolen police configuration itself to count as a cop.
  -- This also keeps autoRole='standard' if traffic refreshes the vehicle after
  -- the player exits/resets it. Replacement spawning is done only once during
  -- the initial theft alert; the maintenance loop only wakes existing cops.
  sanitizeStolenPoliceTraffic(playerId)
  local responders = wakePoliceResponders(playerId)
  local unassigned = {}
  local policeVehs = police.getPoliceVehicles and police.getPoliceVehicles() or {}
  for _, policeId in ipairs(responders) do
    local policeVeh = policeVehs[policeId]
    if policeVeh and policeVeh.role and policeVeh.role.state ~= "disabled"
      and policeVeh.role.targetId ~= playerId
      and not policeCommittedToOtherPursuit(policeVeh, playerId) then
      unassigned[#unassigned + 1] = policeId
    end
  end
  if #unassigned > 0 then
    pcall(function() police.setPursuitMode(cfg.policeCarjackLevel, playerId, unassigned) end)
  end
end

local function processIdentityScan(dtReal)
  identityScanTimer = identityScanTimer - dtReal
  if identityScanTimer > 0 then return end
  identityScanTimer = cfg.identityScanInterval

  if gameplay_walk and gameplay_walk.isWalking and gameplay_walk.isWalking() then return end

  local playerId = be:getPlayerVehicleID(0)
  if not playerId or playerId < 0 then return end

  local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId and career_modules_inventory.getInventoryIdFromVehicleId(playerId) or nil
  if not inventoryId then return end

  local data = getCarjackData(inventoryId)
  if not data or not data.stolen then return end

  -- Legacy 0.2.0 saves used vinChanged/plateFlagAt. Treat those as the same
  -- abstract identity state so updating the mod does not re-flag a laundered car.
  if data.vinChanged == true and data.identityChanged ~= true then
    data.identityChanged = true
  end
  if data.identityChanged then return end

  local flagAt = data.identityFlagAt or data.plateFlagAt
  if not flagAt then
    flagAt = (tonumber(data.stolenAt) or nowPersistentTime()) + cfg.identityFlagDelaySeconds
    data.identityFlagAt = flagAt
    markVehicleDirty(inventoryId)
  end
  if nowPersistentTime() < flagAt then return end

  local police = getPoliceModule()
  if not police or not police.getNearestPoliceVehicle or not police.setPursuitMode then return end

  if police.isVehicleInPursuit then
    local ok, inPursuit = pcall(function() return police.isVehicleInPursuit(playerId) end)
    if ok and inPursuit then return end
  end

  local ok, policeId, distance = pcall(function()
    return police.getNearestPoliceVehicle(playerId, true, true)
  end)
  if not ok or not policeId or not distance or distance > cfg.identityScanRadius then return end

  local level = data.maximumHeat and cfg.policeCarjackLevel or cfg.identityPursuitLevel
  pcall(function() police.setPursuitMode(level, playerId, {policeId}) end)
  message(data.maximumHeat and "STOLEN POLICE VEHICLE IDENTIFIED — MAXIMUM HEAT!" or "STOLEN VEHICLE IDENTIFIED — police recognize the vehicle!", 5)
end

local function calculateIdentityChangeCost(inventoryId)
  if not isStolenInventoryVehicle(inventoryId) then return nil end
  local data = getCarjackData(inventoryId)
  if not data or data.identityChanged or data.vinChanged or data.identityChangeCompleteAt then return nil end
  if data.policeVehicleTheft == true then return nil end

  local currentValue = safeInventoryValue(inventoryId)
  currentValue = positiveNumber(currentValue)
  if not currentValue then return nil end

  local multiplier = math.max(0, tonumber(cfg.identityChangeCostMultiplier) or 0)
  local cost = math.max(0, math.floor(currentValue * multiplier + 0.5))
  return cost, currentValue
end

local function paintsVisuallyEqual(a, b)
  local ca = type(a) == "table" and a.baseColor or nil
  local cb = type(b) == "table" and b.baseColor or nil
  if type(ca) ~= "table" or type(cb) ~= "table" then return false end
  for i = 1, 3 do
    if math.abs((tonumber(ca[i]) or 0) - (tonumber(cb[i]) or 0)) > 0.01 then
      return false
    end
  end
  return true
end

local function chooseRandomIdentityPaint(vehicle)
  if not vehicle or not vehicle.model or not core_vehicles or not core_vehicles.getModel then return nil end
  local okModel, modelData = pcall(function() return core_vehicles.getModel(vehicle.model) end)
  local paints = okModel and modelData and modelData.model and modelData.model.paints or nil
  if type(paints) ~= "table" then return nil end

  local currentPaint = vehicle.config and vehicle.config.paints and vehicle.config.paints[1] or nil
  local candidates = {}
  local allCandidates = {}
  for name, paint in pairs(paints) do
    if type(paint) == "table" then
      allCandidates[#allCandidates + 1] = {name = tostring(name), paint = paint}
      if not currentPaint or not paintsVisuallyEqual(currentPaint, paint) then
        candidates[#candidates + 1] = {name = tostring(name), paint = paint}
      end
    end
  end

  if #candidates == 0 then candidates = allCandidates end
  if #candidates == 0 then return nil end
  local selected = candidates[math.random(1, #candidates)]
  return deepcopy(selected.paint), selected.name
end

local function applyRandomIdentityPaint(inventoryId, vehicle)
  local paint, paintName = chooseRandomIdentityPaint(vehicle)
  if not paint then return nil end

  local paints = {deepcopy(paint), deepcopy(paint), deepcopy(paint)}
  local snapshot = {
    paints = paints,
    config = {paints = deepcopy(paints)},
    objectFields = {}
  }
  local liveId = career_modules_inventory.getVehicleIdFromInventoryId
    and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId) or nil
  persistStolenPaints(inventoryId, liveId, snapshot)
  return paintName
end

local function fallbackRandomPlateText()
  local letters = "ABCDEFGHJKLMNPRSTUVWXYZ"
  local function letter()
    local i = math.random(1, #letters)
    return string.sub(letters, i, i)
  end
  return string.format("%s%s%s-%04d", letter(), letter(), letter(), math.random(0, 9999))
end

local function applyRandomIdentityPlate(inventoryId, vehicle)
  vehicle.config = vehicle.config or {}
  local liveId = career_modules_inventory.getVehicleIdFromInventoryId
    and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId) or nil
  local obj = liveId and getObjectByID(liveId) or nil
  local oldPlate = tostring(vehicle.config.licenseName or "")
  local newPlate

  if obj and core_vehicles and core_vehicles.regenerateVehicleLicenseText then
    for _ = 1, 8 do
      local ok, candidate = pcall(function() return core_vehicles.regenerateVehicleLicenseText(obj) end)
      candidate = ok and candidate and tostring(candidate) or ""
      if candidate ~= "" and candidate ~= oldPlate then
        newPlate = candidate
        break
      end
    end
  end

  newPlate = newPlate or fallbackRandomPlateText()
  vehicle.config.licenseName = newPlate

  if obj then
    if core_vehicles and core_vehicles.setPlateText then
      pcall(function() core_vehicles.setPlateText(newPlate, liveId) end)
    elseif obj.setDynDataFieldbyName then
      pcall(function() obj:setDynDataFieldbyName("licenseText", 0, newPlate) end)
    end
  end
  markVehicleDirty(inventoryId)
  return newPlate
end

local function finalizeVehicleIdentityChange(inventoryId, paidCost)
  local data, vehicle = getCarjackData(inventoryId)
  if not data or not data.stolen or not vehicle then return false end
  if data.policeVehicleTheft == true then
    data.identityChangeStartedAt = nil
    data.identityChangeCompleteAt = nil
    data.identityChangePaidCost = nil
    markVehicleDirty(inventoryId)
    return false
  end
  if data.identityChanged or data.vinChanged then return true end

  local paintName = applyRandomIdentityPaint(inventoryId, vehicle)
  local newPlate = applyRandomIdentityPlate(inventoryId, vehicle)

  data.identityChanged = true
  data.insuranceUnlocked = true
  data.identityChangedAt = nowPersistentTime()
  data.identityChangeStartedAt = nil
  data.identityChangeCompleteAt = nil
  data.identityChangePaidCost = nil
  data.changedIdentityPlate = newPlate
  data.changedIdentityPaint = paintName

  -- Move from the private identity-locked state into RLS's normal uninsured
  -- pool immediately. The player can then use Insurance -> Add Coverage.
  local insurance = getInsuranceModule()
  if insurance and insurance.getInvVehs then
    local okInv, invVehs = pcall(function() return insurance.getInvVehs() end)
    if okInv and type(invVehs) == "table" then
      local entry = invVehs[inventoryId] or invVehs[tostring(inventoryId)]
      if entry and entry.insuranceId == identityLockedInsuranceId then
        entry.insuranceId = -1
      end
    end
  end

  -- Old versions used this as their compatibility marker. Keep writing it so
  -- saves remain readable by the 0.2.x migration logic; no native VIN exists.
  data.vinChanged = true

  markVehicleDirty(inventoryId)
  requestCareerSave(0.1)

  local cost = math.max(0, math.floor(tonumber(paidCost) or 0))
  if paintName then
    message(string.format("Vehicle identity changed for $%d. New plate: %s; repaint: %s.", cost, tostring(newPlate), tostring(paintName)), 6)
  else
    message(string.format("Vehicle identity changed for $%d. New plate: %s.", cost, tostring(newPlate)), 6)
  end
  return true
end

local function changeVehicleIdentity(inventoryId)
  local data, vehicle = getCarjackData(inventoryId)
  if not data or not data.stolen or not vehicle then
    message("Only stolen vehicles can have their identity changed.", 3)
    return false
  end
  if data.policeVehicleTheft == true then
    message("Police vehicles cannot have their identity changed.", 4)
    return false
  end
  if data.identityChanged or data.vinChanged then
    message("This vehicle's identifying markings have already been changed.", 3)
    return false
  end
  if data.identityChangeCompleteAt then
    local remaining = math.max(0, math.ceil((tonumber(data.identityChangeCompleteAt) or nowPersistentTime()) - nowPersistentTime()))
    message(string.format("Vehicle identity change is already in progress (%ds remaining).", remaining), 4)
    return false
  end

  local cost = calculateIdentityChangeCost(inventoryId)
  if cost == nil then
    message("Unable to determine the identity-change cost.", 4)
    return false
  end

  local payment = getPaymentModule()
  if not payment or not payment.canPay or not payment.pay then
    message("RLS payment service is unavailable.", 4)
    return false
  end

  local price = {money = {amount = cost, canBeNegative = false}}
  local canPay = false
  local okCanPay, result = pcall(function() return payment.canPay(price) end)
  if okCanPay then canPay = result and true or false end
  if not canPay then
    message(string.format("Changing the vehicle identity costs $%d.", cost), 4)
    return false
  end

  -- Make sure RLS has a structurally valid locked insurance record before the
  -- service starts. RLS remains responsible for policy selection after it ends.
  ensureStolenInsuranceState(inventoryId)

  local okPay, payErr = pcall(function()
    payment.pay(price, {
      label = string.format("Changed vehicle identity for %s", plainVehicleName(vehicle, inventoryId)),
      tags = {"vehicle", "service"}
    })
  end)
  if not okPay then
    log("E", logTag, "Vehicle-identity payment failed: " .. tostring(payErr))
    message("Unable to process the identity-change payment.", 4)
    return false
  end

  local duration = math.max(0, tonumber(cfg.identityChangeDurationSeconds) or 0)
  if duration > 0 then
    local now = nowPersistentTime()
    data.identityChangeStartedAt = now
    data.identityChangeCompleteAt = now + duration
    data.identityChangePaidCost = cost
    markVehicleDirty(inventoryId)
    requestCareerSave(0.1)
    message(string.format("Vehicle identity change started. Completion in %ds.", math.ceil(duration)), 5)
  else
    finalizeVehicleIdentityChange(inventoryId, cost)
  end

  if career_career and career_career.closeAllMenus then
    pcall(function() career_career.closeAllMenus() end)
  end
  return true
end

local function processPendingIdentityChanges(dtReal)
  identityChangeProcessTimer = identityChangeProcessTimer - dtReal
  if identityChangeProcessTimer > 0 then return end
  identityChangeProcessTimer = 0.50

  local now = nowPersistentTime()
  local vehicles = career_modules_inventory.getVehicles and career_modules_inventory.getVehicles() or {}
  for inventoryId, vehicle in pairs(vehicles or {}) do
    local data = vehicle and vehicle.rlsCarjack or nil
    if data and data.stolen and not data.identityChanged and not data.vinChanged and data.identityChangeCompleteAt then
      if data.policeVehicleTheft == true then
        data.identityChangeStartedAt = nil
        data.identityChangeCompleteAt = nil
        data.identityChangePaidCost = nil
        markVehicleDirty(inventoryId)
      elseif now >= (tonumber(data.identityChangeCompleteAt) or math.huge) then
        finalizeVehicleIdentityChange(inventoryId, data.identityChangePaidCost or 0)
      end
    end
  end
end

local function calculateStripValue(inventoryId)
  if not isStolenInventoryVehicle(inventoryId) then return nil end
  local calculator = getValueCalculator()
  if not calculator or not calculator.getInventoryVehicleValue then return nil end

  local ok, currentValue = pcall(function()
    return calculator.getInventoryVehicleValue(inventoryId)
  end)
  currentValue = ok and positiveNumber(currentValue) or nil
  if not currentValue then return nil end

  return math.max(1, math.floor(currentValue * cfg.stripPartsMultiplier + 0.5)), currentValue
end

local function stripVehicleForParts(inventoryId)
  if not inventoryId or not isStolenInventoryVehicle(inventoryId) then
    message("Only stolen vehicles can be stripped for parts.", 3)
    return false
  end

  local function finishStrip()
    if not isStolenInventoryVehicle(inventoryId) then return false end

    local payout = calculateStripValue(inventoryId)
    if not payout then
      message("Unable to determine a safe current value. Vehicle was not removed.", 4)
      return false
    end

    if not career_modules_inventory.sellVehicle then
      message("RLS vehicle removal is unavailable. Vehicle was not removed.", 4)
      return false
    end

    local ok, sold = pcall(function()
      return career_modules_inventory.sellVehicle(inventoryId, payout)
    end)
    if not ok or sold ~= true then
      message("Unable to strip this vehicle. Vehicle was not removed.", 4)
      return false
    end

    observedSpawnedVehicles[inventoryId] = nil
    pendingSafePark[inventoryId] = nil
    carjackArrestGrace[inventoryId] = nil
    message(string.format("Stolen vehicle stripped for parts: $%d", payout), 4)
    if career_career and career_career.closeAllMenus then
      pcall(function() career_career.closeAllMenus() end)
    end
    return true
  end

  -- Refresh live damage first so the payout reflects the vehicle's current
  -- condition rather than a stale pre-crash value.
  local vehId = career_modules_inventory.getVehicleIdFromInventoryId
    and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId) or nil
  if vehId and career_modules_inventory.updatePartConditions then
    local ok = pcall(function()
      career_modules_inventory.updatePartConditions(vehId, inventoryId, finishStrip)
    end)
    if ok then return true end
  end

  return finishStrip()
end

-- Add stolen-vehicle management actions to the garage computer.
local function onComputerAddFunctions(menuData, computerFunctions)
  if not menuData or not computerFunctions or type(computerFunctions.vehicleSpecific) ~= "table" then return end

  for _, vehicleData in ipairs(menuData.vehiclesInGarage or {}) do
    local inventoryId = vehicleData.inventoryId
    if inventoryId and isStolenInventoryVehicle(inventoryId) then
      local bucket = computerFunctions.vehicleSpecific[inventoryId]
      local data = getCarjackData(inventoryId)
      if type(bucket) == "table" then
        if data and data.policeVehicleTheft ~= true and not data.identityChanged and not data.vinChanged then
          if data.identityChangeCompleteAt then
            local remaining = math.max(0, math.ceil((tonumber(data.identityChangeCompleteAt) or nowPersistentTime()) - nowPersistentTime()))
            bucket.rlsCarjackingIdentityInProgress = {
              id = "rlsCarjackingIdentityInProgress",
              label = string.format("Identity Change in Progress (%ds)", remaining),
              callback = function()
                message(string.format("Vehicle identity change is in progress (%ds remaining).", math.max(0, math.ceil((tonumber(data.identityChangeCompleteAt) or nowPersistentTime()) - nowPersistentTime()))), 4)
              end,
              order = 90
            }
          else
            local cost = calculateIdentityChangeCost(inventoryId)
            local identityLabel = cost ~= nil and string.format("Change Vehicle Identity ($%d)", cost) or "Change Vehicle Identity"
            bucket.rlsCarjackingChangeIdentity = {
              id = "rlsCarjackingChangeIdentity",
              label = identityLabel,
              callback = function()
                changeVehicleIdentity(inventoryId)
              end,
              order = 90
            }
          end
        end

        bucket.rlsCarjackingStripForParts = {
          id = "rlsCarjackingStripForParts",
          label = string.format("Strip for Parts (%g%% value)", (tonumber(cfg.stripPartsMultiplier) or 0) * 100),
          callback = function()
            stripVehicleForParts(inventoryId)
          end,
          order = 95
        }
      end
    end
  end
end

-- RLS speed traps normally treat every owned inventory vehicle as chargeable.
-- For a stolen vehicle, temporarily mask only the `owned` flag while the
-- original handler runs. This prevents the fine/ticket but still allows RLS to
-- process the speed-trap record/leaderboard normally. The flag is restored in
-- the same call, so no ownership state is persisted or exposed elsewhere.
local function callSpeedTrapWithoutOwnershipFine(handler, speedTrapData, ...)
  local vehId = speedTrapData and speedTrapData.subjectID
  local inventoryId = vehId and career_modules_inventory.getInventoryIdFromVehicleId and career_modules_inventory.getInventoryIdFromVehicleId(vehId) or nil
  local vehicle = inventoryId and getInventoryVehicle(inventoryId) or nil

  if not inventoryId or not vehicle or not isStolenInventoryVehicle(inventoryId) then
    return handler(speedTrapData, ...)
  end

  local oldOwned = vehicle.owned
  vehicle.owned = false
  local ok, err = pcall(handler, speedTrapData, ...)
  vehicle.owned = oldOwned

  if not ok then
    log("E", logTag, "RLS speed-trap handler failed: " .. tostring(err))
  end
  return nil
end

local function installSpeedTrapExemption()
  local speedTraps = rawget(_G, "career_modules_speedTraps")
  if not speedTraps then return false end

  if not originalSpeedTrapHandler and type(speedTraps.onSpeedTrapTriggered) == "function" then
    originalSpeedTrapHandler = speedTraps.onSpeedTrapTriggered
    wrappedSpeedTrapHandler = function(speedTrapData, playerSpeed, overSpeed)
      return callSpeedTrapWithoutOwnershipFine(originalSpeedTrapHandler, speedTrapData, playerSpeed, overSpeed)
    end
    speedTraps.onSpeedTrapTriggered = wrappedSpeedTrapHandler
  end

  -- Red-light cameras do not use the same ownership check. Treat them like
  -- other automated cameras for stolen cars: the camera may flash, but the
  -- player is not billed as the registered owner.
  if not originalRedLightHandler and type(speedTraps.onRedLightCamTriggered) == "function" then
    originalRedLightHandler = speedTraps.onRedLightCamTriggered
    wrappedRedLightHandler = function(speedTrapData, playerSpeed)
      local vehId = speedTrapData and speedTrapData.subjectID
      local inventoryId = vehId and career_modules_inventory.getInventoryIdFromVehicleId and career_modules_inventory.getInventoryIdFromVehicleId(vehId) or nil
      if inventoryId and isStolenInventoryVehicle(inventoryId) then
        return nil
      end
      return originalRedLightHandler(speedTrapData, playerSpeed)
    end
    speedTraps.onRedLightCamTriggered = wrappedRedLightHandler
  end

  return originalSpeedTrapHandler ~= nil
end

local function restoreSpeedTrapExemption()
  local speedTraps = rawget(_G, "career_modules_speedTraps")
  if speedTraps then
    if originalSpeedTrapHandler and speedTraps.onSpeedTrapTriggered == wrappedSpeedTrapHandler then
      speedTraps.onSpeedTrapTriggered = originalSpeedTrapHandler
    end
    if originalRedLightHandler and speedTraps.onRedLightCamTriggered == wrappedRedLightHandler then
      speedTraps.onRedLightCamTriggered = originalRedLightHandler
    end
  end
  originalSpeedTrapHandler = nil
  wrappedSpeedTrapHandler = nil
  originalRedLightHandler = nil
  wrappedRedLightHandler = nil
end

local function applySafeParkState(vehId)
  local obj = vehId and getObjectByID(vehId) or nil
  if not obj then return false end

  -- GE-side ignition action is the same API RLS itself uses when parking or
  -- teleporting inventory vehicles.
  if core_vehicleBridge and core_vehicleBridge.executeAction then
    pcall(function() core_vehicleBridge.executeAction(obj, "setIgnitionLevel", 0) end)
  end

  -- Vehicle-side controller APIs are generic across the stock powertrain
  -- controllers. Neutral + smart parking brake is safer than guessing an
  -- automatic transmission's Park index, and works for manuals as well.
  pcall(function()
    obj:queueLuaCommand([[
      if input and input.event then
        input.event("throttle", 0, FILTER_DIRECT)
        input.event("brake", 0, FILTER_DIRECT)
        input.event("clutch", 0, FILTER_DIRECT)
      end
      if controller and controller.mainController then
        if controller.mainController.shiftToGearIndex then
          controller.mainController.shiftToGearIndex(0)
        end
        if controller.mainController.smartParkingBrake then
          controller.mainController.smartParkingBrake(1, FILTER_DIRECT, true)
        elseif input and input.event then
          input.event("parkingbrake", 1, FILTER_DIRECT)
        end
        if controller.mainController.setEngineIgnition then
          controller.mainController.setEngineIgnition(false)
        elseif electrics and electrics.setIgnitionLevel then
          electrics.setIgnitionLevel(0)
        end
      elseif electrics and electrics.setIgnitionLevel then
        electrics.setIgnitionLevel(0)
      end
    ]])
  end)
  return true
end

local function scheduleSafePark(inventoryId, vehId)
  if not inventoryId or not vehId then return end
  pendingSafePark[inventoryId] = {
    vehId = vehId,
    timer = 0.05,
    attempts = 8
  }
end

local function processSpawnSafeParkChecks(dtReal)
  for vehId, pending in pairs(pendingSpawnSafePark) do
    pending.timer = pending.timer - dtReal
    if pending.timer <= 0 then
      local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId
        and career_modules_inventory.getInventoryIdFromVehicleId(vehId) or nil

      if inventoryId and isStolenInventoryVehicle(inventoryId) then
        -- The initial theft is already marked as observed before the player
        -- takes control. Only retrieval/re-spawn events should be parked.
        if observedSpawnedVehicles[inventoryId] ~= vehId and be:getPlayerVehicleID(0) ~= vehId then
          observedSpawnedVehicles[inventoryId] = vehId
          scheduleSafePark(inventoryId, vehId)
        end
        pendingSpawnSafePark[vehId] = nil
      else
        pending.attempts = pending.attempts - 1
        if pending.attempts <= 0 or not getObjectByID(vehId) then
          pendingSpawnSafePark[vehId] = nil
        else
          pending.timer = 0.12
        end
      end
    end
  end
end

local function monitorRetrievedStolenVehicles(dtReal)
  -- Vehicle spawn/destroy hooks handle the normal retrieval path. Keep this
  -- inventory-wide scan only as a compatibility fallback, and throttle it so
  -- large career inventories are not traversed every rendered frame.
  retrievalMonitorTimer = retrievalMonitorTimer - dtReal
  if retrievalMonitorTimer <= 0 then
    retrievalMonitorTimer = 0.50
    local vehicles = career_modules_inventory.getVehicles and career_modules_inventory.getVehicles() or {}

    -- Clean observations for deleted/non-stolen inventory entries.
    for inventoryId, _ in pairs(observedSpawnedVehicles) do
      local vehicle = vehicles[inventoryId]
      if not vehicle or not (vehicle.rlsCarjack and vehicle.rlsCarjack.stolen) then
        observedSpawnedVehicles[inventoryId] = nil
        pendingSafePark[inventoryId] = nil
      end
    end

    for inventoryId, vehicle in pairs(vehicles or {}) do
      if vehicle and vehicle.rlsCarjack and vehicle.rlsCarjack.stolen then
        local vehId = career_modules_inventory.getVehicleIdFromInventoryId and career_modules_inventory.getVehicleIdFromInventoryId(inventoryId) or nil
        if vehId then
          if observedSpawnedVehicles[inventoryId] ~= vehId then
            observedSpawnedVehicles[inventoryId] = vehId
            -- Never interrupt the actively driven car. The initial carjacking
            -- path seeds observedSpawnedVehicles before the player enters it.
            if be:getPlayerVehicleID(0) ~= vehId then
              scheduleSafePark(inventoryId, vehId)
            end
          end
        else
          observedSpawnedVehicles[inventoryId] = nil
          pendingSafePark[inventoryId] = nil
        end
      end
    end
  end

  -- Pending safe-park operations remain frame-timed so the short delayed reset
  -- still happens promptly after a vehicle is retrieved.
  for inventoryId, pending in pairs(pendingSafePark) do
    pending.timer = pending.timer - dtReal
    if pending.timer <= 0 then
      -- If the player entered the car before the delayed reset, leave it alone.
      if be:getPlayerVehicleID(0) == pending.vehId then
        pendingSafePark[inventoryId] = nil
      elseif not getObjectByID(pending.vehId) then
        pendingSafePark[inventoryId] = nil
      else
        applySafeParkState(pending.vehId)
        pending.attempts = pending.attempts - 1
        if pending.attempts <= 0 then
          pendingSafePark[inventoryId] = nil
        else
          pending.timer = 0.18
        end
      end
    end
  end
end

local function processDeferredWork(dtReal)
  if pendingPaintRestore then
    pendingPaintRestore.timer = pendingPaintRestore.timer - dtReal
    if pendingPaintRestore.timer <= 0 then
      restoreVehiclePaintSnapshot(pendingPaintRestore.vehId, pendingPaintRestore.snapshot)
      pendingPaintRestore.attempts = (pendingPaintRestore.attempts or 1) - 1
      if pendingPaintRestore.attempts <= 0 then
        pendingPaintRestore = nil
      else
        pendingPaintRestore.timer = 0.20
      end
    end
  end

  if pendingCareerSaveTimer ~= nil then
    pendingCareerSaveTimer = pendingCareerSaveTimer - dtReal
    if pendingCareerSaveTimer <= 0 then
      pendingCareerSaveTimer = nil
      saveCareer()
    end
  end
end

local function onUpdate(dtReal, dtSim, dtRaw)
  dtReal = tonumber(dtReal) or 0

  processPendingHotwire()
  processHotwireRelease(dtReal)
  processTrafficReplacements(dtReal)
  processPendingIdentityChanges(dtReal)

  -- Run the handoff guard before assigning/maintaining police pursuit.
  processCarjackArrestGrace(dtReal)
  processImmediateAlert(dtReal)
  processMaximumHeat(dtReal)
  processIdentityScan(dtReal)
  processDeferredWork(dtReal)
  processSpawnSafeParkChecks(dtReal)
  monitorRetrievedStolenVehicles(dtReal)

  if not originalSpeedTrapHandler then
    speedTrapInstallRetry = speedTrapInstallRetry - dtReal
    if speedTrapInstallRetry <= 0 then
      speedTrapInstallRetry = 1.0
      installSpeedTrapExemption()
    end
  end

  insuranceCleanupTimer = insuranceCleanupTimer - dtReal
  if insuranceCleanupTimer <= 0 then
    insuranceCleanupTimer = 2.0
    enforceStolenVehicleState()
  end
end

local function onVehicleSpawned(vehId)
  vehId = tonumber(vehId) or vehId
  if not vehId then return end
  pendingSpawnSafePark[vehId] = {timer = 0.05, attempts = 12}
end

local function onVehicleDestroyed(vehId)
  vehId = tonumber(vehId) or vehId
  if not vehId then return end
  pendingSpawnSafePark[vehId] = nil
  for inventoryId, observedVehId in pairs(observedSpawnedVehicles) do
    if observedVehId == vehId then
      observedSpawnedVehicles[inventoryId] = nil
      pendingSafePark[inventoryId] = nil
    end
  end
end

local function onVehicleAdded(inventoryId)
  inventoryId = tonumber(inventoryId) or inventoryId
  if inventoryId and isStolenInventoryVehicle(inventoryId) then
    ensureInventoryBaseValue(inventoryId)
    applyStolenMarketDiscount(inventoryId)
    ensureStolenInsuranceState(inventoryId)

    -- RLS emits onVehicleAdded only after its asynchronous part-condition
    -- initialization completes. Reapply the original live paint here so both
    -- the renderer and saved part paint state retain the traffic-car color.
    local snapshot = pendingInventoryPaintSnapshots[inventoryId]
    if snapshot then
      persistStolenPaints(inventoryId, nil, snapshot)
      pendingInventoryPaintSnapshots[inventoryId] = nil
      requestCareerSave(0.25)
    end
  end
end

local function cleanupSpawnedPoliceResponders()
  for policeId, _ in pairs(spawnedPoliceResponderIds) do
    -- Never delete a responder that has since become a career inventory car.
    local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId
      and career_modules_inventory.getInventoryIdFromVehicleId(policeId) or nil
    if not inventoryId then
      if gameplay_traffic and gameplay_traffic.removeTraffic then
        pcall(function() gameplay_traffic.removeTraffic(policeId, true) end)
      end
      local obj = getObjectByID(policeId)
      if obj then pcall(function() obj:delete() end) end
    end
    spawnedPoliceResponderIds[policeId] = nil
  end
end

local function onExtensionLoaded()
  installWalkingModeWrapper()
  installSpeedTrapExemption()
  enforceStolenVehicleState()
end

local function onCareerModulesActivated(alreadyInLevel)
  installWalkingModeWrapper()
  installSpeedTrapExemption()
  enforceStolenVehicleState()
end

local function onExtensionUnloaded()
  pendingHotwire = nil
  pendingHotwireRelease = {}
  quickAccessInitialized = false
  cleanupSpawnedPoliceResponders()
  restoreSpeedTrapExemption()
  restoreWalkingModeWrapper()
end

M.isStolenInventoryVehicle = isStolenInventoryVehicle
M.changeVehicleIdentity = changeVehicleIdentity
M.changeVehicleVin = changeVehicleIdentity -- 0.2.0 compatibility alias
M.stripVehicleForParts = stripVehicleForParts
M.hotwireSaleVehicle = function() return completeSaleVehicleHotwire(getHotwireCandidate()) end
M.getConfig = function() return cfg end

M.onVehicleSpawned = onVehicleSpawned
M.onVehicleDestroyed = onVehicleDestroyed
M.onVehicleAdded = onVehicleAdded
M.onComputerAddFunctions = onComputerAddFunctions
M.onBeforeRadialOpened = onBeforeRadialOpened
M.onQuickAccessLoaded = onQuickAccessLoaded
M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onCareerModulesActivated = onCareerModulesActivated
M.onExtensionUnloaded = onExtensionUnloaded

return M
