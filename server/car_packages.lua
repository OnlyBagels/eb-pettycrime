local Config = require'shared.config'

local vehiclePackages = {}
local playerActionCooldowns = {}
local validPassengerSeats = { 'seat_pside_f', 'seat_dside_r', 'seat_pside_r' }

-- Helper function to get table size
local function tableSize(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local SecurityManager = {
    canPlayerPerformAction = function(source, action, cooldownMs)
        local key = source .. '_' .. action
        local currentTime = GetGameTimer()
        
        if playerActionCooldowns[key] and (currentTime - playerActionCooldowns[key]) < cooldownMs then
            return false, math.ceil((cooldownMs - (currentTime - playerActionCooldowns[key])) / 1000)
        end
        
        playerActionCooldowns[key] = currentTime
        return true
    end,
    
    validatePlayerPosition = function(source, targetCoords, maxDistance)
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return false end
        
        local playerCoords = GetEntityCoords(ped)
        return #(playerCoords - targetCoords) <= maxDistance
    end,
    
    validateInput = function(input, inputType)
        if inputType == 'source' then
            return input and input > 0 and input ~= 65535
        elseif inputType == 'networkId' then
            return input and type(input) == 'number'
        elseif inputType == 'amount' then
            return input and type(input) == 'number' and input > 0 and input <= 999999
        end
        return false
    end
}

local VehicleManager = {
    hasDriver = function(vehicle)
        return GetPedInVehicleSeat(vehicle, -1) > 0
    end,
    
    hasPassengers = function(vehicle)
        if GetPedInVehicleSeat(vehicle, 0) > 0 then return true end
        
        for i = 1, 6 do
            local ped = GetPedInVehicleSeat(vehicle, i)
            if ped and ped > 0 then return true end
        end
        
        return false
    end,
    
    getValidPassengerSeats = function(vehicle)
        local validSeats = {}
        
        for i = 1, #validPassengerSeats do
            local seatName = validPassengerSeats[i]
            local boneID = GetEntityBoneIndexByName(vehicle, seatName)
            
            if boneID and boneID > 0 and boneID ~= -1 then
                validSeats[#validSeats + 1] = { name = seatName, boneID = boneID }
            end
        end
        
        return validSeats
    end
}

local PackageSystem = {
    cleanupVehiclePackage = function(vehicle, reason)
        local vehicleKey = tostring(vehicle)
        vehiclePackages[vehicleKey] = nil
        
        if DoesEntityExist(vehicle) then
            Entity(vehicle).state:set('loadPackage', nil, true)
            Entity(vehicle).state:set('hasPackage', false, true)
        end
    end,
    
    isWithinAllowedTime = function()
        if not Config.packageSettings.timeRestricted then return true end
        
        local currentHour = tonumber(os.date("%H"))
        local startTime = Config.packageSettings.allowedStartTime
        local endTime = Config.packageSettings.allowedEndTime
        
        if startTime > endTime then
            return currentHour >= startTime or currentHour < endTime
        else
            return currentHour >= startTime and currentHour < endTime
        end
    end,
    
    getRandomPackageProp = function()
        local totalWeight = 0
        local props = {}
        
        for propHash, propData in pairs(Config.packageProps) do
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
        
        local firstProp = next(Config.packageProps)
        return firstProp, Config.packageProps[firstProp]
    end,
    
    getRewardFromProp = function(propHash)
        local propData = Config.packageProps[propHash]
        if not propData?.rewards then return nil end
        
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
}

lib.callback.register('eb-pettycrime-package:server:StealPackage', function(source, vehicleNetId)
    local src = source
    
    if not SecurityManager.validateInput(src, 'source') then
        return false, 'Invalid request'
    end
    
    if not SecurityManager.validateInput(vehicleNetId, 'networkId') then
        return false, 'Invalid vehicle'
    end
    
    local canPerform, timeLeft = SecurityManager.canPlayerPerformAction(src, 'steal_package', 2000)
    if not canPerform then
        return false, ('Please wait %d seconds before trying again'):format(timeLeft)
    end
    
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    
    if not vehicle or not DoesEntityExist(vehicle) then
        return false, 'Vehicle not found'
    end
    
    local vehCoords = GetEntityCoords(vehicle)
    if not SecurityManager.validatePlayerPosition(src, vehCoords, Config.packageSettings.interactionDistance * 2) then
        return false, 'Too far from vehicle'
    end
    
    local vehicleKey = tostring(vehicle)
    local packageData = vehiclePackages[vehicleKey]
    local hasPackageState = Entity(vehicle).state.hasPackage
    
    if not packageData and not hasPackageState then
        return false, 'No package found'
    end
    
    if not packageData then
        packageData = Entity(vehicle).state.loadPackage
    end
    
    if not packageData then
        return false, 'Package data error'
    end
    
    if Config.policeRequired then
        local hasEnoughPolice, requiredPolice, onlinePolice = exports['eb-pettycrime']:CheckPoliceRequirement()
        if not hasEnoughPolice then
            return false, ('Not enough police online! Need %d, currently %d'):format(requiredPolice, onlinePolice)
        end
    end
    
    local propHash = packageData.propHash or packageData.model
    if not propHash then
        return false, 'Package data error'
    end
    
    local rewardItem = PackageSystem.getRewardFromProp(propHash)
    if not rewardItem then
        return false, 'No reward available'
    end
    
    local amount = math.random(rewardItem.minAmount, rewardItem.maxAmount)
    
    if not exports.ox_inventory:CanCarryItem(src, rewardItem.item, amount) then
        return false, 'Your inventory is too full to carry this item!'
    end
    
    local success = exports.ox_inventory:AddItem(src, rewardItem.item, amount)
    
    if not success then
        return false, 'Failed to add item to inventory'
    end
    
    PackageSystem.cleanupVehiclePackage(vehicle, 'stolen')
    
    return true, 'success', rewardItem.item, amount
end)

lib.callback.register('eb-pettycrime-package:client:ValidateVehicle', function(source, vNetID)
    if not SecurityManager.validateInput(source, 'source') then return false end
    if not SecurityManager.validateInput(vNetID, 'networkId') then return false end
    
    local success, validationResult, boneID, seatName = pcall(function()
        local entity = NetworkGetEntityFromNetworkId(vNetID)
        
        local waitTime = 0
        while (not entity or entity == 0 or not DoesEntityExist(entity)) and waitTime < 2000 do
            Wait(50)
            entity = NetworkGetEntityFromNetworkId(vNetID)
            waitTime = waitTime + 50
        end
        
        if not entity or entity == 0 or not DoesEntityExist(entity) then
            return false
        end
        
        if VehicleManager.hasPassengers(entity) then
            return false
        end
        
        local validSeats = VehicleManager.getValidPassengerSeats(entity)
        
        if #validSeats == 0 then
            return false
        end
        
        local selectedSeat = validSeats[math.random(1, #validSeats)]
        
        return true, selectedSeat.boneID, selectedSeat.name
    end)
    
    if not success then
        return false
    end
    
    return validationResult, boneID, seatName
end)

AddEventHandler('entityCreated', function(handle)
    if Config.debug then
        print("DEBUG: Entity created, handle:", handle)
    end
    
    if not handle or not DoesEntityExist(handle) then 
        if Config.debug then
            print("DEBUG: Invalid handle or entity doesn't exist")
        end
        return 
    end
    
    local popType = GetEntityPopulationType(handle)
    local entityType = GetEntityType(handle)
    local vehicleType = GetVehicleType(handle)
    
    if Config.debug then
        print(string.format("DEBUG: PopType: %s, EntityType: %s, VehicleType: %s", popType, entityType, vehicleType))
    end
    
    if popType ~= 2 or entityType ~= 2 or vehicleType ~= 'automobile' then 
        if Config.debug then
            print("DEBUG: Failed vehicle type check")
        end
        return 
    end
    
    if Config.debug then
        print("DEBUG: Vehicle type check passed")
    end
    
    if VehicleManager.hasDriver(handle) or VehicleManager.hasPassengers(handle) then 
        if Config.debug then
            print("DEBUG: Vehicle has occupants, skipping")
        end
        return 
    end
    
    if Config.debug then
        print("DEBUG: No occupants, continuing...")
    end
    
    local model = GetEntityModel(handle)
    if Config.blacklistedModels?[model] then 
        if Config.debug then
            print("DEBUG: Vehicle model is blacklisted:", model)
        end
        return 
    end
    
    if Config.debug then
        print("DEBUG: Model check passed:", model)
    end
    
    local randomRoll = math.random(1, Config.packageSettings.percent or 100)
    if Config.debug then
        print("DEBUG: Random roll:", randomRoll, "needed: 1")
    end
    if randomRoll ~= 1 then 
        if Config.debug then
            print("DEBUG: Failed random roll")
        end
        return 
    end
    
    if Config.debug then
        print("DEBUG: Random roll passed!")
    end
    
    if not PackageSystem.isWithinAllowedTime() then 
        if Config.debug then
            print("DEBUG: Outside allowed time")
        end
        return 
    end
    
    if Config.debug then
        print("DEBUG: Time check passed")
    end
    
    if Config.policeRequired then
        local hasEnoughPolice = exports['eb-pettycrime']:CheckPoliceRequirement()
        if not hasEnoughPolice then 
            if Config.debug then
                print("DEBUG: Not enough police")
            end
            return 
        end
    end
    
    if Config.debug then
        print("DEBUG: Police check passed")
    end
    
    local vehicleKey = tostring(handle)
    if vehiclePackages[vehicleKey] then 
        if Config.debug then
            print("DEBUG: Vehicle already has package")
        end
        return 
    end
    
    local hasPackage = false
    local success = pcall(function()
        hasPackage = Entity(handle).state.hasPackage
    end)
    
    if not success or hasPackage then 
        if Config.debug then
            print("DEBUG: Entity state check failed or already has package")
        end
        return 
    end
    
    if not DoesEntityExist(handle) then 
        if Config.debug then
            print("DEBUG: Entity no longer exists")
        end
        return 
    end
    
    if Config.debug then
        print("DEBUG: Attempting to create package...")
    end
    
    local netId = NetworkGetNetworkIdFromEntity(handle)
    local owner = NetworkGetEntityOwner(handle)
    
    if not DoesEntityExist(handle) then 
        if Config.debug then
            print("DEBUG: Entity disappeared during network operations")
        end
        return 
    end
    
    local validationSuccess, boneID, seatName = lib.callback.await(
        'eb-pettycrime-package:client:ValidateVehicle',
        owner,
        netId
    )
    
    if not validationSuccess or not boneID or not seatName then 
        if Config.debug then
            print("DEBUG: Validation failed - boneID:", boneID, "seatName:", seatName)
        end
        return 
    end
    
    if not DoesEntityExist(handle) then 
        if Config.debug then
            print("DEBUG: Entity disappeared during validation")
        end
        return 
    end
    
    local selectedProp, propData = PackageSystem.getRandomPackageProp()
    
    local data = {
        model = selectedProp,
        boneID = boneID,
        rotation = math.random(0, 360) + 0.0,
        seatName = seatName,
        propHash = selectedProp
    }
    
    vehiclePackages[vehicleKey] = data
    
    if DoesEntityExist(handle) then
        Entity(handle).state:set('loadPackage', data, true)
        Entity(handle).state:set('hasPackage', true, true)
        if Config.debug then
            print("DEBUG: Package created successfully!")
        end
    else
        vehiclePackages[vehicleKey] = nil
        if Config.debug then
            print("DEBUG: Entity disappeared, cleaning up")
        end
    end
end)

AddEventHandler('entityRemoved', function(handle)
    if not handle then return end
    
    local vehicleKey = tostring(handle)
    if vehiclePackages[vehicleKey] then
        PackageSystem.cleanupVehiclePackage(handle, 'entity removed')
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        
        local currentTime = GetGameTimer()
        local cleaned = 0
        
        local expiredCooldowns = {}
        for key, timestamp in pairs(playerActionCooldowns) do
            if currentTime - timestamp > 300000 then
                expiredCooldowns[#expiredCooldowns + 1] = key
            end
        end
        
        for i = 1, #expiredCooldowns do
            playerActionCooldowns[expiredCooldowns[i]] = nil
            cleaned = cleaned + 1
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
            cleaned = cleaned + 1
        end
    end
end)

lib.addCommand('packagestats', {
    help = 'Check package spawn statistics',
    restricted = 'group.admin'
}, function(source)
    local vehicles = GetAllVehicles()
    local activePackages = 0
    local hasEnoughPolice, requiredPolice, onlinePolice = exports['eb-pettycrime']:CheckPoliceRequirement()
    local currentHour = tonumber(os.date("%H"))
    local timeAllowed = PackageSystem.isWithinAllowedTime()
    
    for i = 1, #vehicles do
        if DoesEntityExist(vehicles[i]) and Entity(vehicles[i]).state.hasPackage then
            activePackages = activePackages + 1
        end
    end
    
    local timeStatus = timeAllowed and "ALLOWED" or "BLOCKED"
    local timeRange = Config.packageSettings.timeRestricted and
        string.format(" (%02d:00-%02d:00)", Config.packageSettings.allowedStartTime, Config.packageSettings.allowedEndTime) or " (Always)"
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {0, 255, 0},
        multiline = true,
        args = {"System", ("Active packages: %d | Police: %d/%d | Time: %02d:00 (%s)%s | Tracked: %d"):format(
            activePackages, onlinePolice, requiredPolice, currentHour, timeStatus, timeRange,
            tableSize(vehiclePackages)
        )}
    })
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
end)

AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource ~= resourceName then return end
    
    local vehicles = GetAllVehicles()
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if vehicle and DoesEntityExist(vehicle) then
            PackageSystem.cleanupVehiclePackage(vehicle, 'resource stop')
        end
    end
    
    vehiclePackages = {}
    playerActionCooldowns = {}
end)