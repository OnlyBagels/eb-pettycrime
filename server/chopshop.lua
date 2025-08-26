local Config = require'shared.config'
local Systems = require'shared.systems'
local ServerConfig = require'shared.server_config'

local vehicleChopData = {}
local playerActionCooldowns = {}
local playerLastChopTime = {}

local function isPlayerRateLimited(source, action, cooldownMs)
    local key = source .. '_' .. action
    local currentTime = GetGameTimer()
    
    if playerActionCooldowns[key] and (currentTime - playerActionCooldowns[key]) < cooldownMs then
        return true
    end
    
    playerActionCooldowns[key] = currentTime
    return false
end

local function validatePlayerPosition(source, targetCoords, maxDistance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    
    local playerCoords = GetEntityCoords(ped)
    return #(playerCoords - targetCoords) <= maxDistance
end

local function getVehicleFromPlayer(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    
    local playerCoords = GetEntityCoords(ped)
    local vehicles = GetAllVehicles()
    
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if DoesEntityExist(vehicle) then
            local vehCoords = GetEntityCoords(vehicle)
            local distance = #(playerCoords - vehCoords)
            
            if distance <= 10.0 then
                if Entity(vehicle).state.chopshopVehicle then
                    return vehicle, vehCoords
                end
            end
        end
    end
    
    return nil
end

local function validatePlayerInChopZone(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - Config.chopshop.zone.center)
    
    return distance <= Config.chopshop.zone.radius
end

RegisterNetEvent('pc:action:1')
AddEventHandler('pc:action:1', function(partIndex, vehicleModel)
    local src = source
    
    if isPlayerRateLimited(src, 'chop_part', 3000) then
        TriggerClientEvent('chopshop:notify', src, {
            title = locale('slow_down'),
            description = locale('wait_seconds', 3),
            type = 'error'
        })
        return
    end
    
    if not Systems.Security.validateInput(src, 'source') then return end
    if not Systems.Security.validateInput(partIndex, 'amount') then return end
    
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    
    if not validatePlayerInChopZone(src) then
        TriggerClientEvent('chopshop:notify', src, {
            title = locale('too_far_general'),
            description = locale('too_far_chopshop'),
            type = 'error'
        })
        return
    end
    
    local vehicle, vehicleCoords = getVehicleFromPlayer(src)
    if not vehicle then
        TriggerClientEvent('chopshop:notify', src, {
            title = locale('vehicle_no_exists'),
            description = locale('vehicle_no_exists'),
            type = 'error'
        })
        return
    end
    
    if not validatePlayerPosition(src, vehicleCoords, 10.0) then
        TriggerClientEvent('chopshop:notify', src, {
            title = locale('too_far_from_vehicle'),
            description = locale('too_far_from_vehicle'),
            type = 'error'
        })
        return
    end
    
    if Config.policeRequired then
        local hasEnoughPolice, requiredPolice, onlinePolice = Systems.Police.checkRequirement()
        if not hasEnoughPolice then
            TriggerClientEvent('chopshop:notify', src, {
                title = locale('cannot_chop'),
                description = locale('need_police_online', requiredPolice, onlinePolice),
                type = 'error'
            })
            return
        end
    end
    
    if not Config.chopshop.parts[partIndex] then return end
    
    local currentTime = os.time()
    if playerLastChopTime[src] and (currentTime - playerLastChopTime[src]) < (Config.chopshop.cooldown * 60) then
        local timeLeft = math.ceil(((Config.chopshop.cooldown * 60) - (currentTime - playerLastChopTime[src])) / 60)
        TriggerClientEvent('chopshop:notify', src, {
            title = locale('chopshop_cooldown'),
            description = locale('wait_minutes', timeLeft),
            type = 'error'
        })
        return
    end
    
    local vehicleKey = tostring(vehicle)
    if not vehicleChopData[vehicleKey] then
        vehicleChopData[vehicleKey] = {
            partsRemoved = {},
            startTime = currentTime,
            playerSource = src
        }
    end
    
    if vehicleChopData[vehicleKey].playerSource ~= src then
        return
    end
    
    if vehicleChopData[vehicleKey].partsRemoved[partIndex] then
        TriggerClientEvent('chopshop:notify', src, {
            title = locale('part_already_removed'),
            description = locale('part_already_removed'),
            type = 'error'
        })
        return
    end
    
    local timeSinceStart = currentTime - vehicleChopData[vehicleKey].startTime
    local partsRemoved = 0
    for _ in pairs(vehicleChopData[vehicleKey].partsRemoved) do
        partsRemoved = partsRemoved + 1
    end
    
    if partsRemoved > 0 and timeSinceStart < (partsRemoved * 10) then return end
    
    vehicleChopData[vehicleKey].partsRemoved[partIndex] = true
    
    local partRewards = ServerConfig.chopshopRewards[partIndex]
    if partRewards?.rewards then
        for item, chance in pairs(partRewards.rewards) do
            if math.random(1, 100) <= chance then
                local quantity = math.random(
                    partRewards.quantities[item].min,
                    partRewards.quantities[item].max
                )
                
                if exports.ox_inventory:CanCarryItem(src, item, quantity) then
                    exports.ox_inventory:AddItem(src, item, quantity)
                end
            end
        end
    end
    
    local steelAmount = math.random(1, 3)
    if exports.ox_inventory:CanCarryItem(src, 'steel', steelAmount) then
        exports.ox_inventory:AddItem(src, 'steel', steelAmount)
    end
    
    local totalParts = 0
    local removedParts = 0
    for partId in pairs(Config.chopshop.parts) do
        totalParts = totalParts + 1
        if vehicleChopData[vehicleKey].partsRemoved[partId] then
            removedParts = removedParts + 1
        end
    end
    
    if removedParts >= totalParts then
        playerLastChopTime[src] = currentTime
        TriggerEvent('pc:action:2', src, GetEntityModel(vehicle))
    end
end)

RegisterNetEvent('pc:action:2')
AddEventHandler('pc:action:2', function(playerId, vehicleModel)
    local src = playerId or source
    local player = exports.qbx_core:GetPlayer(src)
    
    if not player then return end
    
    if not validatePlayerInChopZone(src) then return end
    
    local vehicle = getVehicleFromPlayer(src)
    if not vehicle then return end
    
    local vehicleKey = tostring(vehicle)
    if not vehicleChopData[vehicleKey] or vehicleChopData[vehicleKey].playerSource ~= src then
        return
    end
    
    for item, amount in pairs(ServerConfig.chopshopCompletionBonus) do
        if exports.ox_inventory:CanCarryItem(src, item, amount) then
            exports.ox_inventory:AddItem(src, item, amount)
        end
    end
    
    vehicleChopData[vehicleKey] = nil
end)

CreateThread(function()
    while true do
        Wait(300000)
        local currentTime = GetGameTimer()
        local cleaned = 0
        
        for key, timestamp in pairs(playerActionCooldowns) do
            if currentTime - timestamp > 600000 then
                playerActionCooldowns[key] = nil
                cleaned = cleaned + 1
            end
        end
        
        local currentOsTime = os.time()
        for playerId, timestamp in pairs(playerLastChopTime) do
            if currentOsTime - timestamp > 7200 then
                playerLastChopTime[playerId] = nil
                cleaned = cleaned + 1
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    playerActionCooldowns[src .. '_chop_part'] = nil
    playerLastChopTime[src] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return resourceName end
    
    vehicleChopData = {}
    playerActionCooldowns = {}
    playerLastChopTime = {}
end)