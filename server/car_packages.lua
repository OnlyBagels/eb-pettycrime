local Config = require'shared.config'
local Systems = require'shared.systems'
local ServerConfig = require'shared.server_config'

local vehiclePackages = {}
local playerActionCooldowns = {}
local validPassengerSeats = { 'seat_pside_f', 'seat_dside_r', 'seat_pside_r' }

local function debugLog(message)
    if Config.debug then
        print("^2[CAR-PACKAGE-SERVER] " .. message .. "^7")
    end
end

local function canPlayerPerformAction(source, action, cooldownMs)
    local key = source .. '_' .. action
    local currentTime = GetGameTimer()
    
    if playerActionCooldowns[key] and (currentTime - playerActionCooldowns[key]) < cooldownMs then
        return false, math.ceil((cooldownMs - (currentTime - playerActionCooldowns[key])) / 1000)
    end
    
    playerActionCooldowns[key] = currentTime
    return true
end

local function hasDriver(vehicle)
    return GetPedInVehicleSeat(vehicle, -1) > 0
end

local function hasPassengers(vehicle)
    if GetPedInVehicleSeat(vehicle, 0) > 0 then return true end
    
    for i = 1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, i)
        if ped and ped > 0 then return true end
    end
    
    return false
end


local function isValidVehicle(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    
    local popType = GetEntityPopulationType(vehicle)
    if popType ~= 2 and popType ~= 5 and popType ~= 7 then return false end
    
    local entityType = GetEntityType(vehicle)
    if entityType ~= 2 then return false end
    
    local velocity = GetEntityVelocity(vehicle)
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    if speed > 0.5 then return false end
    
    if hasDriver(vehicle) or hasPassengers(vehicle) then
        return false
    end
    
    local model = GetEntityModel(vehicle)
    if Config.blacklistedModels and Config.blacklistedModels[model] then return false end
    
    return true
end

local function getRandomPackageProp()
    local totalWeight = 0
    local props = {}
    
    for propHash, propData in pairs(ServerConfig.packageProps) do
        totalWeight = totalWeight + propData.weight
        props[#props + 1] = { hash = propHash, weight = propData.weight, data = propData }
    end
    
    local randomValue = math.random() * totalWeight
    local currentWeight = 0
    
    for _, prop in ipairs(props) do
        currentWeight = currentWeight + prop.weight
        if randomValue <= currentWeight then
            return prop.hash, prop.data
        end
    end
    
    local firstProp = next(ServerConfig.packageProps)
    return firstProp, ServerConfig.packageProps[firstProp]
end

local function getRewardFromProp(propHash)
    local propData = ServerConfig.packageProps[propHash]
    if not propData or not propData.rewards then return nil end
    
    local totalChance = 0
    for _, reward in ipairs(propData.rewards) do
        totalChance = totalChance + reward.chance
    end
    
    if totalChance == 0 then return propData.rewards[1] end
    
    local randomValue = math.random() * totalChance
    local currentChance = 0
    
    for _, reward in ipairs(propData.rewards) do
        currentChance = currentChance + reward.chance
        if randomValue <= currentChance then return reward end
    end
    
    return propData.rewards[1]
end

local function shouldSpawnPackage()
    if not Systems.Time.isAllowedTime() then return false end
    
    if Config.policeRequired then
        local hasEnoughPolice = Systems.Police.checkRequirement()
        if not hasEnoughPolice then return false end
    end
    
    local randomRoll = math.random(1, 100)
    return randomRoll <= Config.packageSettings.spawnChance
end

lib.callback.register('eb-pettycrime-package:server:StealPackage', function(source, vehicleNetId)
    local src = source
    
    debugLog("StealPackage callback called by player " .. src)
    
    if not Systems.Security.validateInput(src, 'source') then
        debugLog("Invalid source: " .. tostring(src))
        return false, 'Invalid request'
    end
    
    if not Systems.Security.validateInput(vehicleNetId, 'networkId') then
        debugLog("Invalid network ID: " .. tostring(vehicleNetId))
        return false, 'Invalid vehicle'
    end
    
    local canPerform, timeLeft = canPlayerPerformAction(src, 'steal_package', 2000)
    if not canPerform then
        debugLog("Player " .. src .. " on cooldown for " .. timeLeft .. " seconds")
        return false, 'Please wait ' .. timeLeft .. ' seconds before trying again'
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not vehicle or not DoesEntityExist(vehicle) then
        debugLog("Vehicle not found for network ID: " .. vehicleNetId)
        return false, 'Vehicle not found'
    end
    
    local vehCoords = GetEntityCoords(vehicle)
    if not Systems.Security.validatePlayerPosition(src, vehCoords, Config.packageSettings.interactionDistance * 2) then
        debugLog("Player " .. src .. " too far from vehicle")
        return false, 'Too far from vehicle'
    end
    
    local vehicleKey = tostring(vehicle)
    local packageData = vehiclePackages[vehicleKey]
    local hasPackageState = Entity(vehicle).state.hasPackage
    
    debugLog("Package data exists: " .. tostring(packageData ~= nil))
    debugLog("Has package state: " .. tostring(hasPackageState))
    
    if not packageData and not hasPackageState then
        debugLog("No package found on vehicle " .. vehicle)
        return false, 'No package found'
    end
    
    if not packageData then
        packageData = Entity(vehicle).state.loadPackage
        debugLog("Retrieved package data from state bag")
    end
    
    if not packageData then
        debugLog("Package data error - no data available")
        return false, 'Package data error'
    end
    
    if Config.policeRequired then
        local hasEnoughPolice = Systems.Police.checkRequirement()
        if not hasEnoughPolice then
            debugLog("Not enough police online")
            return false, 'Not enough police online'
        end
    end
    
    local propHash = packageData.propHash or packageData.model
    if not propHash then
        debugLog("No prop hash found in package data")
        return false, 'Package data error'
    end
    
    local rewardItem = getRewardFromProp(propHash)
    if not rewardItem then
        debugLog("No reward available for prop: " .. tostring(propHash))
        return false, 'No reward available'
    end
    
    local amount = math.random(rewardItem.minAmount, rewardItem.maxAmount)
    debugLog("Reward: " .. rewardItem.item .. " x" .. amount)
    
    if not exports.ox_inventory:CanCarryItem(src, rewardItem.item, amount) then
        debugLog("Player " .. src .. " inventory full")
        return false, 'Your inventory is too full'
    end
    
    local success = exports.ox_inventory:AddItem(src, rewardItem.item, amount)
    if not success then
        debugLog("Failed to add item to player " .. src .. " inventory")
        return false, 'Failed to add item to inventory'
    end
    
    debugLog("Successfully gave " .. amount .. "x " .. rewardItem.item .. " to player " .. src)
    
    vehiclePackages[vehicleKey] = nil
    Entity(vehicle).state:set('loadPackage', nil, true)
    Entity(vehicle).state:set('hasPackage', false, true)
    
    return true, 'success', rewardItem.item, amount
end)

AddEventHandler('entityCreated', function(handle)
    if not handle or not DoesEntityExist(handle) then return end
    
    if not isValidVehicle(handle) then return end
    
    if not shouldSpawnPackage() then return end
    
    local vehicleKey = tostring(handle)
    if vehiclePackages[vehicleKey] then return end
    
    local hasPackage = false
    pcall(function()
        hasPackage = Entity(handle).state.hasPackage
    end)
    
    if hasPackage then return end
    if not DoesEntityExist(handle) then return end
    

    local selectedSeat = validPassengerSeats[math.random(1, #validPassengerSeats)]
    
    if not DoesEntityExist(handle) then return end
    
    local selectedProp = getRandomPackageProp()
    
    local propOffsets = {
        [`prop_drug_package_02`] = { x = 0.0, y = 0.0, z = 0.1 },
        [`prop_ld_case_01`] = { x = 0.0, y = 0.0, z = 0.25 },
        [`m23_1_prop_m31_laptop_01a`] = { x = 0.0, y = 0.0, z = 0.05 },
        [`ch_prop_ch_bag_01a`] = { x = 0.0, y = 0.0, z = 0.0 },
        [`v_ret_ml_beerbar`] = { x = 0.0, y = 0.0, z = 0.2 },
        [`xm3_prop_xm3_backpack_01a`] = { x = 0.0, y = 0.0, z = 0.0 }
    }
    
    local offset = propOffsets[selectedProp] or { x = 0.0, y = 0.0, z = 0.0 }
    
    local data = {
        model = selectedProp,
        boneID = nil, 
        offset = offset,
        rotation = math.random(0, 360) + 0.0,
        seatName = selectedSeat,
        propHash = selectedProp
    }
    
    vehiclePackages[vehicleKey] = data
    
    if DoesEntityExist(handle) then
        Entity(handle).state:set('loadPackage', data, true)
        Entity(handle).state:set('hasPackage', true, true)
        
        local vehCoords = GetEntityCoords(handle)
        debugLog("Package spawned at coordinates: " .. string.format("%.2f, %.2f, %.2f", vehCoords.x, vehCoords.y, vehCoords.z))
    else
        vehiclePackages[vehicleKey] = nil
    end
end)

AddEventHandler('entityRemoved', function(handle)
    if not handle then return end
    
    local vehicleKey = tostring(handle)
    if vehiclePackages[vehicleKey] then
        vehiclePackages[vehicleKey] = nil
        debugLog("Removed package data for deleted vehicle " .. handle)
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        
        local currentTime = GetGameTimer()
        local cleanedCooldowns = 0
        
        local expiredCooldowns = {}
        for key, timestamp in pairs(playerActionCooldowns) do
            if currentTime - timestamp > 300000 then
                expiredCooldowns[#expiredCooldowns + 1] = key
            end
        end
        
        for i = 1, #expiredCooldowns do
            playerActionCooldowns[expiredCooldowns[i]] = nil
            cleanedCooldowns = cleanedCooldowns + 1
        end
        
        local orphanedPackages = {}
        for vehicleKey in pairs(vehiclePackages) do
            local vehicleId = tonumber(vehicleKey)
            if vehicleId and not DoesEntityExist(vehicleId) then
                orphanedPackages[#orphanedPackages + 1] = vehicleKey
            end
        end
        
        for i = 1, #orphanedPackages do
            local vehicleKey = orphanedPackages[i]
            vehiclePackages[vehicleKey] = nil
        end
        
        if Config.debug and (cleanedCooldowns > 0 or #orphanedPackages > 0) then
            debugLog("Cleanup: " .. cleanedCooldowns .. " cooldowns, " .. #orphanedPackages .. " orphaned packages")
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    
    local keysToRemove = {}
    for key in pairs(playerActionCooldowns) do
        if string.find(key, tostring(src) .. '_') then
            keysToRemove[#keysToRemove + 1] = key
        end
    end
    
    for i = 1, #keysToRemove do
        playerActionCooldowns[keysToRemove[i]] = nil
    end
    
    if #keysToRemove > 0 then
        debugLog("Cleaned up " .. #keysToRemove .. " cooldowns for disconnected player " .. src)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource ~= resourceName then return end
    
    local cleanedVehicles = 0
    local vehicles = GetAllVehicles()
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if vehicle and DoesEntityExist(vehicle) then
            local vehicleKey = tostring(vehicle)
            if vehiclePackages[vehicleKey] then
                cleanedVehicles = cleanedVehicles + 1
            end
            vehiclePackages[vehicleKey] = nil
            Entity(vehicle).state:set('loadPackage', nil, true)
            Entity(vehicle).state:set('hasPackage', false, true)
        end
    end
    
    vehiclePackages = {}
    playerActionCooldowns = {}
    
    debugLog("Resource stopped: Cleaned up " .. cleanedVehicles .. " packages")
end)