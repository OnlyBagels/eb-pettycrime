lib.locale()

local Config = require'shared.config'
local Systems = require'shared.systems'

local lastRobAttempt = 0
local ROB_ATTEMPT_COOLDOWN = 3000
local propCooldowns = {}

local function loadAnimDict(dict)
    lib.requestAnimDict(dict)
end

local function notify(text, type)
    if Config.notifications then
        lib.notify({
            title = locale('robbery_title'),
            description = text,
            type = type or Config.NotifyTypes.info
        })
    end
end

local function clearPedState(ped)
    ClearPedTasks(ped)
    ClearPedTasksImmediately(ped)
    SetPedCanSwitchWeapon(ped, true)
    FreezeEntityPosition(ped, false)
end

local function getPropId(coords)
    return string.format("%.2f_%.2f_%.2f", coords.x, coords.y, coords.z)
end

local function checkPropCooldown(coords)
    local propId = getPropId(coords)
    
    if propCooldowns[propId] and GetGameTimer() < propCooldowns[propId] then
        return false
    end
    
    local cooldownTime = GlobalState['propCooldown_' .. propId]
    
    if cooldownTime and os.time() < cooldownTime then
        return false
    end
    
    return true
end

local function performRobbery(entity, robberyType, skillCheckDifficulty, progressLabel)
    if (GetGameTimer() - lastRobAttempt) < ROB_ATTEMPT_COOLDOWN then
        notify(locale('too_fast'), Config.NotifyTypes.error)
        return
    end
    
    if not DoesEntityExist(entity) then return end
    
    local entityCoords = GetEntityCoords(entity)
    local playerCoords = GetEntityCoords(cache.ped)
    local distance = #(playerCoords - entityCoords)
    
    if distance > 3.0 then
        notify(locale('too_far'), Config.NotifyTypes.error)
        return
    end
    
    if not checkPropCooldown(entityCoords) then return end
    
    if Config.lockpick.required and not exports.ox_inventory:Search('count', Config.lockpick.item) or 
       exports.ox_inventory:Search('count', Config.lockpick.item) < 1 then
        notify(locale('need_lockpick', Config.lockpick.item), Config.NotifyTypes.error)
        return
    end
    
    local hasEnoughPolice, policeMessage = lib.callback.await('eb-pettycrime-vend:server:CheckPoliceCount', false)
    if not hasEnoughPolice then
        notify(policeMessage or locale('not_enough_cops'), Config.NotifyTypes.error)
        return
    end
    
    lastRobAttempt = GetGameTimer()
    
    local propId = getPropId(entityCoords)
    propCooldowns[propId] = GetGameTimer() + (60 * 60 * 1000)
    
    local ped = cache.ped
    
    TaskTurnPedToFaceEntity(ped, entity, -1)
    Wait(1000)
    
    loadAnimDict('veh@break_in@0h@p_m_one@')
    TaskPlayAnim(ped, 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds', 8.0, 1.0, -1, 49, 0, 0, 0, 0)
    
    notify(locale('trying_lock'), Config.NotifyTypes.warning)
    
    local success = lib.skillCheck(skillCheckDifficulty, {'w', 'a', 's', 'd'})
    
    StopAnimTask(ped, 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds', 1.0)
    clearPedState(ped)
    
    if not success then
        notify(locale('lockpick_broken'), Config.NotifyTypes.error)
        lib.callback.await('eb-pettycrime-vend:server:ProcessFailedRobbery', false)
        
        if Config.dispatchOnFail then
            Systems.Dispatch.sendTheftDispatch(entityCoords, 'vending_robbery')
        end
        
        return
    end
    
    notify(locale('robbery_success'), Config.NotifyTypes.success)
    
    loadAnimDict('missheistfbi3b_ig7')
    TaskPlayAnim(ped, 'missheistfbi3b_ig7', 'lift_fibagent_loop', 8.0, 1.0, -1, 49, 0, 0, 0, 0)
    
    Systems.Witness.checkForWitnesses(playerCoords, 'vending_robbery')
    
    local progressSuccess = lib.progressBar({
        duration = Config.robberyTime.vending,
        label = locale(progressLabel),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, mouse = false }
    })
    
    StopAnimTask(ped, 'missheistfbi3b_ig7', 'lift_fibagent_loop', 1.0)
    clearPedState(ped)
    
    if progressSuccess then
        local success, message, rewards = lib.callback.await(
            'eb-pettycrime-vend:server:ProcessSuccessfulRobbery',
            false,
            robberyType,
            entityCoords
        )
        
        if success then
            Systems.Dispatch.sendTheftDispatch(entityCoords, 'vending_robbery')
            
            if rewards then
                for _, reward in ipairs(rewards) do
                    notify(reward.message, Config.NotifyTypes.success)
                end
            end
        else
            notify(message or locale('robbery_failed'), Config.NotifyTypes.error)
            propCooldowns[propId] = nil
        end
    else
        propCooldowns[propId] = nil
    end
end

function robVendingMachine(entity)
    performRobbery(
        entity,
        'vending',
        {'easy', 'easy', 'medium', 'medium', 'hard'},
        'progress_bar_text'
    )
end

function robParkingMeter(entity)
    performRobbery(
        entity,
        'parking_meter',
        {'easy', 'medium', 'medium', 'hard'},
        Config.parkingMeter.progressText
    )
end

function robNewspaperDispenser(entity)
    performRobbery(
        entity,
        'newspaper',
        {'easy', 'easy', 'medium'},
        Config.newspaper.progressText
    )
end

exports.ox_target:addModel(Config.vending.objects, {
    {
        name = 'vending_robbery',
        icon = Config.vending.objectIcon,
        label = locale(Config.vending.objectLabel),
        items = Config.lockpick.required and Config.lockpick.item or nil,
        distance = 2.5,
        onSelect = function(data)
            robVendingMachine(data.entity)
        end,
        canInteract = function(entity)
            if (GetGameTimer() - lastRobAttempt) < ROB_ATTEMPT_COOLDOWN then
                return false
            end
            
            local entityCoords = GetEntityCoords(entity)
            local hasLockpick = not Config.lockpick.required or exports.ox_inventory:Search('count', Config.lockpick.item) >= 1
            return hasLockpick and checkPropCooldown(entityCoords)
        end
    }
})

exports.ox_target:addModel(Config.newspaper.objects, {
    {
        name = 'newspaper_robbery',
        icon = Config.newspaper.icon,
        label = locale(Config.newspaper.label),
        items = Config.lockpick.required and Config.lockpick.item or nil,
        distance = 2.5,
        onSelect = function(data)
            robNewspaperDispenser(data.entity)
        end,
        canInteract = function(entity)
            if (GetGameTimer() - lastRobAttempt) < ROB_ATTEMPT_COOLDOWN then
                return false
            end
            
            local entityCoords = GetEntityCoords(entity)
            local hasLockpick = not Config.lockpick.required or exports.ox_inventory:Search('count', Config.lockpick.item) >= 1
            return hasLockpick and checkPropCooldown(entityCoords)
        end
    }
})

exports.ox_target:addModel(Config.parkingMeter.objects, {
    {
        name = 'parking_meter_robbery',
        icon = Config.parkingMeter.icon,
        label = locale(Config.parkingMeter.label),
        items = Config.lockpick.required and Config.lockpick.item or nil,
        distance = 2.5,
        onSelect = function(data)
            robParkingMeter(data.entity)
        end,
        canInteract = function(entity)
            if (GetGameTimer() - lastRobAttempt) < ROB_ATTEMPT_COOLDOWN then
                return false
            end
            
            local entityCoords = GetEntityCoords(entity)
            local hasLockpick = not Config.lockpick.required or exports.ox_inventory:Search('count', Config.lockpick.item) >= 1
            return hasLockpick and checkPropCooldown(entityCoords)
        end
    }
})

AddStateBagChangeHandler('propCooldown', 'global', function(bagName, key, value, reserved, replicated)
    if replicated then return end
    
    if Config.debug then
        local propId = key:gsub('propCooldown_', '')
        if value then
            local timeLeft = value - os.time()
            lib.print.debug(('Cooldown set for prop %s: %d seconds remaining'):format(propId, timeLeft))
        else
            lib.print.debug(('Cooldown cleared for prop %s'):format(propId))
        end
    end
end)

CreateThread(function()
    while true do
        Wait(300000)
        
        local currentTime = GetGameTimer()
        local cleaned = 0
        
        for propId, cooldownTime in pairs(propCooldowns) do
            if currentTime > cooldownTime then
                propCooldowns[propId] = nil
                cleaned = cleaned + 1
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(r)
    if cache.resource ~= r then return end
    
    propCooldowns = {}
    lastRobAttempt = 0
end)