local Config = require'shared.config'

local objects = {}
local packageVehicles = {}
local trackedVehicles = {}
local actionCooldowns = { lastStealAttempt = 0, STEAL_COOLDOWN = 3000 }

local validSeats = { 'seat_pside_f', 'seat_dside_r', 'seat_pside_r' }
local seatMappings = {
    windows = { ['seat_pside_f'] = 1, ['seat_dside_r'] = 2, ['seat_pside_r'] = 3 },
    doors = { ['seat_pside_f'] = 1, ['seat_dside_r'] = 2, ['seat_pside_r'] = 3 },
    names = { ['seat_pside_f'] = 'front passenger', ['seat_dside_r'] = 'rear driver', ['seat_pside_r'] = 'rear passenger' }
}

local function getSafeMapping(seatName, mappingType, fallback)
    return seatMappings[mappingType][seatName] or fallback
end

local function getValidSeats(entity)
    local validSeatList = {}
    
    for i = 1, #validSeats do
        local seatName = validSeats[i]
        local boneIndex = GetEntityBoneIndexByName(entity, seatName)
        
        if boneIndex and boneIndex ~= -1 and boneIndex ~= 0 then
            validSeatList[#validSeatList + 1] = { name = seatName, boneIndex = boneIndex }
        end
    end
    
    return validSeatList
end

local function isVehicleDoorOpen(vehicle, doorIndex)
    return GetVehicleDoorAngleRatio(vehicle, doorIndex) > 0.1
end

local DispatchManager = {
    sendTheftDispatch = function(coords)
        if not Config.useDispatch or GetResourceState('cd_dispatch') ~= 'started' then return end
        
        local data = exports['cd_dispatch']:GetPlayerInfo()
        
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = Config.dispatchJobs,
            coords = coords or data.coords,
            title = '10-90 - Package Theft',
            message = ('A %s stealing packages from vehicle at %s'):format(data.sex, data.street),
            flash = 0,
            unique_id = data.unique_id,
            sound = 1,
            blip = {
                sprite = 586, scale = 1.2, colour = 3, flashes = false,
                text = '911 - Package Theft', time = 5, radius = 0
            }
        })
    end,
    
    sendWitnessDispatch = function(witnessCoords)
        if not Config.useDispatch or GetResourceState('cd_dispatch') ~= 'started' then return end
        
        local data = exports['cd_dispatch']:GetPlayerInfo()
        
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = Config.dispatchJobs,
            coords = witnessCoords or data.coords,
            title = '10-66 - Suspicious Person',
            message = ('Witness reported %s stealing from vehicle at %s'):format(data.sex, data.street),
            flash = 0,
            unique_id = data.unique_id,
            sound = 1,
            blip = {
                sprite = 280, scale = 1.0, colour = 1, flashes = true,
                text = '911 - Suspicious Person', time = 5, radius = 0
            }
        })
    end
}

local WitnessManager = {
    checkForWitnesses = function(playerCoords)
        if not Config.packageSettings.witnessSystem then return end
        
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
                
                if distance <= Config.packageSettings.witnessDistance then
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
            if math.random(1, Config.packageSettings.witnessCallChance) == 1 then
                local witness = witnesses[i]
                
                TaskLookAtEntity(witness.ped, playerPed, 3000, 0, 2)
                TaskStartScenarioInPlace(witness.ped, "WORLD_HUMAN_MOBILE_FILM_SHOCKING", 0, true)
                
                SetTimeout(math.random(2000, 4000), function()
                    DispatchManager.sendWitnessDispatch(playerCoords)
                end)
                
                break
            end
        end
    end
}

