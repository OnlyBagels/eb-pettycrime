local Config = require'shared.config'

local vehicleChopData = {}
local playerActionCooldowns = {}
local playerLastChopTime = {}

local function canPlayerPerformAction(source, action, cooldownMs)
    local key = source .. '_' .. action
    local currentTime = GetGameTimer()
    
    if playerActionCooldowns[key] and (currentTime - playerActionCooldowns[key]) < cooldownMs then
        return false, math.ceil((cooldownMs - (currentTime - playerActionCooldowns[key])) / 1000)
    end
    
    playerActionCooldowns[key] = currentTime
    return true
end

local function validatePlayerInChopZone(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - Config.chopshop.zone.center)
    
    return distance <= Config.chopshop.zone.radius
end

local function validateVehicleNearPlayer(source, vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    
    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(vehicle)
    local distance = #(playerCoords - vehicleCoords)
    
    return distance <= 10.0
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
                    return vehicle
                end
            end
        end
    end
    
    return nil
end

RegisterNetEvent('pc:action:1')
AddEventHandler('pc:action:1', function(partIndex, vehicleModel)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    
    if not player then return end
    
    if Config.policeRequired then
        local hasEnoughPolice, requiredPolice, onlinePolice = exports['eb-pettycrime']:CheckPoliceRequirement()
        if not hasEnoughPolice then
            TriggerClientEvent('chopshop:notify', src, {
                title = 'Cannot Chop',
                description = ('Need %d police online. Currently: %d'):format(requiredPolice, onlinePolice),
                type = 'error'
            })
            return
        end
    end
    
    local canPerform, timeLeft = canPlayerPerformAction(src, 'chop_part', 3000)
    if not canPerform then
        TriggerClientEvent('chopshop:notify', src, {
            title = 'Slow Down',
            description = ('Wait %d seconds before removing another part'):format(timeLeft),
            type = 'error'
        })
        return
    end
    
    if not validatePlayerInChopZone(src) then
        TriggerClientEvent('chopshop:notify', src, {
            title = 'Too Far',
            description = 'You need to be in the chopshop area',
            type = 'error'
        })
        return
    end
    
    local vehicle = getVehicleFromPlayer(src)
    if not vehicle then return end
    
    if not Config.chopshop.parts[partIndex] then return end
    
    local currentTime = os.time()
    if playerLastChopTime[src] and (currentTime - playerLastChopTime[src]) < (Config.chopshop.cooldown * 60) then
        local timeLeft = math.ceil(((Config.chopshop.cooldown * 60) - (currentTime - playerLastChopTime[src])) / 60)
        TriggerClientEvent('chopshop:notify', src, {
            title = 'Chopshop Cooldown',
            description = ('You must wait %d more minutes'):format(timeLeft),
            type = 'error'
        })
        return
    end
    
    local vehicleKey = tostring(vehicle)
    if not vehicleChopData[vehicleKey] then
        vehicleChopData[vehicleKey] = {
            partsRemoved = {},
            startTime = currentTime
        }
    end
    
    if vehicleChopData[vehicleKey].partsRemoved[partIndex] then return end
    
    local timeSinceStart = currentTime - vehicleChopData[vehicleKey].startTime
    local partsRemoved = 0
    for _ in pairs(vehicleChopData[vehicleKey].partsRemoved) do
        partsRemoved = partsRemoved + 1
    end
    
    if partsRemoved > 0 and timeSinceStart < (partsRemoved * 10) then return end
    
    vehicleChopData[vehicleKey].partsRemoved[partIndex] = true
    
    local itemsGiven = {}
    local partConfig = Config.chopshop.parts[partIndex]
    
    if partConfig?.rewards then
        for item, chance in pairs(partConfig.rewards) do
            if math.random(1, 100) <= chance then
                local quantity = math.random(
                    partConfig.quantities[item].min,
                    partConfig.quantities[item].max
                )
                local success = exports.ox_inventory:AddItem(src, item, quantity)
                if success then
                    table.insert(itemsGiven, {item = item, count = quantity})
                end
            end
        end
    end
    
    local steelAmount = math.random(1, 3)
    local steelSuccess = exports.ox_inventory:AddItem(src, 'steel', steelAmount)
    if steelSuccess then
        table.insert(itemsGiven, {item = 'steel', count = steelAmount})
    end
    
    if #itemsGiven > 0 then
        local itemText = ''
        for i, reward in ipairs(itemsGiven) do
            itemText = itemText .. reward.item .. ' x' .. reward.count
            if i < #itemsGiven then
                itemText = itemText .. ', '
            end
        end
        
        TriggerClientEvent('chopshop:notify', src, {
            title = 'Materials Obtained',
            description = 'You received: ' .. itemText,
            type = 'success'
        })
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
    
    local bonusItems = {}
    for item, amount in pairs(Config.chopshop.completionBonus) do
        local success = exports.ox_inventory:AddItem(src, item, amount)
        if success then
            table.insert(bonusItems, {item = item, count = amount})
        end
    end
    
    if #bonusItems > 0 then
        local bonusText = ''
        for i, bonus in ipairs(bonusItems) do
            bonusText = bonusText .. bonus.item .. ' x' .. bonus.count
            if i < #bonusItems then
                bonusText = bonusText .. ', '
            end
        end
        
        TriggerClientEvent('chopshop:notify', src, {
            title = 'Completion Bonus',
            description = 'Complete dismantling bonus: ' .. bonusText,
            type = 'success'
        })
    end
    
    local vehicle = getVehicleFromPlayer(src)
    if vehicle then
        local vehicleKey = tostring(vehicle)
        vehicleChopData[vehicleKey] = nil
    end
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
    if GetCurrentResourceName() ~= resourceName then return end
    
    vehicleChopData = {}
    playerActionCooldowns = {}
    playerLastChopTime = {}
end)