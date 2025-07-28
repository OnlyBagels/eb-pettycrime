local Config = require'shared.config'

local robbedProps = {}
local playerActionCooldowns = {}

local function canPlayerPerformAction(source, action, cooldownMs)
    local key = source .. '_' .. action
    local currentTime = GetGameTimer()
    
    if playerActionCooldowns[key] and (currentTime - playerActionCooldowns[key]) < cooldownMs then
        return false, math.ceil((cooldownMs - (currentTime - playerActionCooldowns[key])) / 1000)
    end
    
    playerActionCooldowns[key] = currentTime
    return true
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
    if not Config.policeRequired then return true, nil end
    
    local hasEnoughPolice, requiredPolice, onlinePolice = exports['eb-pettycrime']:CheckPoliceRequirement()
    
    if not hasEnoughPolice then
        return false, ('Need %d police online. Currently: %d'):format(requiredPolice, onlinePolice)
    end
    
    return true, nil
end)

lib.callback.register('eb-pettycrime-vend:server:ProcessFailedRobbery', function(source)
    local src = source
    
    local canPerform, timeLeft = canPlayerPerformAction(src, 'rob_fail', 1000)
    if not canPerform then return false end
    
    local hasLockpick = exports.ox_inventory:Search(src, 'count', Config.RequiredItem) >= 1
    if not hasLockpick then return false end
    
    if math.random(1, 100) <= Config.vending.lockpickBreakChance then
        exports.ox_inventory:RemoveItem(src, Config.RequiredItem, 1)
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Lockpick Broken',
            description = 'Your lockpick broke!',
            type = 'error'
        })
    end
    
    return true
end)

lib.callback.register('eb-pettycrime-vend:server:ProcessSuccessfulRobbery', function(source, robberyType, coords)
    local src = source
    
    local canPerform, timeLeft = canPlayerPerformAction(src, 'rob_success', 5000)
    if not canPerform then
        return false, ('Please wait %d seconds'):format(timeLeft)
    end
    
    if not validatePlayerPosition(src, coords, 5.0) then
        return false, 'Too far from target'
    end
    
    local onCooldown, timeRemaining = isOnCooldown(coords)
    if onCooldown then return false end
    
    local hasLockpick = exports.ox_inventory:Search(src, 'count', Config.RequiredItem) >= 1
    if not hasLockpick then
        return false, 'Missing required item'
    end
    
    setCooldown(coords)
    
    local rewardPool = Config.vending.rewards[robberyType]
    if not rewardPool then
        return false, 'Configuration error'
    end
    
    local rewards = {}
    local totalValue = 0
    
    for _, reward in ipairs(rewardPool) do
        if math.random(1, 100) <= reward.chance then
            local amount = math.random(reward.min, reward.max)
            
            if exports.ox_inventory:CanCarryItem(src, reward.item, amount) then
                exports.ox_inventory:AddItem(src, reward.item, amount)
                
                table.insert(rewards, {
                    item = reward.item,
                    amount = amount,
                    message = ('Found %dx %s'):format(amount, reward.label or reward.item)
                })
                
                if reward.value then
                    totalValue = totalValue + (reward.value * amount)
                end
            else
                if robberyType == 'vending' then
                    if exports.ox_inventory:CanCarryItem(src, reward.item, 1) then
                        exports.ox_inventory:AddItem(src, reward.item, 1)
                        table.insert(rewards, {
                            item = reward.item,
                            amount = 1,
                            message = 'Found 1x ' .. (reward.label or reward.item) .. ' (inventory nearly full)'
                        })
                    end
                end
            end
        end
    end
    
    if #rewards == 0 then
        local consolationCash = math.random(5, 15)
        exports.ox_inventory:AddItem(src, 'money', consolationCash)
        table.insert(rewards, {
            item = 'money',
            amount = consolationCash,
            message = ('Found $%d'):format(consolationCash)
        })
    end
    
    return true, 'Success', rewards
end)

CreateThread(function()
    while true do
        Wait(300000)
        
        local currentTime = os.time()
        local cleaned = 0
        
        for propId, cooldownTime in pairs(robbedProps) do
            if currentTime >= cooldownTime then
                robbedProps[propId] = nil
                GlobalState['propCooldown_' .. propId] = nil
                cleaned = cleaned + 1
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