local TargetManager = {
    createPackageTarget = function(vehicle, packageData)
        local targetId = 'package_vehicle_' .. vehicle
        local doorName = getSafeMapping(packageData.seatName, 'names', 'passenger')
        
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name = targetId .. '_steal',
                icon = 'fas fa-hand-paper',
                label = 'Steal package from ' .. doorName .. ' seat',
                distance = Config.packageSettings.interactionDistance,
                canInteract = function()
                    if not packageData?.windowIndex or not packageData?.doorIndex then return false end
                    
                    local windowBroken = not IsVehicleWindowIntact(vehicle, packageData.windowIndex)
                    local doorOpen = isVehicleDoorOpen(vehicle, packageData.doorIndex)
                    local canSteal = (GetGameTimer() - actionCooldowns.lastStealAttempt) >= actionCooldowns.STEAL_COOLDOWN
                    
                    return (windowBroken or doorOpen) and DoesEntityExist(packageData.packageEntity) and canSteal
                end,
                onSelect = function()
                    TheftManager.stealPackage(vehicle, packageData)
                end
            }
        })
        
        return targetId
    end,
    
    removePackageTarget = function(vehicle)
        local targetId = 'package_vehicle_' .. vehicle
        exports.ox_target:removeLocalEntity(vehicle, targetId .. '_steal')
    end
}

TheftManager = {
    stealPackage = function(vehicle, packageData)
        local currentTime = GetGameTimer()
        if (currentTime - actionCooldowns.lastStealAttempt) < actionCooldowns.STEAL_COOLDOWN then
            if Config.notifications then
                lib.notify({ title = 'Too Fast', description = 'You need to wait a moment', type = 'error' })
            end
            return
        end
        
        actionCooldowns.lastStealAttempt = currentTime
        
        if not DoesEntityExist(vehicle) or not Entity(vehicle).state.hasPackage then
            if Config.notifications then
                lib.notify({ title = 'Invalid Target', description = 'No package found', type = 'error' })
            end
            return
        end
        
        local playerCoords = GetEntityCoords(cache.ped)
        local vehicleCoords = GetEntityCoords(vehicle)
        if #(playerCoords - vehicleCoords) > Config.packageSettings.interactionDistance * 1.5 then
            if Config.notifications then
                lib.notify({ title = 'Too Far', description = 'You need to be closer', type = 'error' })
            end
            return
        end
        
        local windowBroken = not IsVehicleWindowIntact(vehicle, packageData.windowIndex)
        local doorOpen = isVehicleDoorOpen(vehicle, packageData.doorIndex)
        
        local progressConfig = {
            label = doorOpen and 'Grabbing package from open door...' or 'Reaching through broken window for package...',
            duration = doorOpen and (Config.packageSettings.stealTime * 0.7) or Config.packageSettings.stealTime,
            canCancel = true,
            position = 'bottom',
            disable = { car = true, move = true, combat = true },
            anim = { dict = 'mini@repair', clip = 'fixing_a_ped' }
        }
        
        WitnessManager.checkForWitnesses(playerCoords)
        
        if lib.progressCircle(progressConfig) then
            local success, message, item, amount = lib.callback.await(
                'eb-pettycrime-package:server:StealPackage',
                false,
                NetworkGetNetworkIdFromEntity(vehicle)
            )
            
            if success then
                TargetManager.removePackageTarget(vehicle)
                packageVehicles[vehicle] = nil
                DispatchManager.sendTheftDispatch(vehicleCoords)
                
                if Config.notifications then
                    lib.notify({
                        title = 'Package Stolen!',
                        description = ('You stole %dx %s'):format(amount or 1, item or 'item'),
                        type = 'success'
                    })
                end
            else
                if Config.notifications then
                    lib.notify({
                        title = 'Cannot Steal Package',
                        description = message or 'Unknown error',
                        type = 'error',
                        duration = 4000
                    })
                end
            end
        end
    end
}

local PackageManager = {
    cleanupPackage = function(vehicle, packageEntity)
        TargetManager.removePackageTarget(vehicle)
        
        if packageEntity and DoesEntityExist(packageEntity) then
            DeleteEntity(packageEntity)
            objects[packageEntity] = nil
        end
        
        packageVehicles[vehicle] = nil
        trackedVehicles[vehicle] = nil
    end,
    
    createPackage = function(vehicle, packageData)
        local modelHash = packageData.model
        
        lib.requestModel(modelHash)
        
        local coords = GetEntityCoords(vehicle)
        local package = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z - 5, false, true, false)
        SetModelAsNoLongerNeeded(modelHash)
        
        if not DoesEntityExist(package) then return nil end
        
        SetDisableFragDamage(package, true)
        SetEntityCollision(package, false, false)
        SetEntityNoCollisionEntity(package, vehicle, false)
        
        AttachEntityToEntity(
            package, vehicle, packageData.boneID,
            0.0, 0.0, 0.0, 0.0, 0.0, packageData.rotation or 0.0,
            0.0, false, false, false, false, 2, true, false
        )
        
        objects[package] = true
        return package
    end
}

