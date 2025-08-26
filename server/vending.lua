local Config = require'shared.config'
local Systems = require'shared.systems'
local ServerConfig = require'shared.server_config'

local robbedProps = {}
local playerActionCooldowns = {}

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

local function getPropId(coords)
    return string.format("%.2f_%.2f_%.2f", coords.x, coords.y, coords.z)
end

local function setCooldown(coords)
    local propId = getPropId(coords)
    local cooldownTime = os.time() + (Config.vending.robbedCooldown * 60)
    
    robbedProps[propId] = cooldownTime
    GlobalState['propCooldown_' .. propId] = cooldownTime
end

local function isOnCooldown(coords)
    local propId = getPropId(coords)
    
    if not robbedProps[propId] then return false end
    
    if os.time() >= robbedProps[propId] then
        robbedProps[propId] = nil
        GlobalState['propCooldown_' .. propId] = nil
        return false
    end
    
    return true, robbedProps[propId] - os.time()
end

lib.callback.register('eb-pettycrime-vend:server:CheckPoliceCount', function(source)
    if isPlayerRateLimited(source, 'police_check', 1000) then
        return false, locale('too_fast')
    end
    
    if not Systems.Security.validateInput(source, 'source') then
        return false, locale('invalid_request')
    end
    
    if not Config.policeRequired then return true, nil end
    
    local hasEnoughPolice, requiredPolice, onlinePolice = Systems.Police.checkRequirement()
    
    if not hasEnoughPolice then
        return false, locale('need_police_online', requiredPolice, onlinePolice)
    end
    
    return true, nil
end)

lib.callback.register('eb-pettycrime-vend:server:ProcessFailedRobbery', function(source, coords)
    if isPlayerRateLimited(source, 'rob_fail', 1000) then
        return false
    end
    
    if not Systems.Security.validateInput(source, 'source') then
        return false
    end
    
    if coords and not validatePlayerPosition(source, coords, 5.0) then
        return false
    end
    
    if not Systems.Lockpick.hasRequiredItem(source) then
        return false
    end
    
    Systems.Lockpick.processLockpickBreak(source, false)
    
    return true
end)

lib.callback.register('eb-pettycrime-vend:server:ProcessSuccessfulRobbery', function(source, robberyType, coords)
    if isPlayerRateLimited(source, 'rob_success', 5000) then
        return false, locale('wait_seconds', 5)
    end
    
    if not Systems.Security.validateInput(source, 'source') then
        return false, locale('invalid_request')
    end
    
    if not Systems.Security.validateInput(coords, 'coords') then
        return false, locale('invalid_request')
    end
    
    if not validatePlayerPosition(source, coords, 5.0) then
        return false, locale('too_far')
    end
    
    local onCooldown, timeRemaining = isOnCooldown(coords)
    if onCooldown then
        return false, locale('location_recently_robbed', math.ceil(timeRemaining / 60))
    end
    
    if not Systems.Lockpick.hasRequiredItem(source) then
        return false, locale('missing_required_item')
    end
    
    if Config.policeRequired then
        local hasEnoughPolice, requiredPolice, onlinePolice = Systems.Police.checkRequirement()
        if not hasEnoughPolice then
            return false, locale('need_police_online', requiredPolice, onlinePolice)
        end
    end
    
    setCooldown(coords)
    
    local rewardPool = ServerConfig.vendingRewards[robberyType]
    if not rewardPool then
        return false, locale('configuration_error')
    end
    
    local rewards = {}
    local totalValue = 0
    
    for _, reward in ipairs(rewardPool) do
        if math.random(1, 100) <= reward.chance then
            local amount = math.random(reward.min, reward.max)
            
            if exports.ox_inventory:CanCarryItem(source, reward.item, amount) then
                local success = exports.ox_inventory:AddItem(source, reward.item, amount)
                if success then
                    table.insert(rewards, {
                        item = reward.item,
                        amount = amount,
                        message = locale('found_item', amount, reward.label or reward.item)
                    })
                    
                    if reward.value then
                        totalValue = totalValue + (reward.value * amount)
                    end
                end
            else
                if robberyType == 'vending' then
                    if exports.ox_inventory:CanCarryItem(source, reward.item, 1) then
                        local success = exports.ox_inventory:AddItem(source, reward.item, 1)
                        if success then
                            table.insert(rewards, {
                                item = reward.item,
                                amount = 1,
                                message = locale('inventory_nearly_full', reward.label or reward.item)
                            })
                        end
                    end
                end
            end
        end
    end
    
    if #rewards == 0 then
        local consolationCash = math.random(5, 15)
        local success = exports.ox_inventory:AddItem(source, 'money', consolationCash)
        if success then
            table.insert(rewards, {
                item = 'money',
                amount = consolationCash,
                message = locale('found_cash', consolationCash)
            })
        end
    end
    
    Systems.Lockpick.processLockpickBreak(source, true)
    
    return true, 'Success', rewards
end)

CreateThread(function()
    while true do
        Wait(300000)
        
        local currentTime = os.time()
        local currentGameTime = GetGameTimer()
        
        for propId, cooldownTime in pairs(robbedProps) do
            if currentTime >= cooldownTime then
                robbedProps[propId] = nil
                GlobalState['propCooldown_' .. propId] = nil
            end
        end
        
        for key, timestamp in pairs(playerActionCooldowns) do
            if currentGameTime - timestamp > 600000 then
                playerActionCooldowns[key] = nil
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for key in pairs(playerActionCooldowns) do
        if string.find(key, tostring(src) .. '_') then
            playerActionCooldowns[key] = nil
        end
    end
end)

AddEventHandler('onResourceStop', function(r)
    if cache.resource ~= r then return end
    
    for propId in pairs(robbedProps) do
        GlobalState['propCooldown_' .. propId] = nil
    end
    
    robbedProps = {}
    playerActionCooldowns = {}
end)