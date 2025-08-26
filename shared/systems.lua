if not IsDuplicityVersion() then
    lib.locale()
end

local Config = require'shared.config'

local Systems = {}

Systems.Dispatch = {
    sendTheftDispatch = function(coords, dispatchType)
        if not Config.useDispatch or GetResourceState('cd_dispatch') ~= 'started' then return end
        
        local data = exports['cd_dispatch']:GetPlayerInfo()
        
        local dispatchData = {
            package_theft = {
                title = '10-90 - Package Theft',
                message = locale('dispatch_package_theft', data.sex, data.street),
                sprite = 586,
                text = '911 - Package Theft'
            },
            vending_robbery = {
                title = '10-90 - Vandalism',
                message = locale('dispatch_vending_robbery', data.sex, data.street),
                sprite = 459,
                text = '911 - Vandalism'
            },
            chopshop = {
                title = '10-99 - Stolen Vehicle',
                message = locale('dispatch_chopshop', data.sex, data.street),
                sprite = 595,
                text = '911 - Vehicle Chopping'
            },
            witness_call = {
                title = '10-66 - Suspicious Person',
                message = locale('dispatch_witness_call', data.sex, data.street),
                sprite = 280,
                text = '911 - Suspicious Person'
            }
        }
        
        local dispatch = dispatchData[dispatchType] or dispatchData.package_theft
        
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = Config.dispatchJobs,
            coords = coords or data.coords,
            title = dispatch.title,
            message = dispatch.message,
            flash = 0,
            unique_id = data.unique_id,
            sound = 1,
            blip = {
                sprite = dispatch.sprite, scale = 1.2, colour = 3, flashes = false,
                text = dispatch.text, time = 5, radius = 0
            }
        })
    end
}

Systems.Witness = {
    checkForWitnesses = function(playerCoords, dispatchType)
        if not Config.witnessSystem.enabled then return end
        
        local playerPed = cache.ped
        local nearbyPeds = GetGamePool('CPed')
        local witnesses = {}
        local batchSize = 10
        local processed = 0
        
        for i = 1, #nearbyPeds do
            local ped = nearbyPeds[i]
            
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
                local pedCoords = GetEntityCoords(ped)
                local distance = #(playerCoords - pedCoords)
                
                if distance <= Config.witnessSystem.distance then
                    if HasEntityClearLosToEntity(ped, playerPed, 17) then
                        witnesses[#witnesses + 1] = { ped = ped, coords = pedCoords, distance = distance }
                    end
                end
            end
            
            processed = processed + 1
            if processed >= batchSize then
                processed = 0
                Wait(0)
            end
        end
        
        for i = 1, #witnesses do
            if math.random(1, 100) <= Config.witnessSystem.callChance then
                local witness = witnesses[i]
                
                TaskLookAtEntity(witness.ped, playerPed, 3000, 0, 2)
                TaskStartScenarioInPlace(witness.ped, "WORLD_HUMAN_MOBILE_FILM_SHOCKING", 0, true)
                
                SetTimeout(math.random(2000, 4000), function()
                    Systems.Dispatch.sendTheftDispatch(playerCoords, 'witness_call')
                end)
                
                break
            end
        end
    end
}

Systems.Security = {
    validateInput = function(input, inputType)
        if inputType == 'source' then
            return input and input > 0 and input ~= 65535
        elseif inputType == 'networkId' then
            return input and type(input) == 'number'
        elseif inputType == 'amount' then
            return input and type(input) == 'number' and input > 0 and input <= 999999
        elseif inputType == 'coords' then
            return input and type(input) == 'vector3'
        end
        return false
    end,
    
    validatePlayerPosition = function(source, targetCoords, maxDistance)
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return false end
        
        local playerCoords = GetEntityCoords(ped)
        return #(playerCoords - targetCoords) <= maxDistance
    end,
    
    canPlayerPerformAction = function(source, action, cooldownMs, cooldownTable)
        local key = source .. '_' .. action
        local currentTime = GetGameTimer()
        
        if cooldownTable[key] and (currentTime - cooldownTable[key]) < cooldownMs then
            return false, math.ceil((cooldownMs - (currentTime - cooldownTable[key])) / 1000)
        end
        
        cooldownTable[key] = currentTime
        return true
    end
}

Systems.Lockpick = {
    hasRequiredItem = function(source)
        if not Config.lockpick.required then return true end
        return exports.ox_inventory:Search(source, 'count', Config.lockpick.item) >= 1
    end,
    
    processLockpickBreak = function(source, success)
        if not Config.lockpick.required then return end
        
        if not success and math.random(1, 100) <= Config.lockpick.breakChance then
            exports.ox_inventory:RemoveItem(source, Config.lockpick.item, 1)
            if Config.notifications then
                TriggerClientEvent('ox_lib:notify', source, {
                    title = locale('lockpick_broken'),
                    description = locale('lockpick_broken_desc'),
                    type = 'error'
                })
            end
            return true
        elseif success and Config.lockpick.removeOnSuccess then
            exports.ox_inventory:RemoveItem(source, Config.lockpick.item, 1)
            return false
        end
        return false
    end
}

if IsDuplicityVersion() then
    Systems.Police = {
        checkRequirement = function()
            if _G.PoliceModule then
                return _G.PoliceModule.CheckPoliceRequirement()
            else
                local requiredPolice = Config.GetRequiredPolice()
                return false, requiredPolice, 0
            end
        end
    }
end

Systems.Time = {
    isAllowedTime = function()
        return Config.IsWithinAllowedTime()
    end
}

return Systems