lib.callback.register('eb-pettycrime-package:client:ValidateVehicle', function(vNetID)
    local entity = lib.waitFor(function()
        if NetworkDoesEntityExistWithNetworkId(vNetID) then
            return NetworkGetEntityFromNetworkId(vNetID)
        end
    end, 'Failed to get vehicle NetworkID', 5000)
    
    if not entity then return false end
    
    local validSeatList = getValidSeats(entity)
    if #validSeatList == 0 then return false end
    
    local selectedSeat = validSeatList[math.random(1, #validSeatList)]
    local boneID = selectedSeat.boneIndex
    
    if not boneID or boneID == 0 then return false end
    
    return true, boneID, selectedSeat.name
end)

AddStateBagChangeHandler('loadPackage', nil, function(bagName, key, value, reserved, replicated)
    if replicated then return end
    
    local vehicle = lib.waitFor(function()
        local e = GetEntityFromStateBagName(bagName)
        if e > 0 and DoesEntityExist(e) then return e end
    end, 'Failed to get vehicle from statebag', 5000)
    
    if not vehicle then return end
    
    if not value then
        if packageVehicles[vehicle] then
            PackageManager.cleanupPackage(vehicle, packageVehicles[vehicle].packageEntity)
        end
        return
    end
    
    if not value.model or not value.boneID or not value.seatName then return end
    
    trackedVehicles[vehicle] = true
    
    local package = PackageManager.createPackage(vehicle, value)
    if not package then return end
    
    local packageData = {
        packageEntity = package,
        seatName = value.seatName,
        windowIndex = getSafeMapping(value.seatName, 'windows', 1),
        doorIndex = getSafeMapping(value.seatName, 'doors', 1),
        doorName = getSafeMapping(value.seatName, 'names', 'passenger')
    }
    
    packageVehicles[vehicle] = packageData
    TargetManager.createPackageTarget(vehicle, packageData)
    
    CreateThread(function()
        local checkInterval = 1000
        local maxChecks = 300
        local checks = 0
        
        while DoesEntityExist(vehicle) and DoesEntityExist(package) and checks < maxChecks do
            local state = Entity(vehicle).state
            if not state.hasPackage then break end
            
            if not IsEntityAttachedToEntity(package, vehicle) then break end
            
            if checks > 60 then checkInterval = 5000 end
            
            Wait(checkInterval)
            checks = checks + 1
        end
        
        PackageManager.cleanupPackage(vehicle, package)
    end)
end)

AddStateBagChangeHandler('hasPackage', nil, function(bagName, key, value, reserved, replicated)
    if replicated or value then return end
    
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle and vehicle > 0 and DoesEntityExist(vehicle) and packageVehicles[vehicle] then
        PackageManager.cleanupPackage(vehicle, packageVehicles[vehicle].packageEntity)
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        
        local toCleanup = {}
        for vehicle in pairs(trackedVehicles) do
            if not DoesEntityExist(vehicle) then
                toCleanup[#toCleanup + 1] = vehicle
            end
        end
        
        local batchSize = 5
        for i = 1, #toCleanup, batchSize do
            for j = i, math.min(i + batchSize - 1, #toCleanup) do
                local vehicle = toCleanup[j]
                if packageVehicles[vehicle] then
                    PackageManager.cleanupPackage(vehicle, packageVehicles[vehicle].packageEntity)
                end
            end
            
            if i + batchSize <= #toCleanup then Wait(0) end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource ~= resourceName then return end
    
    for object in pairs(objects) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end
    
    for vehicle in pairs(packageVehicles) do
        TargetManager.removePackageTarget(vehicle)
    end
    
    objects = {}
    packageVehicles = {}
    trackedVehicles = {}
end)